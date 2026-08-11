#!/usr/bin/env bash
# Phase A native-library build for the Flutter UI (see the implementation
# plan, section 2.2): builds gbm_capi from the C++ tree and copies the
# resulting shared library into app_flutter/build/native/, where
# lib/data/ffi/native_library.dart looks for it during `flutter run`/`flutter
# test`. Run this once before the first `flutter run`, and again after any
# src/capi or src/core change.
#
# Phase B (linux/CMakeLists.txt, windows/CMakeLists.txt) now makes `flutter
# build` compile and bundle gbm_capi automatically on those two platforms --
# this script is no longer required there for a packaged build, only for
# `flutter run`/`flutter test`, which still resolve the library via
# build/native/ (see native_library.dart). macOS has no Phase B yet (its
# Xcode-based runner isn't CMake, and hooking a Run Script build phase into
# a checked-in .pbxproj could not be verified in the environment this was
# written in), so this script remains the only way to get gbm_capi in place
# there, including for a packaged release build.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_DIR="$REPO_ROOT/build/capi-only"
OUT_DIR="$REPO_ROOT/app_flutter/build/native"

cd "$REPO_ROOT"
cmake --preset capi-only >/dev/null
cmake --build --preset capi-only --target gbm_capi

mkdir -p "$OUT_DIR"

case "$(uname -s)" in
    Linux*)
        cp "$BUILD_DIR/src/capi/libgbm_capi.so" "$OUT_DIR/"
        echo "Copied libgbm_capi.so -> $OUT_DIR/"
        ;;
    Darwin*)
        cp "$BUILD_DIR/src/capi/libgbm_capi.dylib" "$OUT_DIR/"
        echo "Copied libgbm_capi.dylib -> $OUT_DIR/"
        ;;
    *)
        echo "Unrecognized platform $(uname -s); copy the built gbm_capi library into $OUT_DIR manually." >&2
        exit 1
        ;;
esac
