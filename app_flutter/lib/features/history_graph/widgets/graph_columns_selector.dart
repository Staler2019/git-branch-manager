import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/graph_columns_repository.dart';

/// Spec page 02 item 16's column picker.
///
/// State lives in [graphColumnVisibilityProvider], not in this widget. An
/// earlier version kept it in local `State` and wrote through to
/// SharedPreferences: that fixed the checkbox not reflecting its own taps,
/// but left the setting invisible to the commit list, which never read it
/// back. Sitting both on one notifier is what makes a toggle reach the rows.
class GraphColumnsSelector extends ConsumerWidget {
  const GraphColumnsSelector({super.key});

  /// Map of internal column ids to display labels (Title Case).
  static const Map<String, String> _columnLabels = <String, String>{
    'graph': 'Graph',
    'message': 'Message',
    'refs': 'Refs',
    'author': 'Author',
    'date': 'Date',
    'hash': 'Hash',
    'committer': 'Committer',
    'changedFiles': 'Changed Files',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Map<String, bool> visibility = ref.watch(
      graphColumnVisibilityProvider,
    );
    final columnIds = _columnLabels.keys.toList();

    return SizedBox(
      width: 220,
      height: columnIds.length * 56.0,
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: columnIds.length,
        itemBuilder: (context, index) {
          final colId = columnIds[index];
          final label = _columnLabels[colId] ?? colId;
          final isVisible = isGraphColumnVisible(visibility, colId);
          final isLocked = kLockedGraphColumnIds.contains(colId);

          return CheckboxListTile(
            title: Text(label),
            value: isVisible,
            enabled: !isLocked,
            onChanged: isLocked
                ? null
                : (value) => ref
                      .read(graphColumnVisibilityProvider.notifier)
                      .setVisible(colId, value ?? false),
          );
        },
      ),
    );
  }
}
