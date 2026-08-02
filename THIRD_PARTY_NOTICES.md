# Third-party notices

## Qt 6 — LGPL v3

The GUI links against Qt 6 (`QtCore`, `QtGui`, `QtWidgets`) under the
**GNU Lesser General Public License version 3**.

Using Qt under the LGPL in a closed-source or commercial product is permitted,
but it carries obligations. This project satisfies them as follows:

| Obligation | How it is met |
|---|---|
| Qt must be **dynamically linked**, so a user can replace it | All three packaging paths (`windeployqt`, `macdeployqt`, `linuxdeploy`) ship Qt as shared libraries. CI asserts no Qt library is statically linked. |
| The LGPL v3 text must accompany the binary | `LICENSES/LGPL-3.0.txt` is installed alongside the application. |
| Users must be told which LGPL components are used, and be able to obtain their source | The About dialog names Qt with its version and licence, and links to the corresponding source. |
| No technical measure may prevent relinking against a modified Qt | The application does not verify or pin the Qt libraries it loads. |

Only LGPL-licensed Qt modules are used. GPL-only add-ons — notably **Qt Charts**
and **Qt Data Visualization** — are deliberately avoided, because linking them
would place the whole application under the GPL.

Qt is a trademark of The Qt Company Ltd. Qt source: <https://download.qt.io/>

## SQLite — public domain

Used for the repository discovery cache. SQLite is in the public domain and
imposes no conditions. <https://www.sqlite.org/copyright.html>

## GoogleTest — BSD 3-Clause

Test-only dependency; never linked into a distributed binary.
<https://github.com/google/googletest/blob/main/LICENSE>

## Git

The application **invokes the `git` executable already installed on the user's
system** and does not bundle, redistribute, or link against Git or libgit2. Git
is licensed under the GPL v2, but because it is only ever executed as a separate
program, no GPL obligation extends to this application.

If Git is missing or older than 2.30, the application says so and points the user
at the official installer rather than shipping its own copy.

## Inter — SIL Open Font License 1.1

The UI font is **Inter** by The Inter Project Authors, used under the **SIL
Open Font License, Version 1.1**. Four static weights (Regular, Medium,
SemiBold, Bold) are bundled as Qt resources at `resources/fonts/` and
registered at startup via `QFontDatabase::addApplicationFont`; the full
licence text ships alongside them at `resources/fonts/Inter-OFL.txt`.

Source: <https://github.com/rsms/inter> (v4.1 release,
<https://github.com/rsms/inter/releases/tag/v4.1>)

## JetBrains Mono — SIL Open Font License 1.1

The monospace font (SHAs, branch tags, diff lines) is **JetBrains Mono** by
The JetBrains Mono Project Authors, used under the **SIL Open Font License,
Version 1.1**. Two static weights (Regular, Medium) are bundled as Qt
resources at `resources/fonts/`; the full licence text ships alongside them at
`resources/fonts/JetBrainsMono-OFL.txt`.

Source: <https://github.com/JetBrains/JetBrainsMono> (v2.304 release,
<https://github.com/JetBrains/JetBrainsMono/releases/tag/v2.304>)

## Lucide — ISC License

Toolbar, sidebar, and file-status icons are drawn from **Lucide**, used under
the **ISC License**. Fourteen SVGs are bundled as Qt resources at
`resources/icons/` and loaded at paint time by `IconLoader`, which recolors
each one per the active theme rather than shipping pre-colored variants; the
full licence text ships alongside them at `resources/icons/LUCIDE-ISC.txt`.
Each SVG's `currentColor` paint value is replaced with a literal opaque colour
at the source file (Qt's SVG renderer does not resolve the CSS keyword), which
`IconLoader` then discards by recompositing with `QPainter::CompositionMode_SourceIn` —
so the literal colour baked into the file on disk is never actually seen.

Source: <https://github.com/lucide-icons/lucide>
