# Sourced, not run: `. scripts/_find-python.sh && py="$(find_python)"`. POSIX sh, because
# .claude/hooks/format-cpp.sh is #!/bin/sh and scripts/_resolve-clang-format.sh is bash.
#
# find_python prints the real executable of the first working Python 3 -- python3, then
# python -- and returns 1 when there is none. It asks the interpreter for sys.executable
# instead of trusting the name on PATH, because on Windows that name may be
#   - the Microsoft Store stub, which only says "install me" and exits 9009;
#   - the pyenv-win shim, a .bat underneath, which reads stdin without passing it on and
#     breaks a multi-line -c.
# The one-line probe below survives both; the executable it prints has neither problem. The
# probe gets /dev/null as stdin, or the shim would eat the hook's payload while being asked.
find_python() {
    for candidate in python3 python; do
        command -v "$candidate" >/dev/null 2>&1 || continue
        exe="$("$candidate" -c 'import sys; sys.exit(sys.version_info[0] != 3 or print(sys.executable))' </dev/null 2>/dev/null)" || continue
        exe="${exe%"$(printf '\r')"}"
        if [ -n "$exe" ]; then
            printf '%s\n' "$exe"
            return 0
        fi
    done
    return 1
}
