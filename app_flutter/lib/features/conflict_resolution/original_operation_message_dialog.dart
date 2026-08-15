import 'package:flutter/material.dart';

import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';

/// Splits a raw MERGE_MSG/rebase-merge/message body into the summary (first
/// line) and description (remaining lines, minus the single blank
/// separator line git itself inserts) -- the same split the MSGS table
/// describes as "預設 summary"/"預設 description".
({String summary, String description}) splitOriginalOperationMessage(
  String message,
) {
  final List<String> lines = message.split('\n');
  if (lines.isEmpty) return (summary: '', description: '');
  final String summary = lines.first;
  List<String> rest = lines.skip(1).toList();
  if (rest.isNotEmpty && rest.first.isEmpty) rest = rest.skip(1).toList();
  return (summary: summary, description: rest.join('\n'));
}

/// A [TextEditingController] that renders `#`-prefixed lines in
/// [GbmColors.textTertiary] -- git's own conflicted-file comment block,
/// which git strips from the final commit message on its own regardless of
/// what's submitted (confirmed empirically against a real conflicted
/// cherry-pick continue), so this dialog only needs to grey the lines, not
/// strip them before submit.
class _CommentAwareController extends TextEditingController {
  _CommentAwareController({super.text});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final Color commentColor = context.gbmColors.textTertiary;
    final List<String> lines = text.split('\n');
    final List<TextSpan> spans = <TextSpan>[];
    for (int i = 0; i < lines.length; i++) {
      spans.add(
        TextSpan(
          text: lines[i],
          style: lines[i].startsWith('#')
              ? style?.copyWith(color: commentColor)
              : style,
        ),
      );
      if (i != lines.length - 1) spans.add(TextSpan(text: '\n', style: style));
    }
    return TextSpan(style: style, children: spans);
  }
}

/// The MSGS-table commit-message step shown before Continue actually fires
/// during a conflicted cherry-pick/rebase -- see spec P8 and this repo's
/// CLAUDE.md "MSGS 表". Prefills summary/description from git's own
/// proposed message (already fetched via
/// [RepoSessionController.requestOriginalOperationMessage] into
/// `initialMessage`); an empty summary disables the submit button, matching
/// git's own refusal to commit with a blank subject. Plain `showDialog`
/// like `promptText` in prompt_text_dialog.dart -- nothing here worth
/// deep-linking to, unlike the routed `/dialogs/*` catalog. Returns the
/// assembled message ready for
/// cherryPickContinueWithMessage/continueRebaseWithMessage, or null if
/// cancelled.
Future<String?> promptOriginalOperationMessage(
  BuildContext context, {
  required String title,
  required String initialMessage,
}) {
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => _OriginalOperationMessageDialog(
      title: title,
      initialMessage: initialMessage,
    ),
  );
}

/// Owns its own controllers so disposal follows the normal [State.dispose]
/// lifecycle -- disposing them manually off a `showDialog` future's
/// completion races the dialog's exit transition (the TextField widgets are
/// still mounted, fading out, when that future resolves) and throws "A
/// TextEditingController was used after being disposed."
class _OriginalOperationMessageDialog extends StatefulWidget {
  const _OriginalOperationMessageDialog({
    required this.title,
    required this.initialMessage,
  });

  final String title;
  final String initialMessage;

  @override
  State<_OriginalOperationMessageDialog> createState() =>
      _OriginalOperationMessageDialogState();
}

class _OriginalOperationMessageDialogState
    extends State<_OriginalOperationMessageDialog> {
  late final TextEditingController _summaryController;
  late final _CommentAwareController _descriptionController;

  @override
  void initState() {
    super.initState();
    final split = splitOriginalOperationMessage(widget.initialMessage);
    _summaryController = TextEditingController(text: split.summary)
      ..addListener(_onSummaryChanged);
    _descriptionController = _CommentAwareController(text: split.description);
  }

  @override
  void dispose() {
    _summaryController.removeListener(_onSummaryChanged);
    _summaryController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _onSummaryChanged() => setState(() {});

  void _submit() {
    final String summary = _summaryController.text.trim();
    if (summary.isEmpty) return;
    final String description = _descriptionController.text;
    Navigator.of(
      context,
    ).pop(description.isEmpty ? summary : '$summary\n\n$description');
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final bool canSubmit = _summaryController.text.trim().isNotEmpty;

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: _summaryController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Summary',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: GbmSpacing.space3),
            TextField(
              controller: _descriptionController,
              minLines: 4,
              maxLines: 12,
              decoration: const InputDecoration(
                labelText: 'Description',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: GbmSpacing.space2),
            Text(
              'Lines starting with # are removed by git on submit.',
              style: TextStyle(
                fontSize: GbmTypography.textXs,
                color: colors.textTertiary,
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
        ),
        TextButton(
          onPressed: canSubmit ? _submit : null,
          child: const Text('Continue'),
        ),
      ],
    );
  }
}
