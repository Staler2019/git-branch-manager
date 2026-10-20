import 'package:flutter/foundation.dart' show immutable;

import 'clone_events.dart';

/// One clone running in the background (P15 B: 「只是通知結果的留在 log
/// 抽屜與狀態列」). What the status bar's task row and the credential
/// listener read; the native handle stays in `CloneJobController`.
@immutable
class CloneJob {
  const CloneJob({
    required this.id,
    required this.url,
    required this.destPath,
    this.progress,
    this.credentialPrompt,
  });

  final int id;

  /// As typed. Never drawn: the task row names [destPath]'s folder, and
  /// the Log shows the masked argv (R6).
  final String url;
  final String destPath;

  /// The last `GBM_EVENT_CLONE_PROGRESS`, or null before the first.
  final CloneProgress? progress;

  /// git is waiting on the user for this, or null.
  final String? credentialPrompt;

  /// The destination's folder name -- `Cloning design-tokens`.
  String get name {
    final String trimmed = destPath.replaceAll(RegExp(r'[/\\]+$'), '');
    final int cut = trimmed.lastIndexOf(RegExp(r'[/\\]'));
    return cut < 0 ? trimmed : trimmed.substring(cut + 1);
  }

  CloneJob withProgress(CloneProgress progress) => CloneJob(
    id: id,
    url: url,
    destPath: destPath,
    progress: progress,
    credentialPrompt: credentialPrompt,
  );

  CloneJob withCredentialPrompt(String? prompt) => CloneJob(
    id: id,
    url: url,
    destPath: destPath,
    progress: progress,
    credentialPrompt: prompt,
  );
}
