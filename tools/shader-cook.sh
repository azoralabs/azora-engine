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
    elif [ "$NATIVE_SHADERS" = 1 ]; then
        # The native compiler that builds the game: a quarter of a second a
        # shader, where starting the bundled compiler's JVM took a second.
        "$AZORA_COMPILER_BIN" "$@"
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

# Whether the game's native compiler (AZORA_COMPILER_BIN) makes Metal
# libraries: an older one only made LLVM. Asked once per compiler binary, with
# a one-entry shader; the answer is kept beside the libraries.
NATIVE_SHADERS=0
if [ -z "${AZORA_SHADER_COMPILER_BIN:-}" ] && [ -n "${AZORA_COMPILER_BIN:-}" ] && [ -x "$AZORA_COMPILER_BIN" ]; then
    NATIVE_PROBE="$OUTPUT/.native-metallib"
    if [ -f "$NATIVE_PROBE" ] && [ ! "$AZORA_COMPILER_BIN" -nt "$NATIVE_PROBE" ]; then
        NATIVE_SHADERS=1
    else
        printf '@Execution("GPU")\nmodule probe.native\n\n@Compute(1, 1, 1)\nfunc probe(id: @GlobalInvocationId UInt3) {\n}\n' > "$STAGE/probe.az"
        if "$AZORA_COMPILER_BIN" compile metallib "$STAGE/probe.az" -o "$STAGE/probe.metallib" >/dev/null 2>&1; then
            NATIVE_SHADERS=1
            : > "$NATIVE_PROBE"
        fi
    fi
fi

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

trivia = r'(?:[\s\ufeff]|//[^\r\n]*(?=[\r\n]|\Z)|/\*(?:[^*]|\*(?!/))*\*/)*'
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

# What every library depends on: this script and the compiler that makes it.
COMPILER_STAMP="$0"
if [ -n "${AZORA_SHADER_COMPILER_BIN:-}" ]; then
    COMPILER_STAMP="$AZORA_SHADER_COMPILER_BIN"
elif [ "$NATIVE_SHADERS" = 1 ]; then
    COMPILER_STAMP="$AZORA_COMPILER_BIN"
elif [ -f "$ENGINE/tools/azorac/lib/compiler-desktop.jar" ]; then
    COMPILER_STAMP="$ENGINE/tools/azorac/lib/compiler-desktop.jar"
fi

# Each library is made again only when its own source, a shader module it
# imports (or one those import), this script or the compiler is newer than
# it. Judged by the newest of every engine shader at once, one edit to any
# of them made all of them again on every build.
# Prints, for each source: its path, the library's name under OUTPUT and the newest file it depends on.
plan_cooking() {
    python3 - "$0" "$COMPILER_STAMP" "$PROJECT" "$SCOPE" "${#ENGINE_SOURCES[@]}" \
        ${ENGINE_SOURCES[@]+"${ENGINE_SOURCES[@]}"} ${PROJECT_SOURCES[@]+"${PROJECT_SOURCES[@]}"} <<'PYTHON'
import os
import re
import sys

script, compiler, project, scope, engine_count = sys.argv[1:6]
files = sys.argv[6:]
engine = files[:int(engine_count)]
module_line = re.compile(r'^\s*module\s+([A-Za-z_][\w.]*)', re.M)
import_line = re.compile(r'^\s*import\s+([A-Za-z_][\w.]*)', re.M)
modules, imports = {}, {}
for path in files:
    text = open(path, encoding="utf-8").read()
    found = module_line.search(text)
    if found:
        modules.setdefault(found.group(1), path)
    imports[path] = import_line.findall(text)

def newest(path):
    best, seen, todo = max([script, compiler], key=os.path.getmtime), set(), [path]
    while todo:
        current = todo.pop()
        if current in seen:
            continue
        seen.add(current)
        if os.path.getmtime(current) > os.path.getmtime(best):
            best = current
        todo.extend(modules[name] for name in imports.get(current, []) if name in modules)
    return best

for path in files:
    is_engine = path in engine
    if (is_engine and scope == "project") or (not is_engine and scope == "engine"):
        continue
    if is_engine:
        relative = os.path.basename(path)[:-3]
    else:
        relative = "project/" + os.path.relpath(path, project)[:-3]
    print(f"{path}\t{relative}\t{newest(path)}")
PYTHON
}

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

PLAN="$STAGE/plan"
plan_cooking > "$PLAN"
while IFS=$'\t' read -r source relative newest <&3; do
    cook "$source" "$relative" "$newest"
done 3< "$PLAN"
