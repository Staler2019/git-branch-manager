import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/file_list_view_mode_repository.dart';
import '../theme/gbm_theme.dart';
import '../theme/tokens.dart';

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
    final FileListViewMode current = ref.watch(fileListViewModeProvider);
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
          _ModeKey(
            icon: Icons.list,
            label: 'Flat list',
            mode: FileListViewMode.list,
            current: current,
          ),
          const SizedBox(width: 2),
          _ModeKey(
            icon: Icons.account_tree,
            label: 'Folder tree',
            mode: FileListViewMode.tree,
            current: current,
          ),
        ],
      ),
    );
  }
}

/// One key of the segmented control. Sized to fit inside a
/// [GbmSpacing.rowHeightCompact] header row, which a default [IconButton]
/// (48x48 before its constraints are overridden) cannot do.
class _ModeKey extends ConsumerWidget {
  const _ModeKey({
    required this.icon,
    required this.label,
    required this.mode,
    required this.current,
  });

  final IconData icon;
  final String label;
  final FileListViewMode mode;
  final FileListViewMode current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GbmColors colors = context.gbmColors;
    final bool active = mode == current;

    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: Tooltip(
        message: label,
        child: InkWell(
          onTap: active
              ? null
              : () => ref.read(fileListViewModeProvider.notifier).setMode(mode),
          borderRadius: BorderRadius.circular(2),
          hoverColor: colors.surfaceHover,
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: active ? colors.accent : null,
              borderRadius: BorderRadius.circular(2),
            ),
            child: Icon(
              icon,
              size: 14,
              color: active ? colors.textOnAccent : colors.textTertiary,
            ),
          ),
        ),
      ),
    );
  }
}
