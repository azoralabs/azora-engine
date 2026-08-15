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
# Builds the Azora Engine FFI plumbing library (libazora_runtime.dylib / .so).
#
# This library contains no platform logic — the platform layer (Cocoa window,
# Metal renderer, CoreText) is written in the Azora language (engine/*.az).
# See runtime/src/ffi/az_ffi.c.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="${1:-$SCRIPT_DIR/build}"
mkdir -p "$OUT_DIR"

OS="$(uname -s)"
CC="${CC:-clang}"

case "$OS" in
    Darwin)
        echo "azora-engine runtime: building FFI shim (macOS)"
        "$CC" -O2 -dynamiclib \
            "$SCRIPT_DIR/src/ffi/az_ffi.c" \
            -lobjc -lm \
            -install_name @rpath/libazora_runtime.dylib \
            -o "$OUT_DIR/libazora_runtime.dylib"
        echo "→ $OUT_DIR/libazora_runtime.dylib"
        ;;
    *)
        echo "azora-engine runtime: building FFI shim ($OS) — platform renderer (Vulkan) planned"
        "$CC" -O2 -shared -fPIC \
            "$SCRIPT_DIR/src/ffi/az_ffi.c" \
            -lm \
            -o "$OUT_DIR/libazora_runtime.so"
        echo "→ $OUT_DIR/libazora_runtime.so"
        ;;
esac
