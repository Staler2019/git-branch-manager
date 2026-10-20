// P15 A #5: 「狀態列寫出實際掃描結果與耗時，不寫「準備就緒」這種沒有資訊的字」.
// The duration is core's own per-folder `last_scan_ms`, summed over the
// enabled folders -- the figure Preferences' summary is read from too.
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/base_folder_record.dart';
import 'package:gbm_flutter/data/models/repo_record.dart';
import 'package:gbm_flutter/data/repositories/discovery_repository.dart';
import 'package:gbm_flutter/features/welcome/scan_summary.dart';

BaseFolderRecord _folder(int id, {int scanMs = 0, bool enabled = true}) =>
    BaseFolderRecord(
      id: id,
      path: '/src/$id',
      enabled: enabled,
      maxDepth: 3,
      followLinks: false,
      lastScanStarted: 0,
      lastScanFinished: 0,
      lastScanDirs: 0,
      lastScanMs: scanMs,
      lastScanSkipped: 0,
    );

RepoRecord _repo(int id) => RepoRecord(
  id: id,
  baseFolderId: 1,
  workDir: '/src/r$id',
  gitDir: '/src/r$id/.git',
  commonDir: '/src/r$id/.git',
  kind: RepoKind.normal,
  name: 'r$id',
  parentRepoId: null,
  depth: 0,
  discoveredAt: 0,
  missingSince: null,
);

void main() {
  test('states folders, repositories and the summed scan time', () {
    final DiscoveryState state = DiscoveryState(
      baseFolders: <BaseFolderRecord>[
        _folder(1, scanMs: 200),
        _folder(2, scanMs: 100),
        _folder(3, scanMs: 31),
        _folder(4, scanMs: 999, enabled: false),
      ],
      repos: <RepoRecord>[for (int i = 0; i < 41; i++) _repo(i)],
    );
    expect(
      scanSummaryLabel(state),
      '掃描 3 個來源資料夾 · 找到 41 個 repository · 331 ms',
    );
  });

  test('before any scan has finished, no duration is claimed', () {
    final DiscoveryState state = DiscoveryState(
      baseFolders: <BaseFolderRecord>[_folder(1), _folder(2)],
    );
    expect(scanSummaryLabel(state), '2 個來源資料夾 · 找到 0 個 repository');
  });

  test('while scanning', () {
    final DiscoveryState state = DiscoveryState(
      baseFolders: <BaseFolderRecord>[_folder(1, scanMs: 5), _folder(2)],
      isScanning: true,
    );
    expect(scanSummaryLabel(state), '正在掃描 2 個來源資料夾…');
  });

  test('with no source folder at all', () {
    expect(scanSummaryLabel(const DiscoveryState()), '還沒有來源資料夾');
  });
}
