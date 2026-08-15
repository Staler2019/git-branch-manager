import 'package:flutter/material.dart';

/// The three theme variants defined in docs/design/tokens-reference.md's
/// `colors.css` (`[data-theme="..."]` selectors), ported verbatim.
enum GbmThemeVariant { darkTechnical, lightIde, neutralProfessional }

/// One theme variant's full semantic color set, so components never branch
/// on which variant is active -- mirrors the design doc's own stated intent
/// ("Each defines the full semantic token set so components never branch on
/// theme"). Field names match the CSS custom-property names 1:1 (camelCase
/// instead of kebab-case) so this file can be diffed against the source doc
/// by eye.
class GbmColors extends ThemeExtension<GbmColors> {
  const GbmColors({
    required this.surfaceApp,
    required this.surfacePanel,
    required this.surfacePanelRaised,
    required this.surfaceSunken,
    required this.surfaceHover,
    required this.surfaceSelected,
    required this.surfaceOverlay,
    required this.borderSubtle,
    required this.borderDefault,
    required this.borderStrong,
    required this.borderFocus,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textOnAccent,
    required this.textLink,
    required this.accent,
    required this.accentHover,
    required this.accentActive,
    required this.accentSubtle,
    required this.success,
    required this.danger,
    required this.dangerHover,
    required this.warning,
    required this.graphLanes,
    required this.diffAddBg,
    required this.diffAddText,
    required this.diffDelBg,
    required this.diffDelText,
    required this.diffAddStrong,
    required this.diffDelStrong,
    required this.scrollbarThumb,
    required this.refChipFill,
    required this.refChipText,
  });

  final Color surfaceApp;
  final Color surfacePanel;
  final Color surfacePanelRaised;
  final Color surfaceSunken;
  final Color surfaceHover;
  final Color surfaceSelected;
  final Color surfaceOverlay;

  final Color borderSubtle;
  final Color borderDefault;
  final Color borderStrong;
  final Color borderFocus;

  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textOnAccent;
  final Color textLink;

  final Color accent;
  final Color accentHover;
  final Color accentActive;
  final Color accentSubtle;

  final Color success;
  final Color danger;
  final Color dangerHover;
  final Color warning;

  /// `--graph-lane-1` .. `--graph-lane-6`, in order.
  final List<Color> graphLanes;

  final Color diffAddBg;
  final Color diffAddText;
  final Color diffDelBg;
  final Color diffDelText;
  final Color diffAddStrong;
  final Color diffDelStrong;

  final Color scrollbarThumb;

  /// Not part of the design doc's token set -- see "Departure from the
  /// source" in docs/design/tokens-reference.md. `.gbm-tag-branch`'s
  /// `--accent-subtle` fill is byte-identical to `--surface-selected` in two
  /// of the three themes, which makes a non-current branch chip disappear on
  /// a selected commit row. These two tokens exist purely to fix that; do
  /// not "correct" them back to accentSubtle.
  final Color refChipFill;
  final Color refChipText;

  /// Not implemented as a real per-field interpolation: the three variants
  /// are discrete design choices, not points on a gradient, and every place
  /// this app switches variant rebuilds `ThemeData` wholesale rather than
  /// animating between them (see theme_mode_provider.dart) -- `t < 0.5`
  /// picks whichever endpoint is closer, matching `ThemeExtension`'s
  /// contract without pretending a continuous blend means anything here.
  @override
  GbmColors lerp(ThemeExtension<GbmColors>? other, double t) {
    if (other is! GbmColors) return this;
    return t < 0.5 ? this : other;
  }

