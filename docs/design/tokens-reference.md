# Design tokens — source of truth

Verbatim from the claude.ai design project `f6b7d1fd-84d4-4b13-874a-74f990a6ba21`
("Git Branch Manager — Pages, Menus, Context"), files under
`_ds/git-branch-manager-design-system-4363160a-9396-4ffb-97b5-e5990b4e3db3/tokens/`.
Kept here so implementation does not depend on re-fetching the design project.

## colors.css

```css
/* Three interchangeable visual directions, selected via [data-theme] on <html> or any wrapper.
   Each defines the full semantic token set so components never branch on theme. */
:root,[data-theme="neutral-professional"]{
--base-white:#ffffff;--base-black:#0b0d10;
--gray-50:#f7f8f9;--gray-100:#eef0f2;--gray-200:#dfe3e7;--gray-300:#c3cad1;--gray-400:#98a3ad;--gray-500:#6b7684;--gray-600:#4f5966;--gray-700:#3a424c;--gray-800:#262c33;--gray-900:#171b1f;
--accent-50:#eaf1fe;--accent-100:#d0e2fd;--accent-300:#7aaef9;--accent-500:#2f81f7;--accent-600:#1f6ce0;--accent-700:#1857b8;
--green-500:#1a8a4a;--green-600:#137a3f;--red-500:#d33d3d;--red-600:#b32c2c;--amber-500:#c97a17;--purple-500:#7358d1;
--surface-app:var(--gray-50);--surface-panel:var(--base-white);--surface-panel-raised:var(--base-white);--surface-sunken:var(--gray-100);--surface-hover:var(--gray-100);--surface-selected:var(--accent-50);--surface-overlay:var(--base-white);
--border-subtle:var(--gray-200);--border-default:var(--gray-300);--border-strong:var(--gray-400);--border-focus:var(--accent-500);
--text-primary:var(--gray-900);--text-secondary:var(--gray-600);--text-tertiary:var(--gray-500);--text-on-accent:var(--base-white);--text-link:var(--accent-600);
--accent:var(--accent-500);--accent-hover:var(--accent-600);--accent-active:var(--accent-700);--accent-subtle:var(--accent-50);
--success:var(--green-500);--danger:var(--red-500);--danger-hover:var(--red-600);--warning:var(--amber-500);
--graph-lane-1:var(--accent-500);--graph-lane-2:#7358d1;--graph-lane-3:#1a8a4a;--graph-lane-4:#c97a17;--graph-lane-5:#d33d3d;--graph-lane-6:#0e9aa7;
--diff-add-bg:#e6f6ec;--diff-add-text:#136c37;--diff-del-bg:#fbeaea;--diff-del-text:#a32e2e;--diff-add-strong:#bfe9cd;--diff-del-strong:#f3c8c8;
--scrollbar-thumb:var(--gray-300);
}
[data-theme="dark-technical"]{
--surface-app:#0d1117;--surface-panel:#0d1117;--surface-panel-raised:#161b22;--surface-sunken:#010409;--surface-hover:#161b22;--surface-selected:#0d2a4d;--surface-overlay:#1c2128;
--border-subtle:#21262d;--border-default:#30363d;--border-strong:#3d444d;--border-focus:#2f81f7;
--text-primary:#e6edf3;--text-secondary:#9198a1;--text-tertiary:#6e7681;--text-on-accent:#ffffff;--text-link:#4c9bff;
--accent:#2f81f7;--accent-hover:#4c9bff;--accent-active:#1f6ce0;--accent-subtle:#0d2a4d;
--success:#3fb950;--danger:#f85149;--danger-hover:#ff6a63;--warning:#d29922;
--graph-lane-1:#4c9bff;--graph-lane-2:#a371f7;--graph-lane-3:#3fb950;--graph-lane-4:#d29922;--graph-lane-5:#f85149;--graph-lane-6:#39c5cf;
--diff-add-bg:#0f2e1a;--diff-add-text:#7ee2a8;--diff-del-bg:#3a1414;--diff-del-text:#ff9b93;--diff-add-strong:#173e24;--diff-del-strong:#4d1c1c;
--scrollbar-thumb:#30363d;
}
[data-theme="light-ide"]{
--surface-app:#ffffff;--surface-panel:#ffffff;--surface-panel-raised:#ffffff;--surface-sunken:#f5f6f8;--surface-hover:#f0f2f5;--surface-selected:#e4edfd;--surface-overlay:#ffffff;
--border-subtle:#eaecef;--border-default:#dcdfe4;--border-strong:#c6cad1;--border-focus:#2f81f7;
--text-primary:#1c2128;--text-secondary:#57606a;--text-tertiary:#8b949e;--text-on-accent:#ffffff;--text-link:#1f6ce0;
--accent:#2f81f7;--accent-hover:#1f6ce0;--accent-active:#1857b8;--accent-subtle:#eaf1fe;
--success:#1a7f37;--danger:#cf222e;--danger-hover:#a40e26;--warning:#9a6700;
--graph-lane-1:#2f81f7;--graph-lane-2:#8250df;--graph-lane-3:#1a7f37;--graph-lane-4:#9a6700;--graph-lane-5:#cf222e;--graph-lane-6:#1b7c83;
--diff-add-bg:#e9fbee;--diff-add-text:#116329;--diff-del-bg:#ffebe9;--diff-del-text:#82241f;--diff-add-strong:#c9f0d4;--diff-del-strong:#ffc9c2;
--scrollbar-thumb:#dcdfe4;
}
```

