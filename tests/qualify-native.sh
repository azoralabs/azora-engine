#!/usr/bin/env bash
# Build and execute real Engine projects with the selected compiler and runtime.
set -euo pipefail
ENGINE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export AZORA_COMPILER_BIN="${AZORA_COMPILER_BIN:-$ENGINE_DIR/../azora-lang/compiler/build/bin/macosArm64/debugExecutable/azora.kexe}"
MODE="${1:-all}"
if [ "$MODE" != all ] && [ "$MODE" != headless ] && [ "$MODE" != game ] && [ "$MODE" != foundation ]; then
    echo "usage: qualify-native.sh [all|headless|foundation|game]" >&2
    exit 2
fi
command -v clang >/dev/null
[ -x "$AZORA_COMPILER_BIN" ]
"$ENGINE_DIR/runtime/build.sh"
if [ "$MODE" = all ] || [ "$MODE" = headless ]; then
    "$ENGINE_DIR/tools/build.sh" "$ENGINE_DIR/tests/headless-ecs" build
    actual="$("$ENGINE_DIR/tests/headless-ecs/.azora-build/headless-ecs")"
    [ "$actual" = "headless ecs passed" ]
    echo "$actual"
fi
if [ "$MODE" = all ] || [ "$MODE" = foundation ]; then
    for probe in owned-ecs scheduled-ecs constructor-ui scene-io dock-layout; do
        "$ENGINE_DIR/tools/build.sh" "$ENGINE_DIR/tests/$probe" build
        actual="$("$ENGINE_DIR/tests/$probe/.azora-build/$probe")"
        case "$probe" in
            owned-ecs) expected="owned ecs passed" ;;
            scheduled-ecs) expected="scheduled ecs passed" ;;
            constructor-ui) expected="constructor ui passed" ;;
            scene-io) expected="scene io passed" ;;
            dock-layout) expected="dock layout passed" ;;
        esac
        [ "$actual" = "$expected" ]
        echo "$actual"
    done
fi
if [ "$MODE" = all ] || [ "$MODE" = game ]; then
    # The shipping game template is first built unchanged. Its complete source
    # is then staged with a bounded entry point using the same host lifecycle.
    "$ENGINE_DIR/tools/build.sh" "$ENGINE_DIR/templates/game" build
    PROBE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/azora-engine-game.XXXXXX")"
    trap 'rm -rf "$PROBE_DIR"' EXIT
    mkdir "$PROBE_DIR/src"
    python3 - "$ENGINE_DIR/templates/game/src/main.az" "$PROBE_DIR/src/main.az" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text()
assert source.count('    e.run()') == 1
source = source.replace('module game\n', 'module game\nimport std.io\n')
source = source.replace('    e.run()', '    assert e.runFrames(3) panic "game did not render three frames"\n    println("native game passed")')
Path(sys.argv[2]).write_text(source)
PY
    "$ENGINE_DIR/tools/build.sh" "$PROBE_DIR" build
    APP_NAME="$(basename "$PROBE_DIR" | tr -cd '[:alnum:]_-')"
    actual="$("$PROBE_DIR/.azora-build/$APP_NAME")"
    [ "$actual" = "native game passed" ]
    echo "$actual"
fi