  @override
  GbmColors copyWith({
    Color? surfaceApp,
    Color? surfacePanel,
    Color? surfacePanelRaised,
    Color? surfaceSunken,
    Color? surfaceHover,
    Color? surfaceSelected,
    Color? surfaceOverlay,
    Color? borderSubtle,
    Color? borderDefault,
    Color? borderStrong,
    Color? borderFocus,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? textOnAccent,
    Color? textLink,
    Color? accent,
    Color? accentHover,
    Color? accentActive,
    Color? accentSubtle,
    Color? success,
    Color? danger,
    Color? dangerHover,
    Color? warning,
    List<Color>? graphLanes,
    Color? diffAddBg,
    Color? diffAddText,
    Color? diffDelBg,
    Color? diffDelText,
    Color? diffAddStrong,
    Color? diffDelStrong,
    Color? scrollbarThumb,
    Color? refChipFill,
    Color? refChipText,
  }) {
    return GbmColors(
      surfaceApp: surfaceApp ?? this.surfaceApp,
      surfacePanel: surfacePanel ?? this.surfacePanel,
      surfacePanelRaised: surfacePanelRaised ?? this.surfacePanelRaised,
      surfaceSunken: surfaceSunken ?? this.surfaceSunken,
      surfaceHover: surfaceHover ?? this.surfaceHover,
      surfaceSelected: surfaceSelected ?? this.surfaceSelected,
      surfaceOverlay: surfaceOverlay ?? this.surfaceOverlay,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      borderDefault: borderDefault ?? this.borderDefault,
      borderStrong: borderStrong ?? this.borderStrong,
      borderFocus: borderFocus ?? this.borderFocus,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      textOnAccent: textOnAccent ?? this.textOnAccent,
      textLink: textLink ?? this.textLink,
      accent: accent ?? this.accent,
      accentHover: accentHover ?? this.accentHover,
      accentActive: accentActive ?? this.accentActive,
      accentSubtle: accentSubtle ?? this.accentSubtle,
      success: success ?? this.success,
      danger: danger ?? this.danger,
      dangerHover: dangerHover ?? this.dangerHover,
      warning: warning ?? this.warning,
      graphLanes: graphLanes ?? this.graphLanes,
      diffAddBg: diffAddBg ?? this.diffAddBg,
      diffAddText: diffAddText ?? this.diffAddText,
      diffDelBg: diffDelBg ?? this.diffDelBg,
      diffDelText: diffDelText ?? this.diffDelText,
      diffAddStrong: diffAddStrong ?? this.diffAddStrong,
      diffDelStrong: diffDelStrong ?? this.diffDelStrong,
      scrollbarThumb: scrollbarThumb ?? this.scrollbarThumb,
      refChipFill: refChipFill ?? this.refChipFill,
      refChipText: refChipText ?? this.refChipText,
    );
  }
}

const Color _white = Color(0xFFFFFFFF);

const Color _gray50 = Color(0xFFF7F8F9);
const Color _gray100 = Color(0xFFEEF0F2);
const Color _gray200 = Color(0xFFDFE3E7);
const Color _gray300 = Color(0xFFC3CAD1);
const Color _gray400 = Color(0xFF98A3AD);
const Color _gray500 = Color(0xFF6B7684);
const Color _gray600 = Color(0xFF4F5966);
const Color _gray900 = Color(0xFF171B1F);

const Color _accent50 = Color(0xFFEAF1FE);
const Color _accent500 = Color(0xFF2F81F7);
const Color _accent600 = Color(0xFF1F6CE0);
const Color _accent700 = Color(0xFF1857B8);

const Color _green500 = Color(0xFF1A8A4A);
const Color _red500 = Color(0xFFD33D3D);
const Color _red600 = Color(0xFFB32C2C);
const Color _amber500 = Color(0xFFC97A17);