## typography.css

```css
/* @import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500;600&display=swap'); */
:root{
--font-ui:"Inter",-apple-system,"Segoe UI",sans-serif;
--font-mono:"JetBrains Mono","SF Mono",Consolas,monospace;
--text-xs:11px;--text-sm:12.5px;--text-base:13.5px;--text-md:15px;--text-lg:18px;--text-xl:22px;--text-2xl:28px;
--leading-tight:1.25;--leading-normal:1.5;--leading-relaxed:1.65;
--weight-regular:400;--weight-medium:500;--weight-semibold:600;--weight-bold:700;
}
```
(In the native app, fonts are bundled as `.ttf` resources, not loaded from Google Fonts CDN.)

## spacing.css

```css
:root{
--space-1:4px;--space-2:8px;--space-3:12px;--space-4:16px;--space-5:20px;--space-6:24px;--space-8:32px;--space-10:40px;--space-12:48px;--space-16:64px;
--row-h-compact:26px;--row-h-comfortable:34px;
--radius-sm:4px;--radius-md:6px;--radius-lg:10px;--radius-full:999px;
}
```

## effects.css

```css
:root{
--shadow-sm:0 1px 2px rgba(0,0,0,.08);
--shadow-md:0 4px 12px rgba(0,0,0,.12);
--shadow-lg:0 12px 32px rgba(0,0,0,.18);
--shadow-focus:0 0 0 3px var(--accent-subtle);
--ease-standard:cubic-bezier(.2,.8,.2,1);
--duration-fast:100ms;
--duration-base:160ms;
}
[data-theme="dark-technical"]{
--shadow-sm:0 1px 2px rgba(0,0,0,.4);
--shadow-md:0 4px 16px rgba(0,0,0,.5);
--shadow-lg:0 16px 40px rgba(0,0,0,.6);
}
```

## components.css (class reference — for QSS selector naming parity, not applied verbatim)

