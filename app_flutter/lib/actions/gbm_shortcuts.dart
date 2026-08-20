import 'package:flutter/services.dart';

import 'gbm_action_id.dart';

/// Represents a keyboard shortcut with its trigger key and modifiers.
///
/// This is a pure data class independent of Flutter's widget/action system.
/// It can be converted to platform-specific keyboard handlers (e.g., SingleActivator
/// in the widget layer) when rendering.
class GbmKeyboardShortcut {
  /// Creates a keyboard shortcut.
  const GbmKeyboardShortcut({
    required this.trigger,
    required this.control,
    required this.meta,
    this.shift = false,
    this.alt = false,
  });

  /// The key that triggers this shortcut.
  final LogicalKeyboardKey trigger;

  /// Whether the Ctrl/Cmd key is required.
  ///
  /// On macOS this will be `false` (use [meta] instead).
  /// On Windows/Linux this will be `true`.
  final bool control;

  /// Whether the Meta (Cmd on macOS) key is required.
  ///
  /// On macOS this will be `true`.
  /// On Windows/Linux this will be `false` (use [control] instead).
  final bool meta;

  /// Whether the Shift key is required.
  final bool shift;

  /// Whether the Alt key is required.
  final bool alt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GbmKeyboardShortcut &&
          runtimeType == other.runtimeType &&
          trigger == other.trigger &&
          control == other.control &&
          meta == other.meta &&
          shift == other.shift &&
          alt == other.alt;

  @override
  int get hashCode =>
      trigger.hashCode ^
      control.hashCode ^
      meta.hashCode ^
      shift.hashCode ^
      alt.hashCode;

  /// Human-readable form for the Keyboard shortcuts dialog and the
  /// Preferences → Shortcuts list, e.g. `⌘⇧P` on macOS, `Ctrl+Shift+P`
  /// elsewhere.
  ///
  /// Modifier order follows each platform's own convention: macOS renders
  /// symbols with no separator in the Control-Option-Shift-Command order the
  /// Apple HIG specifies, and everything else spells the modifiers out
  /// joined by `+`. Derived from the shortcut's own fields rather than
  /// stored as a second copy of the label, so a rebinding cannot leave the
  /// displayed text stale.
  String get displayLabel {
    final String key = _triggerLabel(trigger);
    if (meta) {
      return <String>[if (alt) '⌥', if (shift) '⇧', '⌘', key].join();
    }
    return <String>[
      if (control) 'Ctrl',
      if (alt) 'Alt',
      if (shift) 'Shift',
      key,
    ].join('+');
  }

  /// [LogicalKeyboardKey.keyLabel] is already right for letters and digits;
  /// only the keys whose label is empty or unidiomatic are special-cased.
  static String _triggerLabel(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.comma) return ',';
    if (key == LogicalKeyboardKey.slash) return '/';
    if (key == LogicalKeyboardKey.backquote) return '`';
    if (key == LogicalKeyboardKey.enter) return 'Enter';
    if (key == LogicalKeyboardKey.tab) return 'Tab';
    if (key == LogicalKeyboardKey.escape) return 'Esc';
    final String label = key.keyLabel;
    return label.isEmpty ? key.debugName ?? '?' : label;
  }

  @override
  String toString() =>
      'GbmKeyboardShortcut(trigger: $trigger, meta: $meta, control: $control, shift: $shift, alt: $alt)';
}

