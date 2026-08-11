# Third-party notices

## Flutter engine and framework — BSD 3-Clause

The UI (`app_flutter/`) is built on the **Flutter** engine and framework,
copyright Google LLC, used under the **BSD 3-Clause License**. A distributed
binary bundles the Flutter engine (`flutter_linux_gtk.so` / `Flutter.dylib` /
`flutter_windows.dll`, whichever the target platform uses) and the compiled
Dart runtime. Flutter's own third-party notices (covering Skia and the rest
of the engine's dependencies) are reproduced by the Flutter SDK at
`flutter licenses` and surfaced in-app by `LicenseRegistry` if a licence
page is added; no separate copy is kept here because they change with the
Flutter SDK version this project is built against, not with this project's
own source.

Source: <https://github.com/flutter/flutter>

## Dart packages (`app_flutter/pubspec.yaml`)

Each package below is a direct dependency of the Flutter UI and ships inside
the built binary, under its own permissive licence (BSD-3-Clause or MIT —
see each package's own `LICENSE` on pub.dev for the exact text):

| Package | Licence |
|---|---|
| `flutter_riverpod` (state management) | MIT |
| `go_router` (routing) | BSD-3-Clause |
| `path_provider` | BSD-3-Clause |
| `ffi` (native interop with `gbm_capi`) | BSD-3-Clause |
| `flutter_svg` (renders the Lucide icons below) | MIT |
| `shared_preferences` (theme persistence) | BSD-3-Clause |
| `cupertino_icons` | MIT |

`flutter_lints`, `flutter_test`, and other `dev_dependencies` are build/test
tooling only and are never linked into a distributed binary.

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
SemiBold, Bold) are bundled as Flutter assets at `app_flutter/assets/fonts/`
and declared as the `Inter` font family in `app_flutter/pubspec.yaml`; the
full licence text ships alongside them at
`app_flutter/assets/fonts/Inter-OFL.txt`.

Source: <https://github.com/rsms/inter> (v4.1 release,
<https://github.com/rsms/inter/releases/tag/v4.1>)

## JetBrains Mono — SIL Open Font License 1.1

The monospace font (SHAs, branch tags, diff lines) is **JetBrains Mono** by
The JetBrains Mono Project Authors, used under the **SIL Open Font License,
Version 1.1**. Two static weights (Regular, Medium) are bundled as Flutter
assets at `app_flutter/assets/fonts/` and declared as the `JetBrains Mono`
font family in `app_flutter/pubspec.yaml`; the full licence text ships
alongside them at `app_flutter/assets/fonts/JetBrainsMono-OFL.txt`.

Source: <https://github.com/JetBrains/JetBrainsMono> (v2.304 release,
<https://github.com/JetBrains/JetBrainsMono/releases/tag/v2.304>)

## Lucide — ISC License

Toolbar, sidebar, and file-status icons are drawn from **Lucide**, used under
the **ISC License**. Fourteen SVGs are bundled as Flutter assets at
`app_flutter/assets/icons/` and rendered by `LucideIcon`
(`app_flutter/lib/widgets/lucide_icon.dart`) via the `flutter_svg` package,
which recolors each one per the active theme at paint time (a `ColorFilter`
applied over the loaded SVG) rather than shipping pre-colored variants; the
full licence text ships alongside them at
`app_flutter/assets/icons/LUCIDE-ISC.txt`.

Source: <https://github.com/lucide-icons/lucide>
