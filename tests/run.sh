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
# Headless engine tests.
#
# Each `<name>.az` here is a whole program; `<name>.expected` is what it must
# print. Both are run **twice** - through the interpreter and as a native
# build - and both have to match, because the two backends have disagreed
# silently before: the query walk returned nothing in native builds for a long
# time while `azora run` was perfectly happy, so a test that exercises only one
# of them proves very little.
#
# Only the modules a headless test can use are staged: engine.core and
# engine.ecs. Anything touching a window belongs in a template, not here.
#
#     tests/run.sh            # every test
#     tests/run.sh query      # tests whose name contains "query"
#
set -uo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:${PATH:-}

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
ENGINE_DIR="$(cd "$TESTS_DIR/.." && pwd)"
AZORA="${AZORA_BIN:-$ENGINE_DIR/../azora-lang/app/build/install/azora/bin/azora}"
BUILD_DIR="$TESTS_DIR/.azora-build"
FILTER="${1:-}"

if [ ! -x "$AZORA" ]; then
    echo "error: no azora at $AZORA" >&2
    echo "       build it with: (cd ../azora-lang && ./gradlew :app:installDist)" >&2
    echo "       or set AZORA_BIN" >&2
    exit 1
fi

# `clang` is how a native build is linked; without it only the interpreter runs,
# which is reported rather than skipped silently.
if command -v clang >/dev/null 2>&1; then
    NATIVE=1
else
    NATIVE=0
    echo "note: clang not found - native halves will be skipped"
fi

pass=0
fail=0

for source in "$TESTS_DIR"/*.az; do
    name="$(basename "$source" .az)"
    [ -n "$FILTER" ] && case "$name" in *"$FILTER"*) ;; *) continue ;; esac
    expected="$TESTS_DIR/$name.expected"
    if [ ! -f "$expected" ]; then
        echo "SKIP $name (no .expected)"
        continue
    fi

    stage="$BUILD_DIR/$name"
    rm -rf "$stage"
    mkdir -p "$stage"
    for f in $(find "$ENGINE_DIR/packages" -name '*.az'); do
        module="$(grep -m1 '^module ' "$f" | awk '{print $2}')"
        [ -z "$module" ] && continue
        case "$module" in
            engine.core|engine.ecs|engine.ecs.*)
                path="$(echo "$module" | tr '.' '/')"
                mkdir -p "$stage/$(dirname "$path")"
                cp "$f" "$stage/$path.az"
                ;;
        esac
    done
    cp "$source" "$stage/main.az"

    report() { # report <backend> <actual>
        if [ "$2" = "$(cat "$expected")" ]; then
            echo "PASS $name ($1)"
            pass=$((pass + 1))
        else
            echo "FAIL $name ($1)"
            diff <(echo "$2") "$expected" | sed 's/^/      /'
            fail=$((fail + 1))
        fi
    }

    report interpreted "$("$AZORA" run "$stage/main.az" 2>&1)"

    if [ "$NATIVE" = "1" ]; then
        if "$AZORA" compile llvm "$stage/main.az" > "$stage/$name.ll" 2>"$stage/$name.err" \
            && clang -w -o "$stage/$name" "$stage/$name.ll" 2>>"$stage/$name.err"; then
            # A construct the backend gave up on is a silent wrong answer, not a
            # build failure, so it is worth failing the test outright.
            if grep -q "not lowered" "$stage/$name.ll"; then
                echo "FAIL $name (native): unlowered constructs"
                grep -o "; .* - not lowered" "$stage/$name.ll" | sort -u | sed 's/^/      /'
                fail=$((fail + 1))
            else
                report native "$("$stage/$name" 2>&1)"
            fi
        else
            echo "FAIL $name (native): build failed"
            sed 's/^/      /' "$stage/$name.err" | head -20
            fail=$((fail + 1))
        fi
    fi
done

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