```css
.gbm-btn{font-family:var(--font-ui);font-size:var(--text-sm);font-weight:var(--weight-medium);border-radius:var(--radius-md);padding:0 var(--space-3);height:30px;display:inline-flex;align-items:center;gap:var(--space-2);border:1px solid transparent;cursor:pointer;white-space:nowrap}
.gbm-btn-primary{background:var(--accent);color:var(--text-on-accent)}
.gbm-btn-primary:hover{background:var(--accent-hover)}
.gbm-btn-primary:active{background:var(--accent-active)}
.gbm-btn-secondary{background:var(--surface-panel-raised);border-color:var(--border-default);color:var(--text-primary)}
.gbm-btn-secondary:hover{background:var(--surface-hover)}
.gbm-btn-ghost{background:transparent;color:var(--text-secondary)}
.gbm-btn-ghost:hover{background:var(--surface-hover);color:var(--text-primary)}
.gbm-btn-danger{background:transparent;border-color:var(--border-default);color:var(--danger)}
.gbm-btn-danger:hover{background:var(--diff-del-bg);border-color:var(--danger)}
.gbm-btn[disabled]{opacity:.45;cursor:not-allowed}
.gbm-btn-sm{height:24px;font-size:var(--text-xs);padding:0 var(--space-2)}
.gbm-iconbtn{width:28px;height:28px;border-radius:var(--radius-md);border:1px solid transparent;background:transparent;color:var(--text-secondary)}
.gbm-iconbtn:hover{background:var(--surface-hover);color:var(--text-primary)}
.gbm-iconbtn.active{background:var(--accent-subtle);color:var(--accent)}

.gbm-input{font-family:var(--font-ui);font-size:var(--text-sm);height:30px;padding:0 var(--space-3);border-radius:var(--radius-md);border:1px solid var(--border-default);background:var(--surface-panel);color:var(--text-primary)}
.gbm-input::placeholder{color:var(--text-tertiary)}
.gbm-input:focus{outline:none;border-color:var(--border-focus);box-shadow:var(--shadow-focus)}

.gbm-checkbox{width:15px;height:15px;border-radius:3px;border:1.5px solid var(--border-strong);background:var(--surface-panel)}
.gbm-checkbox.checked,.gbm-checkbox.indeterminate{background:var(--accent);border-color:var(--accent)}

.gbm-tag{display:inline-flex;gap:6px;font-family:var(--font-mono);font-size:var(--text-xs);font-weight:var(--weight-medium);padding:2px 8px;border-radius:var(--radius-full);border:1px solid var(--border-default);color:var(--text-secondary);background:var(--surface-panel-raised)}
.gbm-tag-branch{color:var(--accent);border-color:var(--accent-subtle);background:var(--accent-subtle)}
.gbm-tag-branch.current{background:var(--accent);color:var(--text-on-accent);border-color:var(--accent)}
.gbm-tag-tag{color:var(--warning);background:transparent;border-color:var(--border-default)}
.gbm-tag-remote{color:var(--text-tertiary)}

.gbm-badge{min-width:18px;height:18px;padding:0 5px;border-radius:var(--radius-full);font-size:10.5px;font-weight:var(--weight-semibold);font-family:var(--font-mono)}
.gbm-badge-added{background:var(--diff-add-bg);color:var(--diff-add-text)}
.gbm-badge-removed{background:var(--diff-del-bg);color:var(--diff-del-text)}
.gbm-badge-neutral{background:var(--surface-sunken);color:var(--text-secondary)}

.gbm-panel{background:var(--surface-panel);border:1px solid var(--border-subtle);border-radius:var(--radius-lg)}
.gbm-panel-raised{background:var(--surface-panel-raised);box-shadow:var(--shadow-md);border-radius:var(--radius-lg)}

.gbm-tabs{display:flex;gap:var(--space-1);border-bottom:1px solid var(--border-subtle)}
.gbm-tab{font-size:var(--text-sm);font-weight:var(--weight-medium);color:var(--text-secondary);padding:var(--space-2) var(--space-3);border-bottom:2px solid transparent}
.gbm-tab.active{color:var(--text-primary);border-bottom-color:var(--accent)}

.gbm-banner{gap:var(--space-3);padding:var(--space-2) var(--space-4);font-size:var(--text-sm);border-bottom:1px solid var(--border-subtle)}
.gbm-banner-info{background:var(--accent-subtle);color:var(--text-primary)}
.gbm-banner-warning{background:var(--diff-del-bg);color:var(--diff-del-text)}

.gbm-menu{background:var(--surface-overlay);border:1px solid var(--border-default);border-radius:var(--radius-md);box-shadow:var(--shadow-lg);padding:4px;min-width:220px;font-size:var(--text-sm)}
.gbm-menu-item{padding:6px 10px;border-radius:var(--radius-sm);color:var(--text-primary)}
.gbm-menu-item:hover{background:var(--accent);color:var(--text-on-accent)}
.gbm-menu-item.danger{color:var(--danger)}
.gbm-menu-item.danger:hover{background:var(--danger);color:#fff}
.gbm-menu-shortcut{font-family:var(--font-mono);font-size:10.5px;color:var(--text-tertiary)}
.gbm-menu-sep{height:1px;background:var(--border-subtle);margin:4px 6px}

.gbm-row{gap:var(--space-2);height:var(--row-h-comfortable);padding:0 var(--space-3);border-radius:var(--radius-sm)}
.gbm-row:hover{background:var(--surface-hover)}
.gbm-row.selected{background:var(--surface-selected)}
.gbm-mono{font-family:var(--font-mono)}

.gbm-diffline{font-family:var(--font-mono);font-size:var(--text-sm);padding:1px 10px;white-space:pre;line-height:1.6}
.gbm-diffline-add{background:var(--diff-add-bg);color:var(--diff-add-text)}
.gbm-diffline-del{background:var(--diff-del-bg);color:var(--diff-del-text)}
.gbm-diffline-ctx{color:var(--text-secondary)}
.gbm-diffline-hunk{color:var(--text-tertiary);background:var(--surface-sunken)}
```

## Departure from the source: `--ref-chip-fill` / `--ref-chip-text`

The verbatim spec above (`.gbm-tag-branch`, line 119) has the non-current branch
chip use `--accent-subtle` for both border and background. In implementation
that token turned out to be **byte-identical to `--surface-selected`** in
`dark-technical` (`#0d2a4d`) and `neutral-professional` (`#eaf1fe`), so the chip
disappeared entirely on a selected commit row — a real readability bug, not an
implementation slip; it traces back to this source file.

`Token::RefChipFill` / `Token::RefChipText` (`src/app/theme/Tokens.h`,
`ThemeTokens.cpp`) exist to fix that and are **not** part of the design
project's token set — do not "correct" them back to `--accent-subtle` to match
this doc. Values, chosen for ≥4.5:1 text contrast and visible separation from
`--surface-selected`/`--accent-subtle` in every theme:

| Theme | `--ref-chip-fill` | `--ref-chip-text` |
|---|---|---|
| dark-technical | `#1c3f66` | `#eaf1fe` |
| light-ide | `#c7dbfa` | `#1857b8` |
| neutral-professional | `#c7dbfa` | `#1857b8` |

Consumed directly by `PillPainter::colorsForRef` (C++), not via an `app.qss`
`@` placeholder, so there is no corresponding entry in `ThemeManager.cpp`'s
placeholder table.
