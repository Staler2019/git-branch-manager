#!/usr/bin/env bash
# Applies clang-format 18 to every .cpp/.h under src/, in place -- the same
# scope CI's `lint` job checks (check-path: 'src' in .github/workflows/ci.yml).
# See scripts/format-check.sh for the non-mutating version used by CI/pre-commit.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cf="$("$repo_root/scripts/_resolve-clang-format.sh")"
echo "Using $("$cf" --version) at $cf"

cd "$repo_root"
# `mapfile` isn't available on macOS's stock bash 3.2, so build the array
# with a portable read loop over a NUL-delimited find instead.
files=()
while IFS= read -r -d '' f; do
    files+=("$f")
done < <(find src -type f \( -name '*.cpp' -o -name '*.h' \) -print0)

if [ "${#files[@]}" -eq 0 ]; then
    echo "No files found under src/"
    exit 0
fi

"$cf" -i "${files[@]}"
echo "Formatted ${#files[@]} files under src/"
