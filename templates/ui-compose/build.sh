#!/bin/bash
# Copyright 2026 AzoraLabs
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#
# Builds the reactive-ECS UI template.
#
# `check` type-checks the staged tree. `run` compiles it to a native executable
# and launches it - the window, Metal pipelines and text rasterisation are
# Objective-C calls, and `azora run` goes through the interpreter, which has no
# FFI. A GUI therefore has to be a native build; there is no interpreted path to
# a window.
#
# Staging copies each engine module to the path its `module` declaration names,
# because sibling discovery walks one source root and the engine is a separate
# repository of per-package `src/` directories.
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
ENGINE_DIR="${AZORA_ENGINE_SRC:-$APP_DIR/../..}"
AZORA="${AZORA_BIN:-$APP_DIR/../../../azora-lang/app/build/install/azora/bin/azora}"
BUILD_DIR="$APP_DIR/.azora-build"
STAGE="$BUILD_DIR/src"
ACTION="${1:-check}"
APP_NAME="ui-compose"

if [ ! -d "$ENGINE_DIR/packages" ]; then
    echo "error: azora-engine not found at $ENGINE_DIR" >&2
    echo "       set AZORA_ENGINE_SRC to its checkout" >&2
    exit 1
fi

# ── Stage: the IDE's own tree, then the engine modules it uses ───────────
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP_DIR/src/." "$STAGE/"

for f in $(find "$ENGINE_DIR/packages" -name '*.az'); do
    module="$(grep -m1 '^module ' "$f" | awk '{print $2}')"
    [ -z "$module" ] && continue
    case "$module" in
        engine.core|engine.io|engine.objc|engine.shaders|engine.math.*|\
        engine.platform|engine.gpu|engine.gpu.draw|engine.input|engine.font|\
        engine.ui|engine.ui.node|engine.ui.compose|engine.ui.systems|engine.ui.paint|engine.ui.runner|\
        engine.ecs|engine.ecs.*|engine.app)
            path="$(echo "$module" | tr '.' '/')"
            mkdir -p "$STAGE/$(dirname "$path")"
            cp "$f" "$STAGE/$path.az"
            ;;
    esac
done

if [ "$ACTION" = "check" ]; then
    exec "$AZORA" check "$STAGE/main.az"
fi

if [ "$ACTION" != "run" ] && [ "$ACTION" != "build" ]; then
    echo "usage: build.sh [check|build|run]" >&2
    exit 1
fi

# ── Native build ────────────────────────────────────────────────────────
# The link set is not hard-coded here: azpm reads the engine's package
# manifests and reports the frameworks each resolved package declares, so
# adding an engine package cannot silently produce a link error.
command -v clang >/dev/null 2>&1 || { echo "error: clang is required (xcode-select --install)" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "error: python3 is required (azpm resolver)" >&2; exit 1; }

NATIVE_FLAGS=""
while IFS=$'\t' read -r kind a b; do
    case "$kind" in
        FRAMEWORK) NATIVE_FLAGS="$NATIVE_FLAGS -framework $a" ;;
        LIB)       NATIVE_FLAGS="$NATIVE_FLAGS -l$a" ;;
    esac
done <<< "$(python3 "$ENGINE_DIR/tools/azpm.py" resolve "$APP_DIR")"

if [ -d "$ENGINE_DIR/native/macos" ]; then
    NATIVE_DIR="$ENGINE_DIR/native/macos"
elif [ -d "$ENGINE_DIR/runtime/build" ]; then
    NATIVE_DIR="$ENGINE_DIR/runtime/build"
else
    echo "error: no native runtime; build it in $ENGINE_DIR/runtime" >&2
    exit 1
fi

echo "ui-compose: compiling"
"$AZORA" compile llvm "$STAGE/main.az" > "$BUILD_DIR/$APP_NAME.ll"
if [ ! -s "$BUILD_DIR/$APP_NAME.ll" ]; then
    echo "error: compilation produced no output" >&2
    exit 1
fi

echo "ui-compose: linking"
clang "$BUILD_DIR/$APP_NAME.ll" \
    -L "$NATIVE_DIR" -lazora_runtime \
    -Wl,-rpath,"$NATIVE_DIR" \
    $NATIVE_FLAGS \
    -Wno-override-module \
    -o "$BUILD_DIR/$APP_NAME"

echo "ui-compose: built $BUILD_DIR/$APP_NAME"
if [ "$ACTION" = "run" ]; then
    exec "$BUILD_DIR/$APP_NAME"
fi
