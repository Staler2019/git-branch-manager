import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';

/// A presentational widget for commit message input (summary + description).
/// Renders two text fields:
/// - Summary (single line): char count warning at 50+ chars
/// - Description (multi-line): monospace font with 72-char ruler overlay
///
/// Tab key moves focus from summary to description.
/// No Riverpod dependencies; pure input/callback based.
class CommitMessageBox extends StatefulWidget {
  const CommitMessageBox({
    super.key,
    required this.summaryController,
    required this.descriptionController,
    required this.onSummaryChanged,
    required this.onDescriptionChanged,
  });

  final TextEditingController summaryController;
  final TextEditingController descriptionController;
  final ValueChanged<String> onSummaryChanged;
  final ValueChanged<String> onDescriptionChanged;

  @override
  State<CommitMessageBox> createState() => _CommitMessageBoxState();
}

class _CommitMessageBoxState extends State<CommitMessageBox> {
  late FocusNode _summaryFocus;
  late FocusNode _descriptionFocus;

  @override
  void initState() {
    super.initState();
    _summaryFocus = FocusNode();
    _descriptionFocus = FocusNode();

    widget.summaryController.addListener(() {
      widget.onSummaryChanged(widget.summaryController.text);
      setState(() {});
    });

    widget.descriptionController.addListener(() {
      widget.onDescriptionChanged(widget.descriptionController.text);
    });
  }

  @override
  void dispose() {
    _summaryFocus.dispose();
    _descriptionFocus.dispose();
    super.dispose();
  }

  void _onSummaryKey(KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      _descriptionFocus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final bool summaryOverLimit = widget.summaryController.text.length > 50;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // Summary field with char count warning
        Padding(
          padding: const EdgeInsets.only(bottom: GbmSpacing.space2),
          child: _SummaryField(
            controller: widget.summaryController,
            focusNode: _summaryFocus,
            onKeyEvent: _onSummaryKey,
            overLimit: summaryOverLimit,
            colors: colors,
          ),
        ),

        // Description field with 72-char ruler
        Expanded(
          child: _DescriptionField(
            controller: widget.descriptionController,
            focusNode: _descriptionFocus,
            colors: colors,
          ),
        ),
      ],
    );
  }
}

/// Single-line summary input field.
/// Shows warning color hint when text exceeds 50 characters.
class _SummaryField extends StatelessWidget {
  const _SummaryField({
    required this.controller,
    required this.focusNode,
    required this.onKeyEvent,
    required this.overLimit,
    required this.colors,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final Function(KeyEvent) onKeyEvent;
  final bool overLimit;
  final GbmColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Focus(
          onKeyEvent: (node, event) {
            if (event.logicalKey == LogicalKeyboardKey.tab) {
              onKeyEvent(event);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            maxLines: 1,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              hintText: 'Commit summary',
              isDense: true,
              border: OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: GbmSpacing.space2,
                vertical: GbmSpacing.space1,
              ),
            ),
          ),
        ),
        // Char count indicator when over 50 chars
        if (overLimit)
          Padding(
            padding: const EdgeInsets.only(
              top: GbmSpacing.space1,
              right: GbmSpacing.space1,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                Text(
                  '${controller.text.length} chars',
                  style: TextStyle(
                    fontSize: GbmTypography.textXs,
                    color: colors.warning,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Multi-line description field with monospace font and 72-char ruler overlay.
class _DescriptionField extends StatelessWidget {
  const _DescriptionField({
    required this.controller,
    required this.focusNode,
    required this.colors,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final GbmColors colors;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        TextField(
          controller: controller,
          focusNode: focusNode,
          maxLines: null,
          expands: true,
          style: TextStyle(
            fontFamily: GbmTypography.fontMono,
            fontSize: GbmTypography.textBase,
          ),
          decoration: InputDecoration(
            hintText: 'Commit description (optional)',
            isDense: true,
            border: OutlineInputBorder(),
            contentPadding: const EdgeInsets.all(GbmSpacing.space2),
          ),
        ),
        // 72-char ruler overlay
        Positioned(
          left: _calculateRulerPosition(),
          top: 0,
          bottom: 0,
          child: Container(width: 1, color: colors.borderSubtle),
        ),
        // 72-char ruler label (subtle, positioned at top-right)
        Positioned(
          right: GbmSpacing.space2,
          top: GbmSpacing.space2,
          child: Text(
            '72',
            style: TextStyle(
              fontSize: GbmTypography.textXs,
              color: colors.textTertiary.withValues(alpha: 0.5),
            ),
          ),
        ),
      ],
    );
  }

  /// Calculate the left offset for the 72-char ruler based on monospace font.
  /// Approximation: each char in monospace is roughly 8px at base font size.
  double _calculateRulerPosition() {
    const double charWidth = 8.0;
    const int rulerCharPosition = 72;
    const double leftPadding = GbmSpacing.space2;
    return leftPadding + (rulerCharPosition * charWidth);
  }
}
