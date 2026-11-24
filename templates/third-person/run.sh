#!/bin/sh
set -eu

project_dir="$(cd "$(dirname "$0")" && pwd)"
engine_dir="${AZORA_ENGINE_HOME:-$HOME/.azora/libraries/__AZORA_LIBRARY_ID__/__AZORA_LIBRARY_VERSION__}"
if [ ! -x "$engine_dir/tools/build.sh" ]; then
    engine_dir="$(cd "$project_dir/../.." && pwd)"
fi

exec "$engine_dir/tools/build.sh" "$project_dir" "${1:-run}"
