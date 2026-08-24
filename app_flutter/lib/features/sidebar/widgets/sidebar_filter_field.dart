import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';

/// P02-14's filter box and its 命中/總數 readout.
///
/// Cmd/Ctrl+Shift+E (`editFilterBranches`) focuses this via the [focusNode]
/// the panel passes down. Matching itself lives in `branch_filter.dart` and
/// covers branches, tags and stashes from this one box (rule 1).
///
/// Presentational: it owns no query state. The panel holds the controller
/// (the query outlives this widget -- it is provider-backed so that hiding
/// and re-showing the sidebar keeps the filter in force) and computes both
/// counts from the same filtered lists it renders.
class SidebarFilterField extends StatelessWidget {
  const SidebarFilterField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.isFiltering,
    required this.hasQuery,
    required this.hits,
    required this.total,
    required this.onChanged,
    required this.onClear,
    required this.onEnterFirstResult,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;

  /// Whether a non-blank query is in force -- i.e. the query trimmed is not
  /// empty. Drives the 命中/總數 readout.
  final bool isFiltering;

  /// Whether the field holds *any* text, trimmed or not.
  ///
  /// Deliberately separate from [isFiltering], and not derived from it: a
  /// whitespace-only query filters nothing (so no count is shown) but is
  /// still something the clear button has to be able to remove. Collapsing
  /// the two would strand the user with text they cannot clear by clicking.
  final bool hasQuery;

  final int hits;
  final int total;

  final ValueChanged<String> onChanged;

  /// P02-14 rule 8. Shared by Esc and the clear button so the two cannot
  /// drift.
  final VoidCallback onClear;

  /// P02-14 rule 9: 「↓ 直接跳進第一個結果」.
  final VoidCallback onEnterFirstResult;

  static const BoxConstraints _iconSlot = BoxConstraints(
    minWidth: 28,
    minHeight: 28,
  );

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    OutlineInputBorder border(Color c) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: BorderSide(color: c),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        GbmSpacing.space3,
        0,
        GbmSpacing.space3,
        GbmSpacing.space2,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: SizedBox(
              height: 28,
              // P02-14 rules 8 and 9. Placed here rather than on the panel:
              // this is the innermost `Shortcuts` above the field, so it
              // resolves Esc and ↓ before the app-level
              // `DefaultTextEditingShortcuts` gets them -- and it is scoped
              // to the field, so the tree's own Esc (MULTIKEYS' collapse) is
              // untouched. Same focus-scope reasoning as Ctrl/Cmd+A being
              // bound to the tree only.
              child: CallbackShortcuts(
                bindings: <ShortcutActivator, VoidCallback>{
                  const SingleActivator(LogicalKeyboardKey.escape): onClear,
                  const SingleActivator(LogicalKeyboardKey.arrowDown):
                      onEnterFirstResult,
                },
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  style: TextStyle(
                    fontSize: GbmTypography.textSm,
                    color: colors.textPrimary,
                  ),
                  onChanged: onChanged,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Filter branches',
                    hintStyle: TextStyle(
                      fontSize: GbmTypography.textSm,
                      color: colors.textTertiary,
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      size: 14,
                      color: colors.textTertiary,
                    ),
                    prefixIconConstraints: _iconSlot,
                    suffixIcon: !hasQuery
                        ? null
                        : IconButton(
                            icon: Icon(
                              Icons.close,
                              size: 14,
                              color: colors.textTertiary,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: _iconSlot,
                            onPressed: onClear,
                          ),
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: GbmSpacing.space1,
                    ),
                    filled: true,
                    fillColor: colors.surfaceSunken,
                    border: border(colors.borderSubtle),
                    enabledBorder: border(colors.borderSubtle),
                    focusedBorder: border(colors.borderFocus),
                  ),
                ),
              ),
            ),
          ),
          // Only while filtering: "6/6" on an untouched sidebar is noise, and
          // spec describes the count as part of the filter's behaviour rather
          // than as a permanent counter.
          if (isFiltering)
            Padding(
              padding: const EdgeInsets.only(left: GbmSpacing.space2),
              child: Text(
                '$hits/$total',
                style: TextStyle(
                  fontSize: GbmTypography.textXs,
                  color: colors.textTertiary,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
