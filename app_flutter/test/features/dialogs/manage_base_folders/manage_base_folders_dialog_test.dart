// Covers the offline marker added alongside preferences_dialog_test.dart's
// copy of the same behaviour -- see that file's header comment for the
// broader 0g context. This dialog otherwise only exercises the pre-existing
// enable/remove wiring, which had no prior test file either.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/base_folder_record.dart';
import 'package:gbm_flutter/data/models/repo_record.dart';
import 'package:gbm_flutter/data/repositories/discovery_repository.dart';
import 'package:gbm_flutter/features/dialogs/manage_base_folders/manage_base_folders_dialog.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';

BaseFolderRecord _folder({required int id, required String path}) =>
    BaseFolderRecord(
      id: id,
      path: path,
      enabled: true,
      maxDepth: 3,
      followLinks: false,
      lastScanStarted: 0,
      lastScanFinished: 0,
      lastScanDirs: 0,
      lastScanMs: 0,
      lastScanSkipped: 0,
    );

class _TestDiscoveryController extends StateNotifier<DiscoveryState>
    implements DiscoveryController {
  _TestDiscoveryController(List<BaseFolderRecord> folders)
    : super(DiscoveryState(baseFolders: folders, repos: const <RepoRecord>[]));

  @override
  void addBaseFolderAndScan(String path) {}

  @override
  void removeBaseFolder(int baseFolderId) {}

  @override
  void rescan() {}

  @override
  void setBaseFolderEnabled(int baseFolderId, bool enabled) {}

  @override
  void setBaseFolderDepth(int baseFolderId, int maxDepth) {}
}

Future<void> _pump(WidgetTester tester, List<BaseFolderRecord> folders) async {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      discoveryProvider.overrideWith(
        (ref) => _TestDiscoveryController(folders),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
        home: const Scaffold(body: ManageBaseFoldersDialogContent()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('ManageBaseFoldersDialogContent', () {
    testWidgets('a base folder that no longer exists on disk shows a warning', (
      tester,
    ) async {
      await _pump(tester, <BaseFolderRecord>[
        _folder(id: 1, path: '/definitely/does/not/exist/gbm-test-xyz'),
      ]);

      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('a base folder that exists on disk shows no warning', (
      tester,
    ) async {
      final Directory realDir = Directory.systemTemp.createTempSync(
        'gbm-manage-folders-test-',
      );
      addTearDown(() => realDir.deleteSync(recursive: true));

      await _pump(tester, <BaseFolderRecord>[
        _folder(id: 1, path: realDir.path),
      ]);

      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
    });
  });
}
