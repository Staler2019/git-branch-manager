#!/bin/bash
set -euo pipefail

# Remote-only: local Claude Code sessions already have whatever toolchain
# the developer's machine provides.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

# Pinned to match .github/workflows/ci.yml / release.yml's
# flutter-version -- 3.44.9 is the latest 3.44.x patch still on Dart
# 3.12.2, which is app_flutter/pubspec.yaml's `sdk: ^3.12.2` floor
# exactly. 3.44.0-3.44.1 ship an older Dart that fails that constraint,
# and a later Dart minor (3.13.0 shipped a `dart format` style change)
# would flap formatting against what CI enforces -- see CLAUDE.md's
# "Known gaps" note on this exact problem.
FLUTTER_VERSION="3.44.9"
FLUTTER_ROOT="/opt/flutter-sdk/flutter"

# Idempotent: a checkpointed/restored container may already have this
# from a prior session, and re-downloading a ~1.5GB archive every start
# would defeat the point of a persistent install location.
if [ ! -x "$FLUTTER_ROOT/bin/flutter" ]; then
  echo "Installing Flutter $FLUTTER_VERSION to $FLUTTER_ROOT..."
  mkdir -p /opt/flutter-sdk
  tmp_archive="$(mktemp -u /tmp/flutter-XXXXXX.tar.xz)"
  curl -sSL -o "$tmp_archive" \
    "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
  tar -xJf "$tmp_archive" -C /opt/flutter-sdk
  rm -f "$tmp_archive"
else
  echo "Flutter $FLUTTER_VERSION already installed at $FLUTTER_ROOT, skipping download."
fi

# `flutter`/`dart` refuse to run as the repository owner (root, in this
# environment) without this -- see the "Woah! You appear to be trying to
# run flutter as root" warning it prints otherwise. Harmless as a warning
# but git operations inside the SDK's own repo (e.g. `flutter --version`
# reading its own commit) fail outright without the exception.
git config --global --add safe.directory "$FLUTTER_ROOT" 2>/dev/null || true

export PATH="$FLUTTER_ROOT/bin:$PATH"
echo "export PATH=\"$FLUTTER_ROOT/bin:\$PATH\"" >> "$CLAUDE_ENV_FILE"

# Warms the pub cache so `flutter analyze`/`flutter test` don't hit a
# cold resolve on the first real command of the session.
if [ -f "$CLAUDE_PROJECT_DIR/app_flutter/pubspec.yaml" ]; then
  (cd "$CLAUDE_PROJECT_DIR/app_flutter" && flutter pub get)
fi

flutter --version
