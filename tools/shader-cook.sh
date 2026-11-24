#!/usr/bin/env bash
# Cook Engine and/or project shaders. Metal keeps each source's entry points in one library.
# SPIR-V and DXIL put one binary per entry point under spirv/ and dxil/.
set -euo pipefail

ENGINE="$(cd "$(dirname "$0")/.." && pwd)"
if [ "${1:-}" = --studio ]; then
    PROJECT="$(cd "${2:?usage: shader-cook.sh --studio PROJECT}" && pwd)"
    OUTPUT="$PROJECT/.azora-build/shaders"
    TARGETS=metallib
    SCOPE=project
else
    PROJECT="$(cd "${1:?usage: shader-cook.sh PROJECT OUTPUT [targets]}" && pwd)"
    OUTPUT="${2:?usage: shader-cook.sh PROJECT OUTPUT [targets]}"
    TARGETS="${3:-${AZORA_SHADER_TARGETS:-metallib spv dxil}}"
    SCOPE="${AZORA_SHADER_SCOPE:-all}"
fi

compiler() {
    if [ -n "${AZORA_SHADER_COMPILER_BIN:-}" ]; then
        "$AZORA_SHADER_COMPILER_BIN" "$@"
    elif [ -f "$ENGINE/tools/azorac/lib/app.jar" ]; then
        local java=java
        if [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/java" ]; then java="$JAVA_HOME/bin/java"; fi
        "$java" -cp "$ENGINE/tools/azorac/lib/*" dev.azora.lang.MainKt "$@"
    else
        "${AZORA_COMPILER_BIN:-azora}" "$@"
    fi
}

mkdir -p "$OUTPUT"
OUTPUT="$(cd "$OUTPUT" && pwd)"
STAGE="$(mktemp -d "$OUTPUT/.cook.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT

IMPORTS=()
ENGINE_SOURCES=()
PROJECT_SOURCES=()
for directory in "$ENGINE"/packages/*/shaders; do
    [ -d "$directory" ] || continue
    IMPORTS+=(--import-path "$directory")
    for file in "$directory"/*.az; do
        [ ! -f "$file" ] || ENGINE_SOURCES+=("$file")
    done
done
if [ "$SCOPE" != engine ]; then
    IMPORTS+=(--import-path "$PROJECT")
    while IFS= read -r -d '' file; do PROJECT_SOURCES+=("$file"); done < <(
        python3 - "$PROJECT" <<'PYTHON'
import os
from pathlib import Path
import re
import sys

trivia = r'(?:[\s\ufeff]|//[^\r\n]*|/\*[\s\S]*?\*/)*'
header = re.compile(rf'\A{trivia}@Execution\s*\(\s*"GPU"\s*\){trivia}module\s+')
for directory, folders, files in os.walk(sys.argv[1]):
    folders[:] = sorted(name for name in folders if not name.startswith(".") and name != "build")
    for name in sorted(files):
        if not name.endswith(".az"):
            continue
        source = Path(directory, name)
        if header.match(source.read_text(encoding="utf-8")):
            sys.stdout.buffer.write(os.fsencode(source) + b"\0")
PYTHON
    )
fi

# Import dependencies are included in freshness checks. A project module can be in any subdirectory.
stamp() {
    local newest="$1" source
    shift
    for source in "$@"; do
        if [ "$source" -nt "$newest" ]; then newest="$source"; fi
    done
    printf '%s\n' "$newest"
}
ENGINE_NEWEST="$(stamp "$0" "${ENGINE_SOURCES[@]}")"
if [ -n "${AZORA_SHADER_COMPILER_BIN:-}" ]; then
    ENGINE_NEWEST="$(stamp "$ENGINE_NEWEST" "$AZORA_SHADER_COMPILER_BIN")"
elif [ -f "$ENGINE/tools/azorac/lib/compiler-desktop.jar" ]; then
    ENGINE_NEWEST="$(stamp "$ENGINE_NEWEST" "$ENGINE/tools/azorac/lib/compiler-desktop.jar")"
fi
PROJECT_NEWEST="$(stamp "$ENGINE_NEWEST" ${PROJECT_SOURCES[@]+"${PROJECT_SOURCES[@]}"})"

