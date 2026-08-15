import 'package:flutter/material.dart';

import '../theme/gbm_theme.dart';
import '../theme/tokens.dart';

/// A single-line text prompt: the Dart analog of Qt's `dialogs::promptText`
/// (src/app/dialogs/CommonDialogs.h), used for the handful of branch/tag
/// actions that only need one value from the user (new branch name, rename
/// target) rather than a full dialog-route screen. Unlike the `/dialogs/`
/// routes this is a plain `showDialog` -- there is nothing here worth
/// deep-linking to. Returns the trimmed text, or null if cancelled or left
/// empty.
Future<String?> promptText(
  BuildContext context, {
  required String title,
  required String label,
  String initialValue = '',
}) {
  final TextEditingController controller = TextEditingController(
    text: initialValue,
  );
  return showDialog<String>(
    context: context,
    builder: (dialogContext) {
      final GbmColors colors = dialogContext.gbmColors;
      return AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value.trim()),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(color: colors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('OK'),
          ),
        ],
      );
    },
  ).then((value) => value == null || value.isEmpty ? null : value);
}
