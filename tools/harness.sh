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
# Azora Engine — project test harness.
#
# Builds a test project (an azora.azon + src/main.az that prints one line per
# check), runs it from its own folder and compares what it printed with the
# project's expected.txt. A harness.env beside it, KEY=VALUE per line, is
# exported first.
#
#     tools/harness.sh tests/audio-dsp
#
set -uo pipefail
ENGINE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$(cd "${1:?usage: harness.sh <project>}" && pwd)"
NAME="$(basename "$PROJECT")"
export AZORA_COMPILER_BIN="${AZORA_COMPILER_BIN:-$ENGINE_DIR/../azora-lang/compiler/build/bin/macosArm64/releaseExecutable/azora.kexe}"
export AZORA_STDLIB="${AZORA_STDLIB:-$ENGINE_DIR/../azora-lang/std}"

LOG="$PROJECT/.azora-build/harness.log"
mkdir -p "$PROJECT/.azora-build"
if ! bash "$ENGINE_DIR/tools/build.sh" "$PROJECT" build > "$LOG" 2>&1; then
    echo "FAIL $NAME (build)"
    tail -30 "$LOG"
    exit 1
fi
APP="$(basename "$PROJECT" | tr -cd '[:alnum:]_-')"
if [ -f "$PROJECT/harness.env" ]; then
    while IFS= read -r line; do
        case "$line" in ''|'#'*) ;; *) export "$line" ;; esac
    done < "$PROJECT/harness.env"
fi
ACTUAL="$(cd "$PROJECT" && "./.azora-build/$APP" 2>&1 | grep -v '^azora-engine:\|^Material Fusion:')"
if [ "$ACTUAL" = "$(cat "$PROJECT/expected.txt")" ]; then
    echo "PASS $NAME"
else
    echo "FAIL $NAME"
    diff <(echo "$ACTUAL") "$PROJECT/expected.txt" | sed 's/^/    /'
    exit 1
fi
