import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/file_list_view_mode_repository.dart';
import 'gbm_segmented_control.dart';

/// Spec P03-10's 「一組兩鍵切換」: a two-key segmented control at the right of
/// a file list's header, one key per [FileListViewMode], the active one filled
/// with the accent colour (spec page 03's mockup draws exactly this).
///
/// **Two keys, not one toggling button.** It used to be a single [IconButton]
/// whose icon changed to whatever mode you were *not* in, which meant the
/// control's own appearance was the only clue to the current state and it
/// showed the opposite of it. With two keys the current mode is the lit one
/// and the other key says where tapping goes -- and tapping the key you are
/// already on is a no-op instead of a surprise.
///
/// The mode itself is global ([fileListViewModeProvider], persisted by
/// [FileListViewModeRepository]) and shared by Working Copy, History's Changed
/// files, Compare's Files and the Conflict window's file rail, so every
/// instance of this control shows and changes the same thing.
class FileListModeToggleButton extends ConsumerWidget {
  const FileListModeToggleButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GbmSegmentedControl<FileListViewMode>(
      value: ref.watch(fileListViewModeProvider),
      onChanged: (FileListViewMode mode) =>
          ref.read(fileListViewModeProvider.notifier).setMode(mode),
      options: const <GbmSegmentedOption<FileListViewMode>>[
        GbmSegmentedOption<FileListViewMode>(
          value: FileListViewMode.list,
          label: 'Flat list',
          icon: Icons.list,
        ),
        GbmSegmentedOption<FileListViewMode>(
          value: FileListViewMode.tree,
          label: 'Folder tree',
          icon: Icons.account_tree,
        ),
      ],
    );
  }
}
