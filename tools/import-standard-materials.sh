#!/usr/bin/env bash
set -euo pipefail

ENGINE="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="${1:?usage: import-standard-materials.sh PROJECT}"
LIBRARY="$ENGINE/materials/standard"

if [ ! -f "$PROJECT/azora.azon" ]; then
    echo "Project manifest missing from $PROJECT" >&2
    exit 1
fi

python3 - "$LIBRARY" "$PROJECT" <<'PY'
import os
from pathlib import Path
import shutil
import sys
from tempfile import NamedTemporaryFile

library, project = map(Path, sys.argv[1:])
for pattern in ("Textures/Standard/*/*.aztexture", "Materials/Standard/*.az"):
    sources = sorted(library.glob(pattern))
    if not sources:
        sys.exit(f"Standard material library assets missing: {library / pattern}")
    for source in sources:
        target = project / source.relative_to(library)
        if target.exists() or target.is_symlink():
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        with NamedTemporaryFile(dir=target.parent) as staged, source.open("rb") as data:
            shutil.copyfileobj(data, staged)
            staged.flush()
            try:
                os.link(staged.name, target)
            except FileExistsError:
                pass
PY
