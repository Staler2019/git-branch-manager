import '../../data/models/base_folder_record.dart';
import '../../data/repositories/discovery_repository.dart';

/// The no-repository window's status-bar sentence (spec page 15 A #5:
/// 「狀態列寫出實際掃描結果與耗時，不寫「準備就緒」這種沒有資訊的字」).
///
/// The duration is core's own `last_scan_ms`, summed over the enabled
/// folders: `gbm_discovery_scan_all()` scans them one after another, and the
/// figure survives a restart. It is the same per-folder record Preferences'
/// summary reads, so the two cannot disagree. A folder never scanned
/// contributes 0, and when nothing has been scanned yet no duration is
/// written rather than a made-up 0 ms.
String scanSummaryLabel(DiscoveryState discovery) {
  final List<BaseFolderRecord> enabled = discovery.baseFolders
      .where((BaseFolderRecord f) => f.enabled)
      .toList(growable: false);
  if (enabled.isEmpty) return '還沒有來源資料夾';
  if (discovery.isScanning) return '正在掃描 ${enabled.length} 個來源資料夾…';
  final int totalMs = enabled.fold<int>(
    0,
    (int acc, BaseFolderRecord f) => acc + f.lastScanMs,
  );
  final String found = '找到 ${discovery.repos.length} 個 repository';
  if (totalMs == 0) return '${enabled.length} 個來源資料夾 · $found';
  return '掃描 ${enabled.length} 個來源資料夾 · $found · $totalMs ms';
}