/// `[data-theme="neutral-professional"]` in colors.css.
const GbmColors _neutralProfessional = GbmColors(
  surfaceApp: _gray50,
  surfacePanel: _white,
  surfacePanelRaised: _white,
  surfaceSunken: _gray100,
  surfaceHover: _gray100,
  surfaceSelected: _accent50,
  surfaceOverlay: _white,
  borderSubtle: _gray200,
  borderDefault: _gray300,
  borderStrong: _gray400,
  borderFocus: _accent500,
  textPrimary: _gray900,
  textSecondary: _gray600,
  textTertiary: _gray500,
  textOnAccent: _white,
  textLink: _accent600,
  accent: _accent500,
  accentHover: _accent600,
  accentActive: _accent700,
  accentSubtle: _accent50,
  success: _green500,
  danger: _red500,
  dangerHover: _red600,
  warning: _amber500,
  graphLanes: <Color>[
    _accent500,
    Color(0xFF7358D1),
    Color(0xFF1A8A4A),
    Color(0xFFC97A17),
    Color(0xFFD33D3D),
    Color(0xFF0E9AA7),
  ],
  diffAddBg: Color(0xFFE6F6EC),
  diffAddText: Color(0xFF136C37),
  diffDelBg: Color(0xFFFBEAEA),
  diffDelText: Color(0xFFA32E2E),
  diffAddStrong: Color(0xFFBFE9CD),
  diffDelStrong: Color(0xFFF3C8C8),
  scrollbarThumb: _gray300,
  refChipFill: Color(0xFFC7DBFA),
  refChipText: _accent700,
);

/// `[data-theme="dark-technical"]` in colors.css.
const GbmColors _darkTechnical = GbmColors(
  surfaceApp: Color(0xFF0D1117),
  surfacePanel: Color(0xFF0D1117),
  surfacePanelRaised: Color(0xFF161B22),
  surfaceSunken: Color(0xFF010409),
  surfaceHover: Color(0xFF161B22),
  surfaceSelected: Color(0xFF0D2A4D),
  surfaceOverlay: Color(0xFF1C2128),
  borderSubtle: Color(0xFF21262D),
  borderDefault: Color(0xFF30363D),
  borderStrong: Color(0xFF3D444D),
  borderFocus: Color(0xFF2F81F7),
  textPrimary: Color(0xFFE6EDF3),
  textSecondary: Color(0xFF9198A1),
  textTertiary: Color(0xFF6E7681),
  textOnAccent: _white,
  textLink: Color(0xFF4C9BFF),
  accent: Color(0xFF2F81F7),
  accentHover: Color(0xFF4C9BFF),
  accentActive: Color(0xFF1F6CE0),
  accentSubtle: Color(0xFF0D2A4D),
  success: Color(0xFF3FB950),
  danger: Color(0xFFF85149),
  dangerHover: Color(0xFFFF6A63),
  warning: Color(0xFFD29922),
  graphLanes: <Color>[
    Color(0xFF4C9BFF),
    Color(0xFFA371F7),
    Color(0xFF3FB950),
    Color(0xFFD29922),
    Color(0xFFF85149),
    Color(0xFF39C5CF),
  ],
  diffAddBg: Color(0xFF0F2E1A),
  diffAddText: Color(0xFF7EE2A8),
  diffDelBg: Color(0xFF3A1414),
  diffDelText: Color(0xFFFF9B93),
  diffAddStrong: Color(0xFF173E24),
  diffDelStrong: Color(0xFF4D1C1C),
  scrollbarThumb: Color(0xFF30363D),
  refChipFill: Color(0xFF1C3F66),
  refChipText: Color(0xFFEAF1FE),
);

/// `[data-theme="light-ide"]` in colors.css.
const GbmColors _lightIde = GbmColors(
  surfaceApp: _white,
  surfacePanel: _white,
  surfacePanelRaised: _white,
  surfaceSunken: Color(0xFFF5F6F8),
  surfaceHover: Color(0xFFF0F2F5),
  surfaceSelected: Color(0xFFE4EDFD),
  surfaceOverlay: _white,
  borderSubtle: Color(0xFFEAECEF),
  borderDefault: Color(0xFFDCDFE4),
  borderStrong: Color(0xFFC6CAD1),
  borderFocus: Color(0xFF2F81F7),
  textPrimary: Color(0xFF1C2128),
  textSecondary: Color(0xFF57606A),
  textTertiary: Color(0xFF8B949E),
  textOnAccent: _white,
  textLink: _accent700,
  accent: _accent500,
  accentHover: _accent700,
  accentActive: Color(0xFF1857B8),
  accentSubtle: _accent50,
  success: Color(0xFF1A7F37),
  danger: Color(0xFFCF222E),
  dangerHover: Color(0xFFA40E26),
  warning: Color(0xFF9A6700),
  graphLanes: <Color>[
    _accent500,
    Color(0xFF8250DF),
    Color(0xFF1A7F37),
    Color(0xFF9A6700),
    Color(0xFFCF222E),
    Color(0xFF1B7C83),
  ],
  diffAddBg: Color(0xFFE9FBEE),
  diffAddText: Color(0xFF116329),
  diffDelBg: Color(0xFFFFEBE9),
  diffDelText: Color(0xFF82241F),
  diffAddStrong: Color(0xFFC9F0D4),
  diffDelStrong: Color(0xFFFFC9C2),
  scrollbarThumb: Color(0xFFDCDFE4),
  refChipFill: Color(0xFFC7DBFA),
  refChipText: _accent700,
);

