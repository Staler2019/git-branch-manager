#!/bin/sh
# PostToolUse(Write|Edit|MultiEdit): format the one C++ file a tool just changed.
# Same scope as CI's check (.cpp/.h under src/) and the same v18, which is not what
# `clang-format` on PATH may be; one file only, per [CI-formatter-version-drift].
# Exit 2 hands a resolver or formatter failure to Claude, since CI would go red on it.
root="$(cd "$(dirname "$0")/../.." && pwd -P)"

file="$(python3 -I -c '
import json, sys
try:
    print(json.load(sys.stdin)["tool_input"]["file_path"])
except Exception:
    pass
' 2>/dev/null)"

case "$file" in
  "$root"/src/*.cpp | "$root"/src/*.h) ;;
  *) exit 0 ;;
esac
[ -f "$file" ] || exit 0

clang_format="$("$root/scripts/_resolve-clang-format.sh")" || exit 2
"$clang_format" -i -- "$file" || exit 2