/// Returns a map of GbmActionId to GbmKeyboardShortcut keyboard shortcuts.
///
/// Exactly 36 of the 52 action IDs have keyboard shortcuts. The remaining 16
/// are either intentionally unbound (per spec) or handled specially (e.g., fileExit).
/// `gbm_shortcuts_test.dart` asserts both numbers, so they cannot drift
/// silently — but nothing checks the per-group counts in the comments
/// below, which is how `// Shift group` came to say 14 while holding 15.
///
/// The [isMacOS] parameter controls whether shortcuts use `meta` (macOS) or
/// `control` (Windows/Linux). This is a pure function for testability; it does
/// not read [dart:io]'s Platform at the top level.
Map<GbmActionId, GbmKeyboardShortcut> gbmActionShortcuts(bool isMacOS) {
  return {
    // No-shift group (20)
    GbmActionId.fileNewRepository: _makeShortcut(
      LogicalKeyboardKey.keyN,
      isMacOS,
    ),
    GbmActionId.fileOpenRepository: _makeShortcut(
      LogicalKeyboardKey.keyO,
      isMacOS,
    ),
    GbmActionId.fileSwitchRepository: _makeShortcut(
      LogicalKeyboardKey.keyR,
      isMacOS,
    ),
    GbmActionId.fileCloseWindow: _makeShortcut(
      LogicalKeyboardKey.keyW,
      isMacOS,
    ),
    GbmActionId.filePreferences: _makeShortcut(
      LogicalKeyboardKey.comma,
      isMacOS,
    ),
    GbmActionId.editUndo: _makeShortcut(LogicalKeyboardKey.keyZ, isMacOS),
    GbmActionId.editCut: _makeShortcut(LogicalKeyboardKey.keyX, isMacOS),
    GbmActionId.editCopy: _makeShortcut(LogicalKeyboardKey.keyC, isMacOS),
    GbmActionId.editPaste: _makeShortcut(LogicalKeyboardKey.keyV, isMacOS),
    GbmActionId.editFindInHistory: _makeShortcut(
      LogicalKeyboardKey.keyF,
      isMacOS,
    ),
    GbmActionId.viewHistory: _makeShortcut(LogicalKeyboardKey.digit1, isMacOS),
    GbmActionId.viewWorkingCopy: _makeShortcut(
      LogicalKeyboardKey.digit2,
      isMacOS,
    ),
    GbmActionId.viewNextTab: _makeShortcut(LogicalKeyboardKey.tab, isMacOS),
    GbmActionId.viewCommitDetail: _makeShortcut(
      LogicalKeyboardKey.keyD,
      isMacOS,
    ),
    GbmActionId.viewToggleSidebar: _makeShortcut(
      LogicalKeyboardKey.keyB,
      isMacOS,
    ),
    GbmActionId.viewResetPanelSizes: _makeShortcut(
      LogicalKeyboardKey.digit0,
      isMacOS,
    ),
    GbmActionId.repositoryPush: _makeShortcut(LogicalKeyboardKey.keyP, isMacOS),
    GbmActionId.repositoryCommit: _makeShortcut(
      LogicalKeyboardKey.enter,
      isMacOS,
    ),
    GbmActionId.repositoryOpenInTerminal: _makeShortcut(
      LogicalKeyboardKey.backquote,
      isMacOS,
    ),
    GbmActionId.helpKeyboardShortcuts: _makeShortcut(
      LogicalKeyboardKey.slash,
      isMacOS,
    ),

    // Shift group (15)
    GbmActionId.fileCloneRepository: _makeShortcut(
      LogicalKeyboardKey.keyN,
      isMacOS,
      shift: true,
    ),
    GbmActionId.editRedo: _makeShortcut(
      LogicalKeyboardKey.keyZ,
      isMacOS,
      shift: true,
    ),
    GbmActionId.editFilterBranches: _makeShortcut(
      LogicalKeyboardKey.keyE,
      isMacOS,
      shift: true,
    ),
    GbmActionId.viewFileListAsTree: _makeShortcut(
      LogicalKeyboardKey.keyT,
      isMacOS,
      shift: true,
    ),
    GbmActionId.viewLog: _makeShortcut(
      LogicalKeyboardKey.keyL,
      isMacOS,
      shift: true,
    ),
    GbmActionId.repositoryFetch: _makeShortcut(
      LogicalKeyboardKey.keyF,
      isMacOS,
      shift: true,
    ),
    GbmActionId.repositoryPull: _makeShortcut(
      LogicalKeyboardKey.keyP,
      isMacOS,
      shift: true,
    ),
    GbmActionId.repositoryCompare: _makeShortcut(
      LogicalKeyboardKey.keyC,
      isMacOS,
      shift: true,
    ),
    GbmActionId.repositoryAmendLastCommit: _makeShortcut(
      LogicalKeyboardKey.keyA,
      isMacOS,
      shift: true,
    ),
    GbmActionId.repositoryStageAll: _makeShortcut(
      LogicalKeyboardKey.keyS,
      isMacOS,
      shift: true,
    ),
    GbmActionId.branchNewBranch: _makeShortcut(
      LogicalKeyboardKey.keyB,
      isMacOS,
      shift: true,
    ),
    GbmActionId.branchCheckout: _makeShortcut(
      LogicalKeyboardKey.keyO,
      isMacOS,
      shift: true,
    ),
    GbmActionId.branchMergeIntoCurrent: _makeShortcut(
      LogicalKeyboardKey.keyM,
      isMacOS,
      shift: true,
    ),
    GbmActionId.branchRebaseOnto: _makeShortcut(
      LogicalKeyboardKey.keyR,
      isMacOS,
      shift: true,
    ),
    GbmActionId.repositoryStageSelectedLines: _makeShortcut(
      LogicalKeyboardKey.enter,
      isMacOS,
      shift: true,
    ),

    // Bare-key group (1). The only shortcut in the spec's MENUS table with
    // no Ctrl/Cmd at all, so it cannot go through _makeShortcut() -- that
    // helper always sets one or the other. F2 is the platform convention
    // for rename on Windows and Linux, and spec's 260820 revision
    // ("Branch → Rename branch… = F2") adopts it on macOS too rather than
    // splitting the binding per platform.
    GbmActionId.branchRenameCurrentBranch: const GbmKeyboardShortcut(
      trigger: LogicalKeyboardKey.f2,
      control: false,
      meta: false,
    ),
  };
}

/// Creates a keyboard shortcut with the given key and platform-appropriate modifiers.
GbmKeyboardShortcut _makeShortcut(
  LogicalKeyboardKey trigger,
  bool isMacOS, {
  bool shift = false,
}) {
  return GbmKeyboardShortcut(
    trigger: trigger,
    meta: isMacOS,
    control: !isMacOS,
    shift: shift,
  );
}
