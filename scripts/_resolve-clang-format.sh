#!/usr/bin/env bash
# Resolves a clang-format 18 binary and prints its path on stdout.
#
# CI's `lint` job (.github/workflows/ci.yml) checks src/ with
# jidicula/clang-format-action@v4.13.0 pinned to clang-format-version: '18'.
# .clang-format's IncludeBlocks/regroup behavior differs enough between
# clang-format releases that formatting with anything else just trades one
# red check for another, so this refuses to fall back to a wrong-version
# binary silently -- it resolves 18 specifically or fails with a clear error.
#
# Resolution order, cheapest-that-already-works first:
#   1. `clang-format-18` on PATH (apt/some distro packages install it named
#      this way -- no version check needed, the name says it).
#   2. `clang-format` from a Homebrew `llvm@18` keg, if installed.
#   3. A cached Python venv with the `clang-format` PyPI wheel pinned to
#      18.1.8 (https://pypi.org/project/clang-format/, prebuilt binaries).
#      This is the path that always works with nothing but python3 -- no
#      brew, no system package manager -- so it's the default for anyone who
#      hasn't already got 18 on their machine.
set -euo pipefail

want_major="18"
cache_dir="${GBM_FORMAT_CACHE_DIR:-$HOME/.cache/gbm-clang-format}"
venv_dir="$cache_dir/venv-18.1.8"

version_major() {
    "$1" --version 2>/dev/null | grep -oE '[0-9]+' | head -n1
}

# 1. clang-format-18 on PATH
if command -v clang-format-18 >/dev/null 2>&1; then
    echo "$(command -v clang-format-18)"
    exit 0
fi

# 2. Homebrew llvm@18 keg
if command -v brew >/dev/null 2>&1; then
    if prefix="$(brew --prefix llvm@18 2>/dev/null)" && [ -x "$prefix/bin/clang-format" ]; then
        echo "$prefix/bin/clang-format"
        exit 0
    fi
fi

# 3. Any clang-format already on PATH that happens to be v18
if command -v clang-format >/dev/null 2>&1; then
    if [ "$(version_major clang-format)" = "$want_major" ]; then
        echo "$(command -v clang-format)"
        exit 0
    fi
fi

# 4. Cached venv with the pinned PyPI wheel -- the always-works fallback.
if [ ! -x "$venv_dir/bin/clang-format" ]; then
    if ! command -v python3 >/dev/null 2>&1; then
        echo "error: no clang-format 18 found and python3 is unavailable to install one" >&2
        exit 1
    fi
    echo "Bootstrapping clang-format 18.1.8 into $venv_dir (one-time)..." >&2
    mkdir -p "$cache_dir"
    python3 -m venv "$venv_dir" >&2
    "$venv_dir/bin/pip" install --quiet --upgrade pip >&2
    "$venv_dir/bin/pip" install --quiet "clang-format==18.1.8" >&2
fi

if [ "$(version_major "$venv_dir/bin/clang-format")" != "$want_major" ]; then
    echo "error: bootstrapped clang-format is not major version $want_major" >&2
    exit 1
fi

echo "$venv_dir/bin/clang-format"
