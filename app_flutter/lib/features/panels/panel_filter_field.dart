import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';

/// Spec page 19 樣板規則 2's 「右端固定是 filter」.
///
/// Shaped after `features/sidebar/widgets/sidebar_filter_field.dart` — same
/// 28px height, `search` prefix, clear suffix, Esc-clears — but deliberately
/// **without** that field's 命中/總數 readout. Under rule 6 the hit count
/// belongs in the panel's status bar, and one number written in two places
/// is two things that can disagree.
///
/// Presentational: it owns no query state. The panel holds the query, so the
/// same filter survives a rebuild and the status bar can count against it.
class PanelFilterField extends StatefulWidget {
  const PanelFilterField({
    super.key,
    required this.query,
    required this.onChanged,
    this.hintText = 'Filter',
    this.disabledReason = '',
  });

  final String query;

  /// Null disables the field. See [disabledReason] for when that is right.
  final ValueChanged<String>? onChanged;

  final String hintText;

  /// Why this panel's list cannot be filtered, shown as a tooltip.
  ///
  /// Rule 2 says the filter is 固定 at the right end, so it is drawn for
  /// every panel — but two of the twelve have nothing to filter:
  ///
  /// - `blame`, whose list really is *file content* rather than a named
  ///   collection, so there is no name a filter could match; and
  /// - `interactive-rebase`, which has rule 3's writable list, where a
  ///   filtered order is not the real order and a drag would reorder
  ///   against commits the user cannot see.
  ///
  /// **Two panels were listed here and turned out not to belong** — both
  /// corrected in place rather than quietly dropped, per
  /// [CULT-scrutinise-the-comment], because a wrong reason left standing is
  /// what makes the next round repeat it:
  ///
  /// - `bisect` was grouped with `interactive-rebase` as a writable list.
  ///   It is not: marking happens on the toolbar and the list only
  ///   *records* (待裁定 6), so a filtered view reorders nothing. Its filter
  ///   is live while a bisect runs and disabled only when one is not,
  ///   because then the list is a start form with nothing in it.
  /// - `line-history` was grouped with `blame` as file content. It is not:
  ///   a `LineHistoryChunk` carries `oid`, `author` and `subject`, and its
  ///   row draws a subject over an author and a date — `file-history`'s
  ///   shape. Its filter is live.
  ///
  /// Disabled with a stated reason rather than hidden —
  /// 隱藏會讓人以為功能不存在 ([FLU-menu-enabled-is-visual-only]) — and the
  /// reason has to be reachable, which is why it is a tooltip and not a
  /// comment.
  final String disabledReason;

  bool get enabled => onChanged != null;

  @override
  State<PanelFilterField> createState() => _PanelFilterFieldState();
}

class _PanelFilterFieldState extends State<PanelFilterField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.query,
  );

  static const BoxConstraints _iconSlot = BoxConstraints(
    minWidth: 28,
    minHeight: 28,
  );

  @override
  void didUpdateWidget(PanelFilterField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The panel owns the query, so a programmatic clear (Esc elsewhere, a
    // tab reset) has to reach the field. Guarded, or every keystroke would
    // fight the caret.
    if (widget.query != _controller.text) {
      _controller.text = widget.query;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    widget.onChanged?.call('');
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    OutlineInputBorder border(Color c) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: BorderSide(color: c),
    );

    final Widget field = SizedBox(
      width: 200,
      height: 28,
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.escape): _clear,
        },
        child: TextField(
          controller: _controller,
          enabled: widget.enabled,
          style: TextStyle(
            fontSize: GbmTypography.textSm,
            color: colors.textPrimary,
          ),
          onChanged: widget.onChanged,
          decoration: InputDecoration(
            isDense: true,
            hintText: widget.hintText,
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
            suffixIcon: _controller.text.isEmpty || !widget.enabled
                ? null
                : IconButton(
                    icon: Icon(
                      Icons.close,
                      size: 14,
                      color: colors.textTertiary,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: _iconSlot,
                    onPressed: _clear,
                  ),
            contentPadding: const EdgeInsets.symmetric(
              vertical: GbmSpacing.space1,
            ),
            filled: true,
            fillColor: colors.surfaceSunken,
            border: border(colors.borderSubtle),
            enabledBorder: border(colors.borderSubtle),
            focusedBorder: border(colors.borderFocus),
            disabledBorder: border(colors.borderSubtle),
          ),
        ),
      ),
    );

    if (widget.enabled) return field;
    return Tooltip(message: widget.disabledReason, child: field);
  }
}
