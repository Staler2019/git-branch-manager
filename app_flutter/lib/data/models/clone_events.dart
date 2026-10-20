import 'package:flutter/foundation.dart';

import 'count_format.dart';
import 'git_error.dart';

/// The two transfer phases `git clone` reports (core's
/// `parseTransferProgress`), named as git names them on stderr.
enum ClonePhase {
  receiving('receiving objects'),
  resolving('resolving deltas');

  const ClonePhase(this.gitName);

  /// TASKS 「兩段進度…各自顯示實際數字」: the phase is written out, or a count
  /// restarting from zero would read as the clone going backwards (W-D7).
  final String gitName;
}

/// `GBM_EVENT_CLONE_PROGRESS`'s payload.
@immutable
class CloneProgress {
  const CloneProgress({
    required this.phase,
    required this.current,
    required this.total,
  });

  factory CloneProgress.fromJson(Map<String, dynamic> json) => CloneProgress(
    phase: switch (json['phase'] as String) {
      'receiving' => ClonePhase.receiving,
      'resolving' => ClonePhase.resolving,
      final String other => throw FormatException('unknown phase', other),
    },
    current: json['current'] as int,
    total: json['total'] as int,
  );

  final ClonePhase phase;
  final int current;
  final int total;

  /// `receiving objects 12,480 / 31,206` -- P10's Log mock writes the
  /// running clone row this way.
  String get label =>
      '${phase.gitName} ${formatCount(current)} / ${formatCount(total)}';
}

/// `GBM_EVENT_CLONE_FINISHED`'s payload, sent exactly once per job.
@immutable
class CloneFinished {
  const CloneFinished({
    required this.ok,
    this.error,
    this.removedPath,
    this.removalError,
  });

  factory CloneFinished.fromJson(Map<String, dynamic> json) => CloneFinished(
    ok: json['ok'] as bool,
    error: switch (json['error']) {
      final Map<String, dynamic> e => GitError.fromJson(e),
      _ => null,
    },
    removedPath: json['removedPath'] as String?,
    removalError: json['removalError'] as String?,
  );

  final bool ok;

  /// Already credential-masked: [GitError.fromJson] is a masking point (R6).
  final GitError? error;

  /// Set when the cancelled job's own destination is gone now.
  final String? removedPath;

  /// Why the cancelled job's cleanup stopped short.
  final String? removalError;
}
