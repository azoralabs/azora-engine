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
#   <lib>/engine/<module>/*.az           engine modules (Azora language)
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

# ── Collect sources: selected engine modules + project src ───────────────
if [ ! -d "$PROJECT_DIR/src" ]; then
    echo "error: no src/ directory in $PROJECT_DIR" >&2
    exit 1
fi

rm -rf "$SRC_DIR"
mkdir -p "$SRC_DIR"

ENGINE_MODULES=""
append_engine_module() {
    local module="$1"
    if [ ! -d "$LIB_DIR/engine/$module" ]; then
        echo "warning: unknown engine module '$module' (ignored)" >&2
        return
    fi
    case " $ENGINE_MODULES " in
        *" $module "*) ;;
        *) ENGINE_MODULES="$ENGINE_MODULES $module" ;;
    esac
}

add_engine_module() {
    local module="$1"
    case "$module" in
        gpu)
            add_engine_module "objc"
            add_engine_module "math"
            add_engine_module "shaders"
            append_engine_module "gpu"
            ;;
        platform)
            add_engine_module "input"
            add_engine_module "gpu"
            append_engine_module "platform"
            ;;
        ui)
            add_engine_module "platform"
            append_engine_module "ui"
            ;;
        render)
            add_engine_module "ui"
            append_engine_module "render"
            ;;
        ecs)
            add_engine_module "core"
            append_engine_module "ecs"
            ;;
        jobs|concurrency)
            add_engine_module "core"
            append_engine_module "jobs"
            ;;
        engine|all)
            for dir in "$LIB_DIR/engine/"*/; do
                [ -d "$dir" ] || continue
                add_engine_module "$(basename "$dir")"
            done
            ;;
        *)
            append_engine_module "$module"
            ;;
    esac
}

ENGINE_USES="$(
    awk '
        /^[[:space:]]*use[[:space:]]+engine([[:space:]]|$)/ { print "engine" }
        /^[[:space:]]*use[[:space:]]+engine\./ {
            line = $0
            sub(/^[[:space:]]*use[[:space:]]+engine\./, "", line)
            sub(/[[:space:]].*/, "", line)
            print line
        }
    ' "$PROJECT_DIR"/src/*.az
)"

if [ -z "$ENGINE_USES" ]; then
    add_engine_module "engine"
else
    for module in $ENGINE_USES; do
        add_engine_module "$module"
    done
fi

for module in $ENGINE_MODULES; do
    mkdir -p "$SRC_DIR/engine/$module"
    for file in "$LIB_DIR/engine/$module/"*.az; do
        [ -f "$file" ] || continue
        cp "$file" "$SRC_DIR/engine/$module/"
    done
done

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
# The platform layer is Azora code calling the OS directly, so the final link
# pulls in the system frameworks it uses (Cocoa/Metal/CoreText/…) plus the
# engine's small FFI shim (libazora_runtime).
OS="$(uname -s)"
case "$OS" in
    Darwin)
        NATIVE_DIR="$LIB_DIR/native/macos"
        PLATFORM_LIBS="-lobjc -framework Cocoa -framework Metal -framework QuartzCore -framework CoreText -framework CoreGraphics -framework CoreFoundation"
        ;;
    *)
        echo "error: only macOS is supported right now (Vulkan backend planned)." >&2
        exit 1
        ;;
esac

if [ ! -d "$NATIVE_DIR" ]; then
    echo "error: no native runtime for $OS in this library build ($NATIVE_DIR missing)." >&2
    exit 1
fi

echo "azora-engine: linking"
"$CLANG_BIN" "$BUILD_DIR/$APP_NAME.ll" \
    -L "$NATIVE_DIR" -lazora_runtime \
    -Wl,-rpath,"$NATIVE_DIR" \
    $PLATFORM_LIBS \
    -Wno-override-module \
    -o "$BUILD_DIR/$APP_NAME"

echo "azora-engine: built $BUILD_DIR/$APP_NAME"

if [ "$ACTION" = "run" ]; then
    echo "azora-engine: launching"
    exec "$BUILD_DIR/$APP_NAME"
fi
