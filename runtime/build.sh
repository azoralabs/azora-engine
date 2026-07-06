#!/bin/bash
# Builds the Azora Engine native runtime library (libazora_runtime.dylib / .so).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="${1:-$SCRIPT_DIR/build}"
mkdir -p "$OUT_DIR"

OS="$(uname -s)"

CC="${CC:-clang}"

case "$OS" in
    Darwin)
        echo "azora-engine runtime: building Metal backend (macOS)"
        "$CC" -fobjc-arc -O2 -dynamiclib \
            "$SCRIPT_DIR/src/macos/azrt_macos.m" \
            -framework Cocoa -framework Metal -framework QuartzCore \
            -install_name @rpath/libazora_runtime.dylib \
            -o "$OUT_DIR/libazora_runtime.dylib"
        echo "→ $OUT_DIR/libazora_runtime.dylib"
        ;;
    *)
        echo "azora-engine runtime: building stub backend ($OS) — Vulkan backend planned"
        "$CC" -O2 -shared -fPIC \
            "$SCRIPT_DIR/src/stub/azrt_stub.c" \
            -o "$OUT_DIR/libazora_runtime.so"
        echo "→ $OUT_DIR/libazora_runtime.so"
        ;;
esac
