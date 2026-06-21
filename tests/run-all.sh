#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

printf 'run-all: syntax\n'
while IFS= read -r path; do
    bash -n "$path"
done <<'LIST'
install.sh
bin/install-runtime.sh
lib/agy-termux-lib.sh
tests/doctor-format.sh
tests/metadata-fail-closed.sh
tests/obsolete-cleanup.sh
tests/invariants.sh
tests/run-all.sh
LIST
python3 -m py_compile tools/build-runtime.py

printf 'run-all: doctor-format\n'
bash tests/doctor-format.sh

printf 'run-all: metadata-fail-closed\n'
bash tests/metadata-fail-closed.sh

printf 'run-all: obsolete-cleanup\n'
bash tests/obsolete-cleanup.sh

printf 'run-all: invariants\n'
bash tests/invariants.sh

printf 'run-all: ok\n'
