import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/graph_columns_repository.dart';

/// UI to toggle column visibility for the graph display.
/// Converts to ConsumerStatefulWidget with local state to fix reactivity bug:
/// previous implementation read visibility once and persisted changes to
/// SharedPreferences but never rebuilt to show the updated local state.
class GraphColumnsSelector extends ConsumerStatefulWidget {
  const GraphColumnsSelector({super.key});

  @override
  ConsumerState<GraphColumnsSelector> createState() =>
      _GraphColumnsSelectorState();
}

class _GraphColumnsSelectorState extends ConsumerState<GraphColumnsSelector> {
  late Map<String, bool> _visibility;

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
  void initState() {
    super.initState();
    final repo = ref.read(graphColumnsRepositoryProvider);
    _visibility = repo.readVisibility();
  }

  @override
  Widget build(BuildContext context) {
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
          final isVisible = _visibility[colId] ?? true;
          final isLocked = colId == 'graph' || colId == 'message';

          return CheckboxListTile(
            title: Text(label),
            value: isVisible,
            enabled: !isLocked,
            onChanged: isLocked
                ? null
                : (value) {
                    setState(() {
                      _visibility[colId] = value ?? false;
                    });
                    final repo = ref.read(graphColumnsRepositoryProvider);
                    unawaited(repo.writeVisibility(_visibility));
                  },
          );
        },
      ),
    );
  }
}
