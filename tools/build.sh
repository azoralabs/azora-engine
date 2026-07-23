#!/bin/bash
# Azora Engine — project build tool.
#
# Compiles an Azora Engine project (its resolved engine packages + the project's
# own src/*.az) to a native executable via the Azora compiler's LLVM backend and
# clang, linking against the frameworks the resolved packages declare.
#
# The set of engine packages to stage and the native frameworks/libs to link are
# resolved from the .azon package manifests by tools/azpm.py — there is no
# hard-coded dependency graph or framework list here.
#
# Usage: build.sh <project_dir> [build|run]
#
# Layout expectations (a workspace checkout or an installed bundle):
#   <lib>/workspace.azon
#   <lib>/packages/<pkg>/{package.azon, src/*.az}
#   <lib>/tools/{azon.py, azpm.py}
#   <lib>/native/macos/libazora_runtime.dylib
#   <lib>/tools/azorac/lib/*.jar         bundled Azora compiler CLI
set -euo pipefail

LIB_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="${1:?usage: build.sh <project_dir> [build|run]}"
ACTION="${2:-run}"

PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
BUILD_DIR="$PROJECT_DIR/.azora-build"
SRC_DIR="$BUILD_DIR/src"

# ── Locate a JVM (for the bundled Azora compiler) ────────────────────────
find_java() {
    if [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/java" ]; then
        echo "$JAVA_HOME/bin/java"; return
    fi
    if command -v java >/dev/null 2>&1; then
        command -v java; return
    fi
    if [ -x /usr/libexec/java_home ]; then
        local home
        home="$(/usr/libexec/java_home 2>/dev/null || true)"
        if [ -n "$home" ] && [ -x "$home/bin/java" ]; then
            echo "$home/bin/java"; return
        fi
    fi
    echo ""
}

JAVA_BIN="$(find_java)"
if [ -z "$JAVA_BIN" ]; then
    echo "error: Java 17+ is required to run the Azora compiler (set JAVA_HOME or install a JDK)." >&2
    exit 1
fi

# ── Locate clang ─────────────────────────────────────────────────────────
find_clang() {
    if command -v clang >/dev/null 2>&1; then
        command -v clang; return
    fi
    if command -v xcrun >/dev/null 2>&1; then
        xcrun -f clang 2>/dev/null || true; return
    fi
    echo ""
}

CLANG_BIN="$(find_clang)"
if [ -z "$CLANG_BIN" ]; then
    echo "error: clang is required (install the Xcode Command Line Tools: xcode-select --install)." >&2
    exit 1
fi

PYTHON_BIN="$(command -v python3 || true)"
if [ -z "$PYTHON_BIN" ]; then
    echo "error: python3 is required (used by the azpm package resolver)." >&2
    exit 1
fi

# ── Collect sources: resolved engine packages + project src ──────────────
if [ ! -d "$PROJECT_DIR/src" ]; then
    echo "error: no src/ directory in $PROJECT_DIR" >&2
    exit 1
fi

rm -rf "$SRC_DIR"
mkdir -p "$SRC_DIR"

# azpm resolves the project's `import engine[.x]` statements to a package
# closure, telling us which source dirs to stage where and what to link.
RESOLVE="$("$PYTHON_BIN" "$LIB_DIR/tools/azpm.py" resolve "$PROJECT_DIR")"

NATIVE_FLAGS=""
while IFS=$'\t' read -r kind a b; do
    case "$kind" in
        STAGE)
            mkdir -p "$SRC_DIR/$b"
            cp "$a/"*.az "$SRC_DIR/$b/" 2>/dev/null || true
            ;;
        FRAMEWORK) NATIVE_FLAGS="$NATIVE_FLAGS -framework $a" ;;
        LIB)       NATIVE_FLAGS="$NATIVE_FLAGS -l$a" ;;
    esac
done <<< "$RESOLVE"

cp "$PROJECT_DIR/src/"*.az "$SRC_DIR/"

if [ ! -f "$SRC_DIR/main.az" ]; then
    echo "error: project has no src/main.az entry point" >&2
    exit 1
fi

APP_NAME="$(basename "$PROJECT_DIR" | tr -cd '[:alnum:]_-')"
[ -n "$APP_NAME" ] || APP_NAME="app"

echo "azora-engine: compiling ($APP_NAME)"
if [ -n "${AZORA_COMPILER_BIN:-}" ]; then
    if [ ! -x "$AZORA_COMPILER_BIN" ]; then
        echo "error: AZORA_COMPILER_BIN is not executable: $AZORA_COMPILER_BIN" >&2
        exit 1
    fi
    "$AZORA_COMPILER_BIN" compile llvm "$SRC_DIR/main.az" > "$BUILD_DIR/$APP_NAME.ll"
else
    CLASSPATH=""
    for jar in "$LIB_DIR/tools/azorac/lib/"*.jar; do
        [ -f "$jar" ] || continue
        CLASSPATH="${CLASSPATH:+$CLASSPATH:}$jar"
    done
    if [ -z "$CLASSPATH" ]; then
        echo "error: bundled Azora compiler not found in $LIB_DIR/tools/azorac/lib" >&2
        exit 1
    fi
    "$JAVA_BIN" -cp "$CLASSPATH" dev.azora.lang.MainKt compile llvm "$SRC_DIR/main.az" \
        > "$BUILD_DIR/$APP_NAME.ll"
fi

if [ ! -s "$BUILD_DIR/$APP_NAME.ll" ]; then
    echo "error: Azora compilation produced no output (see errors above)." >&2
    exit 1
fi

# ── LLVM IR → native executable ──────────────────────────────────────────
# The platform layer is Azora code calling the OS directly, so the final link
# pulls in the system frameworks the resolved packages declared plus the
# engine's small FFI shim (libazora_runtime).
OS="$(uname -s)"
case "$OS" in
    Darwin) NATIVE_DIR="$LIB_DIR/native/macos" ;;
    *)
        echo "error: only macOS is supported right now (Vulkan backend planned)." >&2
        exit 1
        ;;
esac

if [ ! -d "$NATIVE_DIR" ]; then
    # Workspace checkouts keep the freshly built runtime under runtime/build;
    # installed engine bundles use native/<platform>.
    if [ -d "$LIB_DIR/runtime/build" ]; then
        NATIVE_DIR="$LIB_DIR/runtime/build"
    else
        echo "error: no native runtime for $OS in this build ($NATIVE_DIR missing)." >&2
        exit 1
    fi
fi

echo "azora-engine: linking"
"$CLANG_BIN" "$BUILD_DIR/$APP_NAME.ll" \
    -L "$NATIVE_DIR" -lazora_runtime \
    -Wl,-rpath,"$NATIVE_DIR" \
    $NATIVE_FLAGS \
    -Wno-override-module \
    -o "$BUILD_DIR/$APP_NAME"

echo "azora-engine: built $BUILD_DIR/$APP_NAME"

if [ "$ACTION" = "run" ]; then
    echo "azora-engine: launching"
    exec "$BUILD_DIR/$APP_NAME"
fi