GbmColors tokensFor(GbmThemeVariant variant) {
  return switch (variant) {
    GbmThemeVariant.darkTechnical => _darkTechnical,
    GbmThemeVariant.lightIde => _lightIde,
    GbmThemeVariant.neutralProfessional => _neutralProfessional,
  };
}

/// `typography.css`.
abstract final class GbmTypography {
  static const String fontUi = 'Inter';
  static const String fontMono = 'JetBrains Mono';

  static const double textXs = 11;
  static const double textSm = 12.5;
  static const double textBase = 13.5;
  static const double textMd = 15;
  static const double textLg = 18;
  static const double textXl = 22;
  static const double text2xl = 28;

  static const double leadingTight = 1.25;
  static const double leadingNormal = 1.5;
  static const double leadingRelaxed = 1.65;

  static const FontWeight weightRegular = FontWeight.w400;
  static const FontWeight weightMedium = FontWeight.w500;
  static const FontWeight weightSemibold = FontWeight.w600;
  static const FontWeight weightBold = FontWeight.w700;
}

/// `spacing.css`.
abstract final class GbmSpacing {
  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 20;
  static const double space6 = 24;
  static const double space8 = 32;
  static const double space10 = 40;
  static const double space12 = 48;
  static const double space16 = 64;

  static const double rowHeightCompact = 26;
  static const double rowHeightComfortable = 34;

  static const double radiusSm = 4;
  static const double radiusMd = 6;
  static const double radiusLg = 10;
  static const double radiusFull = 999;
}

/// `effects.css`. Shadow alpha differs for dark-technical (deeper shadows on
/// a dark surface read correctly; the same alpha on light would be nearly
/// invisible), so this is a function of variant rather than a flat constant.
abstract final class GbmEffects {
  static const Duration durationFast = Duration(milliseconds: 100);
  static const Duration durationBase = Duration(milliseconds: 160);
  static const Curve easeStandard = Cubic(0.2, 0.8, 0.2, 1);

  static List<BoxShadow> shadowSm(GbmThemeVariant variant) => <BoxShadow>[
    BoxShadow(
      color: const Color(0xFF000000).withValues(
        alpha: variant == GbmThemeVariant.darkTechnical ? 0.4 : 0.08,
      ),
      blurRadius: 2,
      offset: const Offset(0, 1),
    ),
  ];

