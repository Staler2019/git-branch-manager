#!/usr/bin/env bash
# Regenerates every raster app-icon artefact from resources/branding/app-icon.svg
# and commits them alongside the source -- CI runners have no SVG rasteriser,
# so these PNG/.icns/.ico files are checked in rather than built on demand.
#
# Needs: rsvg-convert (brew install librsvg) for PNG rasterisation, python3
# for the .ico multi-size export (bootstraps a small cached venv with Pillow,
# same pattern as scripts/_resolve-clang-format.sh). .icns generation uses
# macOS's `iconutil` and is skipped with a warning on other platforms -- the
# already-committed .icns only needs regenerating after an actual icon change,
# and that's expected to happen on a Mac.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
branding_dir="$repo_root/resources/branding"
svg="$branding_dir/app-icon.svg"

if ! command -v rsvg-convert >/dev/null 2>&1; then
    echo "error: rsvg-convert not found (brew install librsvg)" >&2
    exit 1
fi

render() {
    local size="$1" out="$2"
    rsvg-convert --width "$size" --height "$size" "$svg" -o "$out"
}

echo "Rendering PNGs..."
embed_sizes=(16 32 48 64 128 256 512 1024)
for size in "${embed_sizes[@]}"; do
    render "$size" "$branding_dir/app-icon-${size}.png"
done

# --- macOS .icns -------------------------------------------------------
if command -v iconutil >/dev/null 2>&1; then
    echo "Building .icns..."
    iconset_dir="$(mktemp -d)/AppIcon.iconset"
    mkdir -p "$iconset_dir"
    render 16 "$iconset_dir/icon_16x16.png"
    render 32 "$iconset_dir/icon_16x16@2x.png"
    render 32 "$iconset_dir/icon_32x32.png"
    render 64 "$iconset_dir/icon_32x32@2x.png"
    render 128 "$iconset_dir/icon_128x128.png"
    render 256 "$iconset_dir/icon_128x128@2x.png"
    render 256 "$iconset_dir/icon_256x256.png"
    render 512 "$iconset_dir/icon_256x256@2x.png"
    render 512 "$iconset_dir/icon_512x512.png"
    render 1024 "$iconset_dir/icon_512x512@2x.png"
    iconutil -c icns "$iconset_dir" -o "$branding_dir/app-icon.icns"
    rm -rf "$(dirname "$iconset_dir")"
else
    echo "warning: iconutil not found (macOS only) -- skipping .icns, leaving the committed one as-is" >&2
fi

# --- Windows .ico --------------------------------------------------------
echo "Building .ico..."
venv_dir="${GBM_ICON_CACHE_DIR:-$HOME/.cache/gbm-app-icon}/venv-pillow"
if [ ! -x "$venv_dir/bin/python" ]; then
    mkdir -p "$(dirname "$venv_dir")"
    python3 -m venv "$venv_dir"
    "$venv_dir/bin/pip" install --quiet --upgrade pip
    "$venv_dir/bin/pip" install --quiet Pillow
fi
"$venv_dir/bin/python" - "$branding_dir" <<'PYEOF'
import sys
from pathlib import Path
from PIL import Image

branding_dir = Path(sys.argv[1])
# Pillow generates every requested size itself (via resizing) from a single
# source image passed to save() -- passing pre-resized append_images instead
# silently keeps only the base size, which is the bug this replaced.
base = Image.open(branding_dir / "app-icon-256.png").convert("RGBA")
base.save(
    branding_dir / "app-icon.ico",
    format="ICO",
    sizes=[(16, 16), (32, 32), (48, 48), (256, 256)],
)
PYEOF

echo "Done. Generated artefacts are in $branding_dir -- commit them alongside app-icon.svg."
