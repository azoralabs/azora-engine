#!/bin/bash
# Azora Engine — library bundle packager.
#
# Assembles the installable library bundle that Azora Studio consumes
# (Project Browser → Libraries → Install):
#
#   dist/azora-engine-<version>/
#     library.json                       manifest (id, version, templates)
#     engine/*.az                        engine core, Azora language
#     runtime/include/azora_runtime.h    native ABI reference
#     native/macos/libazora_runtime.dylib
#     tools/build.sh                     project build tool
#     tools/azorac/lib/*.jar             bundled Azora compiler CLI
#     templates/{app,game}/              project templates
#
# Also produces dist/azora-engine-<version>.azlib (a zip) for distribution.
#
# Usage: package.sh [--azora-lang <path>]
#   --azora-lang  Path to the azora-lang repository used to build the
#                 bundled compiler (default: ../azora-lang next to this repo).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
AZORA_LANG_DIR="${ROOT_DIR}/../azora-lang"

while [ $# -gt 0 ]; do
    case "$1" in
        --azora-lang) AZORA_LANG_DIR="$2"; shift 2 ;;
        *) echo "unknown option: $1" >&2; exit 1 ;;
    esac
done

VERSION="$(python3 -c "import json;print(json.load(open('$ROOT_DIR/library.json'))['version'])")"
LIB_ID="$(python3 -c "import json;print(json.load(open('$ROOT_DIR/library.json'))['id'])")"
DIST="$ROOT_DIR/dist/$LIB_ID-$VERSION"

echo "azora-engine: packaging $LIB_ID $VERSION"

# ── 1. Native runtime ────────────────────────────────────────────────────
"$ROOT_DIR/runtime/build.sh" "$ROOT_DIR/runtime/build" >/dev/null
echo "  ✓ native runtime"

# ── 2. Bundled Azora compiler ────────────────────────────────────────────
if [ ! -d "$AZORA_LANG_DIR" ]; then
    echo "error: azora-lang repository not found at $AZORA_LANG_DIR (use --azora-lang)" >&2
    exit 1
fi
(cd "$AZORA_LANG_DIR" && ./gradlew :app:installDist -q)
AZORAC_LIB="$AZORA_LANG_DIR/app/build/install/azora/lib"
if [ ! -d "$AZORAC_LIB" ]; then
    echo "error: azora compiler distribution missing at $AZORAC_LIB" >&2
    exit 1
fi
echo "  ✓ azora compiler"

# ── 3. Assemble the bundle ───────────────────────────────────────────────
rm -rf "$DIST"
mkdir -p "$DIST/engine" "$DIST/native/macos" "$DIST/tools/azorac/lib" \
         "$DIST/runtime/include" "$DIST/templates"

cp "$ROOT_DIR/library.json" "$DIST/"
cp "$ROOT_DIR/engine/"*.az "$DIST/engine/"
cp "$ROOT_DIR/runtime/include/azora_runtime.h" "$DIST/runtime/include/"
cp "$ROOT_DIR/tools/build.sh" "$DIST/tools/"
cp "$AZORAC_LIB/"*.jar "$DIST/tools/azorac/lib/"
cp -R "$ROOT_DIR/templates/app" "$DIST/templates/app"
cp -R "$ROOT_DIR/templates/game" "$DIST/templates/game"

case "$(uname -s)" in
    Darwin) cp "$ROOT_DIR/runtime/build/libazora_runtime.dylib" "$DIST/native/macos/" ;;
    *)      mkdir -p "$DIST/native/linux"
            cp "$ROOT_DIR/runtime/build/libazora_runtime.so" "$DIST/native/linux/" ;;
esac
echo "  ✓ bundle assembled"

# ── 4. Zip as .azlib ─────────────────────────────────────────────────────
(cd "$ROOT_DIR/dist" && rm -f "$LIB_ID-$VERSION.azlib" \
    && zip -qr "$LIB_ID-$VERSION.azlib" "$LIB_ID-$VERSION")
echo "  ✓ $ROOT_DIR/dist/$LIB_ID-$VERSION.azlib"

echo "done: $DIST"
