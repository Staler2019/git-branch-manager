import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/file_list_view_mode_repository.dart';

/// A toggle button to switch between list and tree view modes for file displays.
///
/// This is a presentational widget that displays the current mode and allows
/// the user to toggle between list and tree modes. The actual mode state is
/// managed by the [fileListViewModeProvider] and persisted via
/// [FileListViewModeRepository].
///
/// The button shows different icons for each mode:
/// - List mode: view list icon
/// - Tree mode: folder tree icon
class FileListModeToggleButton extends ConsumerWidget {
  const FileListModeToggleButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMode = ref.watch(fileListViewModeProvider);

    return IconButton(
      icon: Icon(
        currentMode == FileListViewMode.list ? Icons.list : Icons.folder,
      ),
      tooltip: currentMode == FileListViewMode.list
          ? 'Switch to tree view'
          : 'Switch to list view',
      onPressed: () async {
        final newMode = currentMode == FileListViewMode.list
            ? FileListViewMode.tree
            : FileListViewMode.list;
        await ref.read(fileListViewModeProvider.notifier).setMode(newMode);
      },
    );
  }
}
