import 'package:flutter/material.dart';

import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';

/// Prompts for both a name and a URL at once -- unlike every other
/// branch/tag rename/create flow, adding a remote genuinely needs two
/// values, so this doesn't fit `promptText`'s single-field shape. Returns
/// null if cancelled, or if either field is left empty.
///
/// Moved here verbatim from the deleted `manage_remotes_dialog.dart` when
/// that panel became a tab: the panel's `Add…` needs exactly this prompt,
/// and rewriting it would have been a behaviour change smuggled into a
/// carrier change.
Future<({String name, String url})?> promptAddRemote(BuildContext context) {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController urlController = TextEditingController();
  return showDialog<({String name, String url})>(
    context: context,
    builder: (dialogContext) {
      final GbmColors colors = dialogContext.gbmColors;
      ({String name, String url})? resultFromControllers() {
        final String name = nameController.text.trim();
        final String url = urlController.text.trim();
        return name.isEmpty || url.isEmpty ? null : (name: name, url: url);
      }

      // Only pops on a valid result -- leaving the dialog open (with
      // whatever the user already typed still in place) is the signal
      // that a required field is missing, rather than silently discarding
      // the input by closing anyway.
      void submitIfValid() {
        final ({String name, String url})? result = resultFromControllers();
        if (result != null) {
          Navigator.of(dialogContext).pop(result);
        }
      }

      return AlertDialog(
        title: const Text('Add remote'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Name',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: GbmSpacing.space2),
            TextField(
              controller: urlController,
              decoration: const InputDecoration(
                labelText: 'URL',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => submitIfValid(),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(color: colors.textSecondary),
            ),
          ),
          TextButton(onPressed: submitIfValid, child: const Text('Add')),
        ],
      );
    },
  );
}
