/// Which of spec page 10's three `LOGRULES` severity levels an
/// [OperationRecord] belongs to.
///
/// Deliberately three values, matching the drawer's filter buttons, rather
/// than one per outcome shape: `CANCELLED` and `TIMEOUT` are both outcome
/// *causes*, and conflating "which cause" with "how bad" is what let the
/// drawer's warning filter become a strict subset of its error filter.
enum OperationLogLevel { info, warning, error }

/// One line in the operation log.
///
/// Spec page 10's `LOGRULES` 記什麼 row asks for two different things:
/// 「每一次實際執行的 git 指令原文、工作目錄、結束代碼、耗時」 **and**
/// 「應用層事件（開啟 repo、切分支、prune 掉哪些 ref）」. Only the first has
/// ever existed here, because [OperationRecord] is git-invocation-shaped --
/// it has no way to say "the user opened this repository".
///
/// The split lives entirely on the Dart side, and that is not an omission:
/// `src/core/base/Logging.h` has sinks and nothing else -- there is no
/// C++-side log file, no rotation, and no storage. The whole log is
/// [RepoSessionState.operationLog], fed by `GBM_EVENT_OPERATION_LOG_RECORD`.
/// So an app-level event needs no capi at all, only a second member of this
/// closed set.
///
/// Sealed, so the drawer's rendering and its plain-text export must both
/// handle every kind -- the two came to disagree once already (see [level]).
/// Both members live in this file because a sealed type's subtypes must be
/// in the same library.
sealed class GbmLogEntry {
  const GbmLogEntry();

  int get whenEpochMs;

  /// Which of `LOGRULES`' three severity levels this line belongs to.
  OperationLogLevel get level;

  /// The level word shown on the row and written into the export.
  String get levelLabel;

  /// The wide middle column's text, unescaped -- rendering and export both
  /// put it through [escapeControlChars] themselves.
  String get message;
}

/// Mirrors `gbm::OperationRecord` (src/core/base/Logging.h) as serialized by
/// `capi::toJson(const OperationRecord&)` -- one `git` invocation, for an
/// operation-log panel.
class OperationRecord extends GbmLogEntry {
  const OperationRecord({
    required this.whenEpochMs,
    required this.repoDir,
    required this.argv,
    required this.commandLine,
    required this.exitCode,
    required this.durationMs,
    required this.stderrText,
    required this.cancelled,
    required this.timedOut,
    this.benignExit = false,
  });

  factory OperationRecord.fromJson(Map<String, dynamic> json) {
    return OperationRecord(
      whenEpochMs: json['whenEpochMs'] as int,
      repoDir: json['repoDir'] as String,
      argv: (json['argv'] as List<dynamic>).cast<String>(),
      commandLine: json['commandLine'] as String,
      exitCode: json['exitCode'] as int,
      durationMs: json['durationMs'] as int,
      stderrText: json['stderrText'] as String,
      cancelled: json['cancelled'] as bool,
      timedOut: json['timedOut'] as bool,
      benignExit: json['benignExit'] as bool,
    );
  }

  @override
  final int whenEpochMs;

  final String repoDir;
  final List<String> argv;
  final String commandLine;
  final int exitCode;
  final int durationMs;
  final String stderrText;
  final bool cancelled;
  final bool timedOut;

  /// True when the caller declared [exitCode] a normal *answer* for this
  /// command rather than a refusal — see `GitCommand::benignExitCodes` in
  /// `src/core/git/GitCommand.h`, which is where the declaration is made and
  /// the only place that knows what question was asked.
  ///
  /// The reported case: `git config --local --get user.name` exits 1 when the
  /// key is unset, so every refresh wrote two red `ERROR` rows for reading an
  /// identity that simply is not configured. Spec page 10's `LOGRULES`
  /// reserves error for an action that was actually *refused*; a `--get` on an
  /// unset key answered.
  ///
  /// Defaulted rather than `required`, unlike every other field here.
  /// [fromJson] is the only production construction site — everything else is
  /// a test fixture, where `false` ("an ordinary invocation") is exactly what
  /// an omitted value should mean. The strictness that matters is on the wire,
  /// and it is kept: [fromJson] reads `as bool` with no fallback, so a payload
  /// missing the key is a loud `TypeError` rather than a silent `false`. The
  /// C++ side always serializes it and nothing here is persisted or replayed,
  /// so there is no legitimate "old payload" to be lenient towards.
  final bool benignExit;

  /// Whether this invocation did not do what was asked.
  ///
  /// A declared answer is not a failure — that is the whole point of
  /// [benignExit] — but a cancellation or a timeout stays one whatever the
  /// caller declared, because neither is an answer to anything.
  bool get failed => (exitCode != 0 && !benignExit) || cancelled || timedOut;