has_entry() { grep -qE '^[[:space:]]*@(Vertex|Fragment|Compute)([[:space:](]|$)' "$1"; }

material_bindings() {
    python3 - "$1" "$2" <<'PY'
import json
import math
from pathlib import Path
import re
import sys

source, output = map(Path, sys.argv[1:])
bindings = re.findall(r"^\s*// @Material (.+)$", source.read_text(encoding="utf-8"), re.M)
if not bindings:
    sys.exit(0)
try:
    if len(bindings) != 1:
        raise ValueError("expected one @Material declaration")
    data = json.loads(bindings[0])
    albedo = data["albedo"]
    textures = data["textures"]
    if len(albedo) != 3 or not all(isinstance(value, (int, float)) and math.isfinite(value)
                                  and 0 <= value <= 1 for value in albedo):
        raise ValueError("albedo requires three numbers in 0..1")
    if len(textures) > 8 or any(
        not isinstance(path, str) or not path.endswith((".aztexture", ".aztex"))
        or any(part in ("", ".", "..") for part in path.split("/"))
        or any(ch in path for ch in '\\"\n\r\x00') for path in textures
    ):
        raise ValueError("textures requires at most eight project-relative texture sets")
    output.write_text(json.dumps({"albedo": albedo, "textures": textures}), encoding="utf-8")
except (KeyError, TypeError, ValueError) as error:
    sys.exit(f"{source}: {error}")
PY
}

cook() {
    local source="$1" relative="$2" newest="$3" target output manifest product stale name
    has_entry "$source" || return 0
    for target in $TARGETS; do
        case "$target" in
            metallib)
                output="$OUTPUT/$relative.metallib"
                if [ -s "$output" ] && [ ! "$newest" -nt "$output" ]; then continue; fi
                mkdir -p "$(dirname "$output")"
                echo "azora-engine: ${source#"$ENGINE"/} (metallib)"
                material_bindings "$source" "$STAGE/material.bindings"
                compiler compile metallib "$source" "${IMPORTS[@]}" -o "$STAGE/shader.metallib"
                if [ -f "$STAGE/material.bindings" ]; then
                    mv "$STAGE/material.bindings" "$output.bindings"
                elif [ -f "$output.bindings" ]; then
                    rm "$output.bindings"
                fi
                mv "$STAGE/shader.metallib" "$output"
                ;;
            spv|dxil)
                output="$OUTPUT/$([ "$target" = spv ] && echo spirv || echo dxil)/$relative"
                manifest="$output.$target.stamp"
                stale=1
                if [ -s "$manifest" ] && [ ! "$newest" -nt "$manifest" ]; then
                    stale=0
                    while IFS= read -r name; do
                        if [ ! -s "$(dirname "$output")/$name" ]; then stale=1; break; fi
                    done < "$manifest"
                fi
                [ "$stale" = 1 ] || continue
                mkdir -p "$(dirname "$output")" "$STAGE/stages"
                echo "azora-engine: ${source#"$ENGINE"/} ($target)"
                compiler compile "$target" "$source" "${IMPORTS[@]}" -o "$STAGE/stages/"
                : > "$STAGE/manifest"
                for product in "$STAGE"/stages/*."$target"; do
                    printf '%s\n' "$(basename "$product")" >> "$STAGE/manifest"
                    mv "$product" "$(dirname "$output")/"
                done
                if [ -f "$manifest" ]; then
                    while IFS= read -r name; do
                        if [ -n "$name" ] && ! grep -Fxq "$name" "$STAGE/manifest"; then rm -f "$(dirname "$output")/$name"; fi
                    done < "$manifest"
                fi
                mv "$STAGE/manifest" "$manifest"
                ;;
            *) echo "Unknown shader target '$target' (metallib, spv, dxil)" >&2; exit 1 ;;
        esac
    done
}

if [ "$SCOPE" != project ]; then
    for source in "${ENGINE_SOURCES[@]}"; do
        cook "$source" "$(basename "$source" .az)" "$ENGINE_NEWEST"
    done
fi
for source in ${PROJECT_SOURCES[@]+"${PROJECT_SOURCES[@]}"}; do
    relative="${source#"$PROJECT"/}"
    cook "$source" "project/${relative%.az}" "$PROJECT_NEWEST"
done
