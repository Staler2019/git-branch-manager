import 'package:flutter/material.dart';

import '../theme/gbm_theme.dart';
import '../theme/tokens.dart';

/// One key of a [GbmSegmentedControl].
///
/// [label] is always the tooltip and the accessibility label; [showLabel]
/// decides whether it is also painted. An icon-only key still announces
/// itself, which is why the label is required rather than optional.
class GbmSegmentedOption<T> {
  const GbmSegmentedOption({
    required this.value,
    required this.label,
    this.icon,
    this.showLabel = false,
  });

  final T value;
  final String label;
  final IconData? icon;
  final bool showLabel;
}

/// The spec's 「一組 N 鍵切換」: a bordered strip of keys where the current
/// value is the filled one and every other key says where tapping goes.
///
/// Two surfaces draw this shape -- the file-list list/tree switch (P03-10)
/// and the diff pane's `2 file` / `unified` switch (P03's 變體 B titlebar) --
/// so it lives here rather than being hand-rolled twice. The alternative,
/// [SegmentedButton], is Material 3's own and sizes itself for a touch
/// target: it cannot fit the [GbmSpacing.rowHeightCompact] header rows both
/// call sites put it in.
///
/// Tapping the key you are already on is a no-op, not a re-emit: these
/// switches sit next to lists that rebuild on change, and re-selecting the
/// current value would throw that work away for nothing.
class GbmSegmentedControl<T> extends StatelessWidget {
  const GbmSegmentedControl({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final List<GbmSegmentedOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;

    return Container(
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        border: Border.all(color: colors.borderDefault),
        borderRadius: BorderRadius.circular(GbmSpacing.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (int i = 0; i < options.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: 2),
            _SegmentKey<T>(
              option: options[i],
              active: options[i].value == value,
              onTap: () => onChanged(options[i].value),
            ),
          ],
        ],
      ),
    );
  }
}

class _SegmentKey<T> extends StatelessWidget {
  const _SegmentKey({
    required this.option,
    required this.active,
    required this.onTap,
  });

  final GbmSegmentedOption<T> option;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final Color foreground = active ? colors.textOnAccent : colors.textTertiary;

    return Semantics(
      button: true,
      selected: active,
      label: option.label,
      child: Tooltip(
        message: option.label,
        child: InkWell(
          onTap: active ? null : onTap,
          borderRadius: BorderRadius.circular(2),
          hoverColor: colors.surfaceHover,
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: option.showLabel ? 6 : 2,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: active ? colors.accent : null,
              borderRadius: BorderRadius.circular(2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (option.icon != null)
                  Icon(option.icon, size: 14, color: foreground),
                if (option.icon != null && option.showLabel)
                  const SizedBox(width: 4),
                if (option.showLabel)
                  Text(
                    option.label,
                    style: TextStyle(
                      fontSize: GbmTypography.textXs,
                      color: foreground,
                      fontWeight: active ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