  /// The single source of truth for how severely this record should read --
  /// the drawer's filter, its row styling, and the plain-text export all go
  /// through here rather than re-deriving the conditions locally.
  ///
  /// [cancelled] must be tested *first*: a child killed by
  /// `ProcessRunner::execute()`'s cancel path also carries a non-zero exit
  /// code (SIGTERM leaves 128 + 15 = 143), so checking [exitCode] first
  /// makes the cancelled branch unreachable and reports a superseded read as
  /// a failure. That is exactly the misreport this getter was added to fix:
  /// `Session::refreshHistory()` terminates the in-flight `for-each-ref`
  /// whenever a newer refresh is posted, and the abandoned one is not an
  /// error -- it is work that was replaced. Spec's `LOGRULES` reserves
  /// error for an action that was actually refused (`git push … exit 1`).
  ///
  /// [timedOut] is tested before [benignExit] for the same reason [cancelled]
  /// is tested before both: a command killed for taking too long never
  /// finished saying whatever it was going to say, so a declared answer code
  /// left behind by the kill is not an answer. The C++ side sets [benignExit]
  /// purely from the declared code list and deliberately does not guard it on
  /// these two flags — this ordering is what makes that safe, and it is the
  /// only place the precedence lives.
  @override
  OperationLogLevel get level {
    if (cancelled) return OperationLogLevel.warning;
    if (timedOut) return OperationLogLevel.error;
    if (exitCode != 0 && !benignExit) return OperationLogLevel.error;
    return OperationLogLevel.info;
  }

  /// The level word shown on a log row and written into the plain-text
  /// export, so the two cannot drift apart.
  ///
  /// Switches on [level] and nothing else -- a second, independent condition
  /// tree over [cancelled]/[exitCode] is how the drawer's filter and its
  /// export came to disagree in the first place. `TIMEOUT` is a refinement
  /// *within* error, so it cannot contradict the level.
  ///
  /// `warning` maps to `CANCELLED` because cancellation is currently its
  /// only cause; a second warning cause must split this arm rather than
  /// widen the word.
  @override
  String get levelLabel => switch (level) {
    OperationLogLevel.info => 'INFO',
    OperationLogLevel.warning => 'CANCELLED',
    OperationLogLevel.error => timedOut ? 'TIMEOUT' : 'ERROR',
  };

  @override
  String get message => commandLine;
}

/// An app-level event: something the app did that no single `git` invocation
/// describes.
///
/// `LOGRULES` names three by example -- 「開啟 repo、切分支、prune 掉哪些
/// ref」 -- and page 10's own mockup draws a fourth as a warning row:
/// 「origin/graph-lanes 已不存在於遠端，標記為 gone（尚未 prune）」.
///
/// Carries no exit code, duration or stderr, because it is not a process:
/// the row and the export both omit those rather than printing a
/// meaningless `exit 0`.
///
/// [message] is written by the caller and goes straight into the log and its
/// export, so `LOGRULES`' 不記什麼 row (認證資訊、remote URL 中的 token、檔
/// 案內容) is the caller's responsibility -- see the app-event helpers on
/// [RepoSessionController], which is where every one of these is built.
final class AppLogEntry extends GbmLogEntry {
  const AppLogEntry({
    required this.whenEpochMs,
    required this.level,
    required this.message,
  });

  @override
  final int whenEpochMs;

  @override
  final OperationLogLevel level;

  @override
  final String message;

  /// `WARNING`, not [OperationRecord]'s `CANCELLED`: that word is precise
  /// there because cancellation is a git invocation's only way to be a
  /// warning, and an app event has no such thing to be cancelled.
  @override
  String get levelLabel => switch (level) {
    OperationLogLevel.info => 'INFO',
    OperationLogLevel.warning => 'WARNING',
    OperationLogLevel.error => 'ERROR',
  };
}

/// Renders C0 control characters (and DEL) as visible escapes, so a command
/// line that carries one is legible instead of running together.
///
/// The case that forced this: `RefStore::load()` joins `for-each-ref`'s eight
/// `%(...)` fields with `\x1f` (`src/core/git/RefStore.cpp`'s
/// `kFieldSeparator`). In a `SelectableText` those bytes have no glyph, so
/// the whole `--format=` argument reads as one run-together string -- and
/// copying it out of the log drops them entirely, which is how a perfectly
/// well-formed command reached a bug report looking corrupted.
///
/// Backslashes are deliberately **not** escaped. `OperationRecord::commandLine()`
/// (src/core/base/Logging.cpp) already doubles a backslash inside a quoted
/// argument, so doing it again here would render every Windows path with twice
/// the backslashes it has. The consequence, stated rather than hidden: the
/// output is *visible* but not strictly round-trippable -- a literal `\x1f`
/// someone typed into a path is indistinguishable from an escaped 0x1F byte.
/// This text is read by a human, not re-parsed, so visibility wins.
///
/// Applied to the command line only. `stderrText` is genuinely multi-line and
/// escaping its newlines would collapse it into one unreadable row.
String escapeControlChars(String text) {
  final StringBuffer out = StringBuffer();
  for (final int unit in text.codeUnits) {
    if (unit >= 0x20 && unit != 0x7f) {
      out.writeCharCode(unit);
      continue;
    }
    switch (unit) {
      case 0x09:
        out.write(r'\t');
      case 0x0a:
        out.write(r'\n');
      case 0x0d:
        out.write(r'\r');
      default:
        out.write(r'\x');
        out.write(unit.toRadixString(16).padLeft(2, '0'));
    }
  }
  return out.toString();
}
