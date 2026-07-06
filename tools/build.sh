#!/bin/bash
# Azora Engine — project build tool.
#
# Compiles an Azora Engine project (engine sources + project src/*.az) to a
# native executable via the Azora compiler's LLVM backend and clang, linking
# against the engine's native runtime.
#
# Usage: build.sh <project_dir> [build|run]
#
# Layout expectations (a library bundle install):
#   <lib>/engine/*.az                    engine core (Azora language)
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

# ── Collect sources: engine core + project src ───────────────────────────
if [ ! -d "$PROJECT_DIR/src" ]; then
    echo "error: no src/ directory in $PROJECT_DIR" >&2
    exit 1
fi

rm -rf "$SRC_DIR"
mkdir -p "$SRC_DIR"
cp "$LIB_DIR/engine/"*.az "$SRC_DIR/"
cp "$PROJECT_DIR/src/"*.az "$SRC_DIR/"

if [ ! -f "$SRC_DIR/main.az" ]; then
    echo "error: project has no src/main.az entry point" >&2
    exit 1
fi

# ── Azora → LLVM IR ──────────────────────────────────────────────────────
CLASSPATH=""
for jar in "$LIB_DIR/tools/azorac/lib/"*.jar; do
    [ -f "$jar" ] || continue
    CLASSPATH="${CLASSPATH:+$CLASSPATH:}$jar"
done
if [ -z "$CLASSPATH" ]; then
    echo "error: bundled Azora compiler not found in $LIB_DIR/tools/azorac/lib" >&2
    exit 1
fi

APP_NAME="$(basename "$PROJECT_DIR" | tr -cd '[:alnum:]_-')"
[ -n "$APP_NAME" ] || APP_NAME="app"

echo "azora-engine: compiling ($APP_NAME)"
"$JAVA_BIN" -cp "$CLASSPATH" dev.azora.lang.MainKt compile llvm "$SRC_DIR/main.az" \
    > "$BUILD_DIR/$APP_NAME.ll"

if [ ! -s "$BUILD_DIR/$APP_NAME.ll" ]; then
    echo "error: Azora compilation produced no output (see errors above)." >&2
    exit 1
fi

# ── LLVM IR → native executable ──────────────────────────────────────────
OS="$(uname -s)"
case "$OS" in
    Darwin) NATIVE_DIR="$LIB_DIR/native/macos" ;;
    *)      NATIVE_DIR="$LIB_DIR/native/linux" ;;
esac

if [ ! -d "$NATIVE_DIR" ]; then
    echo "error: no native runtime for $OS in this library build ($NATIVE_DIR missing)." >&2
    exit 1
fi

echo "azora-engine: linking"
"$CLANG_BIN" "$BUILD_DIR/$APP_NAME.ll" \
    -L "$NATIVE_DIR" -lazora_runtime \
    -Wl,-rpath,"$NATIVE_DIR" \
    -Wno-override-module \
    -o "$BUILD_DIR/$APP_NAME"

echo "azora-engine: built $BUILD_DIR/$APP_NAME"

if [ "$ACTION" = "run" ]; then
    echo "azora-engine: launching"
    exec "$BUILD_DIR/$APP_NAME"
fi
