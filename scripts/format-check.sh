#!/usr/bin/env bash
# Non-mutating check: exits non-zero if any file under src/ would be changed
# by clang-format 18. This is what CI's `lint` job effectively runs
# (jidicula/clang-format-action@v4.13.0, check-path: 'src') -- run this
# locally before pushing to reproduce that gate exactly.
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

"$cf" --dry-run --Werror "${files[@]}"
echo "All ${#files[@]} files under src/ are clang-format-clean."
