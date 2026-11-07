#!/usr/bin/env bash
# Resolves a clang-format 22 binary and prints its path on stdout.
#
# CI's `lint` job (.github/workflows/ci.yml) checks src/ with
# jidicula/clang-format-action@v4.18.0 pinned to clang-format-version: '22'.
# .clang-format's IncludeBlocks/regroup behavior differs enough between
# clang-format releases that formatting with anything else just trades one
# red check for another, so this refuses to fall back to a wrong-version
# binary silently -- it resolves 22 specifically or fails with a clear error.
#
# Resolution order, cheapest-that-already-works first:
#   1. `clang-format-22` on PATH (apt/some distro packages install it named
#      this way -- no version check needed, the name says it).
#   2. `clang-format` from a Homebrew `llvm@22` keg, if installed.
#   3. A cached Python venv with the `clang-format` PyPI wheel pinned to
#      22.1.8 (https://pypi.org/project/clang-format/, prebuilt binaries).
#      This is the path that always works with nothing but Python 3 -- no
#      brew, no system package manager -- so it's the default for anyone who
#      hasn't already got 22 on their machine.
set -euo pipefail

want_major="22"
cache_dir="${GBM_FORMAT_CACHE_DIR:-$HOME/.cache/gbm-clang-format}"
venv_dir="$cache_dir/venv-22.1.8"

version_major() {
    "$1" --version 2>/dev/null | grep -oE '[0-9]+' | head -n1
}

# 1. clang-format-22 on PATH
if command -v clang-format-22 >/dev/null 2>&1; then
    echo "$(command -v clang-format-22)"
    exit 0
fi

# 2. Homebrew llvm@22 keg
if command -v brew >/dev/null 2>&1; then
    if prefix="$(brew --prefix llvm@22 2>/dev/null)" && [ -x "$prefix/bin/clang-format" ]; then
        echo "$prefix/bin/clang-format"
        exit 0
    fi
fi

# 3. Any clang-format already on PATH that happens to be v22
if command -v clang-format >/dev/null 2>&1; then
    if [ "$(version_major clang-format)" = "$want_major" ]; then
        echo "$(command -v clang-format)"
        exit 0
    fi
fi

# 4. Cached venv with the pinned PyPI wheel -- the always-works fallback.
# A venv keeps its executables in bin/, or in Scripts/ when the Python is a Windows one.
venv_exe() {
    if [ -d "$venv_dir/Scripts" ]; then
        echo "$venv_dir/Scripts/$1"
    else
        echo "$venv_dir/bin/$1"
    fi
}

# Asks the binary rather than checking it exists: a venv outlives the Python it
# was built from, and then its clang-format is executable but cannot start.
if [ "$(version_major "$(venv_exe clang-format)")" != "$want_major" ]; then
    # python3, else python: a python.org install on Windows has no python3.
    . "$(dirname "$0")/_find-python.sh"
    if ! python="$(find_python)"; then
        echo "error: no clang-format 22 found and no Python 3 is available to install one" >&2
        exit 1
    fi
    echo "Bootstrapping clang-format 22.1.8 into $venv_dir..." >&2
    mkdir -p "$cache_dir"
    "$python" -m venv --clear "$venv_dir" >&2
    # Through the venv's python: on Windows pip.exe cannot replace itself and fails.
    "$(venv_exe python)" -m pip install --quiet --upgrade pip >&2
    "$(venv_exe python)" -m pip install --quiet "clang-format==22.1.8" >&2
fi

if [ "$(version_major "$(venv_exe clang-format)")" != "$want_major" ]; then
    echo "error: bootstrapped clang-format is not major version $want_major" >&2
    exit 1
fi

venv_exe clang-format