  static List<BoxShadow> shadowMd(GbmThemeVariant variant) => <BoxShadow>[
    BoxShadow(
      color: const Color(0xFF000000).withValues(
        alpha: variant == GbmThemeVariant.darkTechnical ? 0.5 : 0.12,
      ),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> shadowLg(GbmThemeVariant variant) => <BoxShadow>[
    BoxShadow(
      color: const Color(0xFF000000).withValues(
        alpha: variant == GbmThemeVariant.darkTechnical ? 0.6 : 0.18,
      ),
      blurRadius: 32,
      offset: const Offset(0, 12),
    ),
  ];
}

/// A single splitter's persisted-layout spec, from spec page 09's SPLITTERS
/// table. Splitters are proportion-based (`flexRatio`) or single-pane
/// absolute-width (`defaultExtent`) depending on how many panes they
/// divide -- never both, so exactly one is non-null per instance.
class GbmSplitterSpec {
  const GbmSplitterSpec.extent({
    required this.defaultExtent,
    required this.minExtent,
    this.collapsedByDefault = false,
  }) : flexRatio = null;

  const GbmSplitterSpec.flex({
    required this.flexRatio,
    required this.minExtent,
    this.collapsedByDefault = false,
  }) : defaultExtent = null;

  /// Single-pane default width/height in logical pixels (e.g. sidebar).
  /// Null for multi-pane splitters, which use [flexRatio] instead.
  final double? defaultExtent;

  /// Relative flex weights for a multi-pane splitter (e.g. `[62, 38]` for a
  /// 62/38 split), stored as proportions rather than absolute pixels so the
  /// panes resize together when the window resizes. Null for single-pane
  /// splitters, which use [defaultExtent] instead.
  final List<double>? flexRatio;

  /// Minimum extent any one pane may be dragged to before it snaps and
  /// refuses to shrink further.
  final double minExtent;

  /// `main.log` starts collapsed (height 0) until the user opens it.
  final bool collapsedByDefault;
}

/// Structural chrome sizes and splitter defaults from the design spec
/// (`Flutter Desktop Spec.dc.html`, pages 02/03/06/09). Colors and type
/// live in [GbmColors]/[GbmTypography]; this holds the pixel dimensions
/// that were previously scattered as inline literals across widgets, so a
/// future spec revision has one edit site instead of many.
abstract final class GbmLayout {
  static const double menuBarHeight = 32;
  static const double topBarHeight = 44;
  static const double tabRowHeight = 36;

  static const double sidebarDefaultWidth = 250;
  static const double sidebarMinWidth = 180;

  static const double workingCopyLeftColumnWidth = 280;

  static const double dialogDefaultWidth = 480;
  static const double dialogMaxHeight = 560;

  static const double menuMinWidth = 220;

  static const double graphLaneWidth = 18;

  static const double diffGutterWidth = 36;
  static const double diffMarkerWidth = 14;

  /// Sidebar <-> central area.
  static const GbmSplitterSpec splitterMainSidebar = GbmSplitterSpec.extent(
    defaultExtent: sidebarDefaultWidth,
    minExtent: sidebarMinWidth,
  );

  /// Commit list <-> commit detail.
  static const GbmSplitterSpec splitterMainDetail = GbmSplitterSpec.flex(
    flexRatio: <double>[62, 38],
    minExtent: 160,
  );

  /// Central area <-> Changed files (History tab only).
  static const GbmSplitterSpec splitterMainFiles = GbmSplitterSpec.extent(
    defaultExtent: 186,
    minExtent: 140,
  );

  /// Unstaged <-> Staged columns.
  static const GbmSplitterSpec splitterWcColumns = GbmSplitterSpec.flex(
    flexRatio: <double>[1, 1],
    minExtent: 200,
  );

  /// File columns <-> diff pane.
  static const GbmSplitterSpec splitterWcDiff = GbmSplitterSpec.flex(
    flexRatio: <double>[46, 54],
    minExtent: 150,
  );

  /// Main content <-> log drawer. Collapsed by default so it takes no
  /// space until the user opens it.
  static const GbmSplitterSpec splitterMainLog = GbmSplitterSpec.extent(
    defaultExtent: 0,
    minExtent: 90,
    collapsedByDefault: true,
  );

  /// Conflict window: file list <-> three-pane area.
  static const GbmSplitterSpec splitterCwFiles = GbmSplitterSpec.extent(
    defaultExtent: 158,
    minExtent: 120,
  );

  /// Conflict window: left (ours) <-> result <-> right (theirs). The
  /// middle (result) column is always widest.
  static const GbmSplitterSpec splitterCwPanes = GbmSplitterSpec.flex(
    flexRatio: <double>[1, 1.12, 1],
    minExtent: 220,
  );
}
