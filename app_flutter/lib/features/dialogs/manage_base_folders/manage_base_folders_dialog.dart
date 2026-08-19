import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/base_folder_record.dart';
import '../../../data/repositories/discovery_repository.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_dialog_shell.dart';

/// The Dart analog of `ManageBaseFoldersDialog`
/// (src/app/dialogs/ManageBaseFoldersDialog.cpp). Routed as
/// `/dialogs/manage-base-folders`. A compact enable/disable/remove view of
/// the same base folders Preferences → Repository sources holds (spec page
/// 11 item 2), which is also where a folder is added -- this dialog has no
/// add field of its own.
class ManageBaseFoldersDialogContent extends ConsumerWidget {
  const ManageBaseFoldersDialogContent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DiscoveryState discovery = ref.watch(discoveryProvider);
    final GbmColors colors = context.gbmColors;

    return GbmDialogShell(
      title: 'Base Folders',
      child: discovery.baseFolders.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: GbmSpacing.space4),
              child: Text(
                'No base folders yet.',
                style: TextStyle(color: colors.textTertiary),
              ),
            )
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (final folder in discovery.baseFolders)
                    _BaseFolderRow(folder: folder),
                  const SizedBox(height: GbmSpacing.space2),
                ],
              ),
            ),
    );
  }
}

class _BaseFolderRow extends ConsumerWidget {
  const _BaseFolderRow({required this.folder});

  final BaseFolderRecord folder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GbmColors colors = context.gbmColors;
    // Same pure local filesystem check as preferences_dialog.dart's
    // _BaseFolderRow -- see that copy's doc comment. A visual marker only;
    // the folder's settings are kept and enable/remove still work normally.
    final bool isOffline = !Directory(folder.path).existsSync();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: GbmSpacing.space1),
      child: Row(
        children: <Widget>[
          Checkbox(
            value: folder.enabled,
            onChanged: (value) => ref
                .read(discoveryProvider.notifier)
                .setBaseFolderEnabled(folder.id, value ?? true),
            visualDensity: VisualDensity.compact,
          ),
          if (isOffline) ...<Widget>[
            Tooltip(
              message:
                  'This folder is not reachable right now — its settings '
                  'are kept.',
              child: Icon(
                Icons.warning_amber_rounded,
                size: 16,
                color: colors.warning,
              ),
            ),
            const SizedBox(width: GbmSpacing.space1),
          ],
          Expanded(
            child: Text(
              folder.path,
              style: TextStyle(
                fontSize: GbmTypography.textSm,
                color: colors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, size: 18, color: colors.danger),
            tooltip: 'Remove',
            onPressed: () => ref
                .read(discoveryProvider.notifier)
                .removeBaseFolder(folder.id),
          ),
        ],
      ),
    );
  }
}
