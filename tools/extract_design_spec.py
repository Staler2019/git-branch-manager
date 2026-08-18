#!/usr/bin/env python3
"""Extracts the readable spec document and its data constants from the
"Flutter Desktop Spec (standalone).html" design deliverable.

That file is not plain HTML: it is a bundler-wrapped export where the
actual page content is JSON-stringified and, together with the design
system's component sources, gzip+base64-compressed inside inline
<script> tags. This script reverses that packaging so the spec's prose,
data tables, and page structure can be diffed against the app's
implementation without hand-decoding the bundle each time.

Usage:
    python3 tools/extract_design_spec.py [--out DIR]

Produces two files in --out (default: current directory):
    spec_raw.html   -- the decoded spec document (template + inline data)
    spec_logic.js    -- just the largest inline <script> block, which holds
                        the page's data constants (PAGES, MENUS, CTX,
                        DIALOGS, STATES, SPLITTERS, ...) as plain JS.

spec_logic.js is the authoritative source for the spec's data tables --
read it directly (it's plain `const NAME = [...]` declarations) rather
than re-parsing spec_raw.html's mustache-style template markup.
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

DEFAULT_SPEC_PATH = (
    Path(__file__).resolve().parent.parent
    / "docs"
    / "claude-design-demo"
    / "Flutter Desktop Spec (standalone).html"
)

_SCRIPT_RE = re.compile(r"<script[^>]*>(.*?)</script>", re.S | re.I)
_INLINE_SCRIPT_RE = re.compile(
    r"<script(?![^>]*\bsrc=)[^>]*>(.*?)</script>", re.S | re.I
)


def extract(spec_path: Path) -> tuple[str, str]:
    """Returns (spec_raw_html, spec_logic_js)."""
    bundle = spec_path.read_text(encoding="utf-8")
    top_level_scripts = _SCRIPT_RE.findall(bundle)

    # The decoded document is whichever top-level <script> body parses as a
    # JSON string starting with "<!DOCTYPE" -- avoids depending on a fixed
    # index, since the bundler's script ordering is not a stable contract.
    doc = None
    for raw in top_level_scripts:
        raw = raw.strip()
        if not raw.startswith('"'):
            continue
        try:
            candidate = json.loads(raw)
        except json.JSONDecodeError:
            continue
        if candidate.lstrip().startswith("<!DOCTYPE"):
            doc = candidate
            break
    if doc is None:
        raise RuntimeError(
            "could not find the JSON-stringified spec document among "
            f"{len(top_level_scripts)} top-level <script> blocks -- the "
            "bundle format may have changed"
        )

    inline_blocks = _INLINE_SCRIPT_RE.findall(doc)
    if not inline_blocks:
        raise RuntimeError("decoded document has no inline <script> blocks")
    # The data-constants block is by far the largest inline script (the
    # other one just neuters window.lucide.createIcons).
    logic_js = max(inline_blocks, key=len)

    return doc, logic_js


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--spec",
        type=Path,
        default=DEFAULT_SPEC_PATH,
        help="path to the standalone spec HTML (default: %(default)s)",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=Path.cwd(),
        help="output directory for spec_raw.html / spec_logic.js "
        "(default: current directory)",
    )
    args = parser.parse_args()

    doc, logic_js = extract(args.spec)

    args.out.mkdir(parents=True, exist_ok=True)
    raw_path = args.out / "spec_raw.html"
    logic_path = args.out / "spec_logic.js"
    raw_path.write_text(doc, encoding="utf-8")
    logic_path.write_text(logic_js, encoding="utf-8")

    print(f"wrote {raw_path} ({len(doc):,} chars)")
    print(f"wrote {logic_path} ({len(logic_js):,} chars)")


if __name__ == "__main__":
    main()
