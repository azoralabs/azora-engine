#!/usr/bin/env bash
# Generate Metal libraries ahead of launch. The runtime uses the same compiler for editable graphs.
set -euo pipefail
ENGINE="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="${1:?usage: fusion-cook.sh PROJECT COMPILER CLANG RUNTIME}"
COMPILER="${2:-}"
CLANG="${3:-/usr/bin/clang}"
RUNTIME="${4:-$ENGINE/runtime/build}"
CACHE="$PROJECT/.azora-build/fusion"

assets=()
while IFS= read -r -d '' asset; do assets+=("$asset"); done < <(
    find "$PROJECT" -name '.*' -type d ! -path "$PROJECT" -prune -o -type f \( -name '*.azfusion' -o -name '*.azmaterial' \) -print0
)
[ "${#assets[@]}" -gt 0 ] || exit 0
[ "$(uname -s)" = Darwin ] || exit 0
if [ ! -x "$COMPILER" ]; then
    echo "Material Fusion: native compiler unavailable, pipelines will prepare on load."
    exit 0
fi
if ! /usr/bin/xcrun -sdk macosx metal --version >/dev/null 2>&1; then
    echo "Material Fusion: Xcode Metal Toolchain unavailable, pipelines will prepare on load."
    exit 0
fi

mkdir -p "$CACHE"
TEMP="$(mktemp -d "$CACHE/.cook-XXXXXX")"
trap 'rm -rf "$TEMP"' EXIT
mkdir -p "$TEMP/src"
cp "$ENGINE/packages/azora-material-fusion/tools/emit.az" "$TEMP/src/main.az"
STAGES="$(python3 "$ENGINE/tools/azpm.py" resolve "$TEMP")"
FLAGS=()
while IFS=$'\t' read -r kind source destination; do
    case "$kind" in
        STAGE)
            mkdir -p "$TEMP/src/$destination"
            cp "$source/"*.az "$TEMP/src/$destination/"
            ;;
        FRAMEWORK) FLAGS+=(-framework "$source") ;;
        LIB) FLAGS+=("-l$source") ;;
    esac
done <<< "$STAGES"
"$COMPILER" compile llvm "$TEMP/src/main.az" >"$TEMP/emit.ll"
"$CLANG" -Wno-override-module "$TEMP/emit.ll" -L "$RUNTIME" -lazora_runtime -Wl,-rpath,"$RUNTIME" "${FLAGS[@]}" -o "$TEMP/emit"

for asset in "${assets[@]}"; do
    relative="${asset#"$PROJECT"/}"
    if ! AZORA_FUSION_ASSET="$asset" "$TEMP/emit" > "$TEMP/emitted.txt"; then
        echo "Material Fusion: could not compile $relative" >&2
        cat "$TEMP/emitted.txt" >&2
        exit 1
    fi
    read -r key <"$TEMP/emitted.txt"
    [[ "$key" =~ ^-?[0-9]+$ ]] || exit 1
    output="$CACHE/$relative.$key"
    if [ -s "$output.metal3.metallib" ] && [ -s "$output.metal2.metallib" ]; then continue; fi
    tail -n +2 "$TEMP/emitted.txt" >"$TEMP/material.metal"
    mkdir -p "$(dirname "$output")"
    for target in 3 2; do
        if /usr/bin/xcrun -sdk macosx metal -std="macos-metal$target.0" -o "$TEMP/material.metallib" "$TEMP/material.metal"; then
            mv "$TEMP/material.metallib" "$output.metal$target.metallib"
        elif [ "$target" = 2 ]; then
            exit 1
        else
            echo "Material Fusion: Metal 3 failed for $relative, preparing Metal 2."
        fi
    done
    mv "$TEMP/material.metal" "$output.metal"
done
