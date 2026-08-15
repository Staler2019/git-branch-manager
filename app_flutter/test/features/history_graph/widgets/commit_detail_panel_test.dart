import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/commit_meta.dart';
import 'package:gbm_flutter/data/models/parsed_diff.dart';
import 'package:gbm_flutter/data/models/signature.dart';
import 'package:gbm_flutter/features/history_graph/widgets/commit_detail_panel.dart';

import '../../../support/pump_app.dart';

const CommitMeta _meta = CommitMeta(
  oid: 'abc123',
  tree: 'tree1',
  parents: <String>['parent1'],
  author: Signature(
    name: 'Alice',
    email: 'alice@example.com',
    when: 0,
    tzOffsetMinutes: 0,
  ),
  committer: Signature(
    name: 'Alice',
    email: 'alice@example.com',
    when: 0,
    tzOffsetMinutes: 0,
  ),
  subject: 'Fix the thing',
  body: 'Full description body.',
  signedCommit: false,
);

void main() {
  testWidgets('prompts to select a commit when nothing is selected', (
    tester,
  ) async {
    await pumpGbmWidget(
      tester,
      child: const CommitDetailPanelCore(
        selectedFilePath: null,
        hasSelectedCommit: false,
        meta: null,
        diff: null,
      ),
    );

    expect(find.text('Select a commit to view details'), findsOneWidget);
  });

  testWidgets('shows a spinner while a selected commit\'s meta is loading', (
    tester,
  ) async {
    await pumpGbmWidget(
      tester,
      child: const CommitDetailPanelCore(
        selectedFilePath: null,
        hasSelectedCommit: true,
        meta: null,
        diff: null,
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows commit subject and body once meta has loaded', (
    tester,
  ) async {
    await pumpGbmWidget(
      tester,
      child: const CommitDetailPanelCore(
        selectedFilePath: null,
        hasSelectedCommit: true,
        meta: _meta,
        diff: null,
      ),
    );

    expect(find.text('Fix the thing'), findsOneWidget);
    expect(find.text('Full description body.'), findsOneWidget);
  });

  testWidgets(
    'shows a spinner instead of metadata once a file is selected but its '
    'diff has not arrived yet',
    (tester) async {
      await pumpGbmWidget(
        tester,
        child: const CommitDetailPanelCore(
          selectedFilePath: 'a.dart',
          hasSelectedCommit: true,
          meta: _meta,
          diff: null,
        ),
      );

      expect(find.text('Fix the thing'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    },
  );

  testWidgets(
    'shows the file diff instead of metadata once a file is selected and '
    'its diff has arrived -- mutually exclusive with the metadata view',
    (tester) async {
      await pumpGbmWidget(
        tester,
        child: const CommitDetailPanelCore(
          selectedFilePath: 'a.dart',
          hasSelectedCommit: true,
          meta: _meta,
          diff: ParsedDiff.empty,
        ),
      );

      expect(find.text('Fix the thing'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );
}
