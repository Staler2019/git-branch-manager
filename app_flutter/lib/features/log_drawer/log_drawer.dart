import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/models/operation_record.dart';
import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/lucide_icon.dart';

enum _LogLevel { all, info, warning, error }

/// The log drawer widget for displaying operation records. Self-contained with
/// local filtering state. Supports filtering by level (all/info/warning/error),
/// copying all entries, and saving them to a plain-text file.
///
/// Shows time, level icon, command, exit code, and duration. Entries are
/// displayed newest-first. No external dependencies — takes record list as
/// constructor param only.
class LogDrawer extends StatefulWidget {
  const LogDrawer({
    super.key,
    required this.records,
    this.showTimeouts = false,
    this.showColumnHeaders = false,
  });

  final List<GbmLogEntry> records;

  /// Preferences → Developer → LOG, 「在 Log 顯示每個指令的時限」: a column
  /// with the limit each command actually ran under, multiplier applied.
  final bool showTimeouts;

  /// Preferences → Developer → LOG, 「在 Log 顯示欄名列」: a row naming the
  /// columns above the list. A switch of its own, by ruling.
  final bool showColumnHeaders;

  @override
  State<LogDrawer> createState() => _LogDrawerState();
}

class _LogDrawerState extends State<LogDrawer> {
  _LogLevel _selectedLevel = _LogLevel.all;

  /// Filters on [OperationRecord.level] rather than re-deriving the
  /// conditions here.
  ///
  /// The predicates this replaces were `failed && !cancelled && !timedOut`
  /// for warning against `cancelled || timedOut || exitCode != 0` for error
  /// -- warning was a strict *subset* of error, so selecting Error also
  /// showed every warning and spec's three-level `LOGRULES` model was not
  /// actually a partition. Going through `level` makes the three mutually
  /// exclusive by construction.
  List<GbmLogEntry> get _filteredRecords {
    return widget.records.where((record) {
      return switch (_selectedLevel) {
        _LogLevel.all => true,
        _LogLevel.info => record.level == OperationLogLevel.info,
        _LogLevel.warning => record.level == OperationLogLevel.warning,
        _LogLevel.error => record.level == OperationLogLevel.error,
      };
    }).toList();
  }

  /// One plain-text line per record, shared by Copy all and Save as… so the
  /// two exports cannot drift apart.
  ///
  /// Carries every field spec page 10 item 4 lists for a log row: ISO-8601
  /// timestamp, level, the git command verbatim, its exit code, and how long
  /// it took. Nothing here reaches into credentials or file contents -- the
  /// `LOGRULES` "不記什麼" row is satisfied upstream, by what
  /// `OperationRecord` chooses to carry at all.
  static String _formatRecord(GbmLogEntry entry) {
    final String when = DateTime.fromMillisecondsSinceEpoch(entry.whenEpochMs)
        .toIso8601String();
    final String head =
        '$when  ${entry.levelLabel}  ${escapeControlChars(entry.message)}';
    // An app-level event is not a process: printing `(exit 0, 0ms)` after it
    // would read as a git invocation that succeeded instantly.
    // A running record has no exit code or duration yet; its placeholders
    // would read as an instant success. The limit is exported whether or not
    // the drawer shows its column: a pasted log is where it gets read.
    return switch (entry) {
      OperationRecord(running: true) => switch (_limitForExport(entry)) {
        final String limit => '$head  ($limit)',
        null => head,
      },
      OperationRecord(:final int exitCode, :final int durationMs) =>
        '$head  (exit $exitCode, ${durationMs}ms'
            '${switch (_limitForExport(entry)) {
              final String limit => ', $limit',
              null => '',
            }})',
      AppLogEntry() => head,
    };
  }

  String get _exportText => _filteredRecords.map(_formatRecord).join('\n');

  Future<void> _copyAll() async {
    await Clipboard.setData(ClipboardData(text: _exportText));

    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
    }
  }

  /// Spec page 10's `LOGRULES` export row: "Save as…（純文字）".
  ///
  /// Writes into the platform documents directory under a timestamped name
  /// rather than opening a native save panel. When this was written the app
  /// had no file-picker dependency at all; `file_selector` has since been
  /// added for context menu 05-K's "Save this revision as…"
  /// ([FileSavePicker]), so this could be switched over — it has not been,
  /// because a log that reliably lands somewhere findable, with the full
  /// path shown afterwards so it can be attached to a bug report, is not a
  /// worse outcome than a save panel, and changing it here was outside that
  /// change's scope.
  Future<void> _saveAs() async {
    final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(
      context,
    );
    try {
      final Directory dir = await getApplicationDocumentsDirectory();
      // Colons are illegal in Windows filenames, so the ISO timestamp is
      // flattened rather than used verbatim.
      final String stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final File file = File('${dir.path}/gbm-log-$stamp.txt');
      await file.writeAsString(_exportText);
      messenger?.showSnackBar(
        SnackBar(content: Text('Log saved to ${file.path}')),
      );
    } on FileSystemException catch (e) {
      messenger?.showSnackBar(
        SnackBar(content: Text('Could not save the log: ${e.message}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;

    return Container(
      decoration: BoxDecoration(
        color: colors.surfacePanel,
        border: Border(top: BorderSide(color: colors.borderSubtle)),
      ),
      child: Column(
        children: <Widget>[
          // Header with filter controls
          Container(
            padding: const EdgeInsets.all(GbmSpacing.space3),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.borderSubtle)),
            ),
            child: Row(
              children: <Widget>[
                Text(
                  'Filter:',
                  style: TextStyle(
                    fontSize: GbmTypography.textSm,
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(width: GbmSpacing.space2),
                for (final level in _LogLevel.values) ...<Widget>[
                  TextButton(
                    onPressed: () => setState(() => _selectedLevel = level),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: GbmSpacing.space2,
                      ),
                      backgroundColor: _selectedLevel == level
                          ? colors.surfaceSelected
                          : Colors.transparent,
                    ),
                    child: Text(
                      level.name[0].toUpperCase() + level.name.substring(1),
                      style: TextStyle(
                        fontSize: GbmTypography.textXs,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  if (level != _LogLevel.values.last)
                    const SizedBox(width: GbmSpacing.space1),
                ],
                const Spacer(),
                TextButton.icon(
                  onPressed: _filteredRecords.isEmpty ? null : _copyAll,
                  icon: const Icon(Icons.copy, size: 14),
                  label: Text(
                    'Copy All',
                    style: TextStyle(fontSize: GbmTypography.textXs),
                  ),
                ),
                const SizedBox(width: GbmSpacing.space2),
                TextButton.icon(
                  onPressed: _filteredRecords.isEmpty ? null : _saveAs,
                  icon: const Icon(Icons.save, size: 14),
                  label: Text(
                    'Save As',
                    style: TextStyle(fontSize: GbmTypography.textXs),
                  ),
                ),
              ],
            ),
          ),

          if (widget.showColumnHeaders)
            _LogColumnNames(showLimit: widget.showTimeouts),

          // Operation list
          Expanded(
            child: _filteredRecords.isEmpty
                ? Center(
                    child: Text(
                      'No operations recorded yet',
                      style: TextStyle(color: colors.textTertiary),
                    ),
                  )
                : ListView.builder(
                    reverse: true,
                    itemCount: _filteredRecords.length,
                    itemBuilder: (context, index) {
                      final record =
                          _filteredRecords[_filteredRecords.length - 1 - index];
                      return _LogRow(
                        entry: record,
                        showLimit: widget.showTimeouts,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// HH:mm:ss in local time -- entries within one session span at most a few
/// hours, so the date portion would just be visual noise.
String _formatTime(int epochMs) {
  final DateTime when = DateTime.fromMillisecondsSinceEpoch(epochMs);
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${pad(when.hour)}:${pad(when.minute)}:${pad(when.second)}';
}

/// The limit an invocation ran under, as the limit column writes it: a local
/// command's total (「限 120s」), a network command's no-data limit (「無傳輸
/// 60s」). Both already carry the user's multiplier -- core arms exactly this
/// number. Empty when neither applies.
String _limitLabel(OperationRecord record) {
  if (record.timeoutMs > 0) return '限 ${_seconds(record.timeoutMs)}';
  if (record.idleTimeoutMs > 0) return '無傳輸 ${_seconds(record.idleTimeoutMs)}';
  return '';
}

/// The same choice as [_limitLabel], in the export's own words and units.
String? _limitForExport(OperationRecord record) {
  if (record.timeoutMs > 0) return 'limit ${record.timeoutMs}ms';
  if (record.idleTimeoutMs > 0) return 'idle limit ${record.idleTimeoutMs}ms';
  return null;
}

String _seconds(int ms) => ms % 1000 == 0 ? '${ms ~/ 1000}s' : '${ms}ms';

/// Column widths from the design spec's screen 3. The time column is fixed
/// so a header can sit over it; HH:mm:ss in a mono face is one width anyway.
const double _kIconWidth = 14;
const double _kLevelWidth = 68;
const double _kTimeWidth = 56;
const double _kDurationWidth = 72;
const double _kExitWidth = 44;
const double _kLimitWidth = 84;

/// The one layout the column-name row and every log row are built from, so
/// a name cannot drift from the cells under it -- the defect reported on
/// the first draft (「欄位名稱與欄位內容位置沒有對起來」).
class _LogColumns extends StatelessWidget {
  const _LogColumns({
    required this.icon,
    required this.level,
    required this.time,
    required this.command,
    required this.duration,
    required this.exit,
    required this.limit,
    required this.showLimit,
  });

  final Widget icon;
  final Widget level;
  final Widget time;
  final Widget command;
  final Widget duration;
  final Widget exit;
  final Widget limit;
  final bool showLimit;

  @override
  Widget build(BuildContext context) {
    const Widget gap = SizedBox(width: GbmSpacing.space2);
    return Row(
      children: <Widget>[
        SizedBox(width: _kIconWidth, child: icon),
        gap,
        SizedBox(width: _kLevelWidth, child: level),
        gap,
        SizedBox(width: _kTimeWidth, child: time),
        gap,
        Expanded(child: command),
        gap,
        SizedBox(
          width: _kDurationWidth,
          child: Align(alignment: Alignment.centerRight, child: duration),
        ),
        gap,
        SizedBox(width: _kExitWidth, child: exit),
        if (showLimit) ...<Widget>[
          gap,
          Container(
            width: _kLimitWidth,
            padding: const EdgeInsets.only(left: GbmSpacing.space2),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: context.gbmColors.borderSubtle),
              ),
            ),
            child: limit,
          ),
        ],
      ],
    );
  }
}

/// 「顯示欄位名稱」: 11px names over the same columns, with 時限 only while
/// its column is shown.
class _LogColumnNames extends StatelessWidget {
  const _LogColumnNames({required this.showLimit});

  final bool showLimit;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    Widget name(String text) => Text(
      text,
      maxLines: 1,
      softWrap: false,
      style: TextStyle(
        fontSize: GbmTypography.textXs,
        color: colors.textTertiary,
      ),
    );
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: GbmSpacing.space3,
        vertical: GbmSpacing.space1,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      child: _LogColumns(
        icon: const SizedBox.shrink(),
        level: name('層級'),
        time: name('時間'),
        command: name('指令'),
        duration: name('耗時'),
        exit: name('exit'),
        limit: name('時限'),
        showLimit: showLimit,
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.entry, required this.showLimit});

  final GbmLogEntry entry;
  final bool showLimit;

  /// The icon for a git invocation stays a four-way on the *cause*, which is
  /// finer than the three levels and orthogonal to them -- a timeout and a
  /// rejected exit are both errors but not the same thing. An app-level
  /// event has no process outcome to be finer about, so it falls back to the
  /// level.
  ///
  /// The failure arm reads [OperationRecord.failed] rather than `exitCode !=
  /// 0`, which is the same predicate gating the `exit N` chip below. It used
  /// to re-derive the condition, and that is precisely how a row could end up
  /// labelled INFO next to a red error icon once a non-zero exit stopped
  /// automatically meaning failure ([CULT-single-source-of-truth]).
  ///
  /// A running record is answered before any of this, in [build]: it is
  /// drawn with a turning Lucide loader rather than a Material glyph.
  static IconData _iconFor(GbmLogEntry entry) => switch (entry) {
    OperationRecord(cancelled: true) => Icons.stop_circle,
    OperationRecord(timedOut: true) => Icons.schedule,
    OperationRecord(failed: true) => Icons.error,
    OperationRecord() => Icons.check_circle,
    AppLogEntry(level: OperationLogLevel.info) => Icons.info_outline,
    AppLogEntry(level: OperationLogLevel.warning) => Icons.warning_amber,
    AppLogEntry(level: OperationLogLevel.error) => Icons.error_outline,
  };

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    // Colour follows the level, not `failed`: a cancelled read used to be
    // painted the same danger red as a genuinely rejected command, which is
    // what made a superseded refresh look like a failure.
    final GbmLogEntry shown = entry;
    final bool isRunning = shown is OperationRecord && shown.running;
    final Color statusColor = isRunning
        ? colors.accent
        : switch (entry.level) {
            OperationLogLevel.info => colors.textTertiary,
            OperationLogLevel.warning => colors.warning,
            OperationLogLevel.error => colors.danger,
          };
    final TextStyle metaStyle = TextStyle(
      fontSize: GbmTypography.textXs,
      color: colors.textTertiary,
    );
    // Null for an app-level event: it has no process, so the duration, exit
    // code and stderr blocks below are absent rather than zeroed.
    final OperationRecord? git = switch (entry) {
      final OperationRecord record => record,
      AppLogEntry() => null,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: GbmSpacing.space3,
        vertical: GbmSpacing.space1,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _LogColumns(
            showLimit: showLimit,
            icon: isRunning
                ? _RunningLoader(color: statusColor)
                : Icon(_iconFor(entry), size: 14, color: statusColor),
            // Spec page 10 item 4 lists the level as a field of a log row.
            // It existed only in the export until now; on screen the sole
            // signal was the icon's colour, so "cancelled" and "failed"
            // were indistinguishable at a glance.
            level: Text(
              entry.levelLabel,
              style: TextStyle(
                fontSize: GbmTypography.textXs,
                fontFamily: GbmTypography.fontMono,
                color: statusColor,
              ),
            ),
            time: Text(
              _formatTime(entry.whenEpochMs),
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontSize: GbmTypography.textXs,
                fontFamily: GbmTypography.fontMono,
                color: colors.textTertiary,
              ),
            ),
            command: SelectableText(
              escapeControlChars(entry.message),
              style: TextStyle(
                fontSize: GbmTypography.textSm,
                fontFamily: GbmTypography.fontMono,
                color: colors.textPrimary,
              ),
            ),
            // 「最後面就不用執行中敘述了」: a running row has no duration or
            // exit until its outcome arrives and replaces it. An app event
            // has neither at all. Both keep the cells, empty, so the columns
            // to their right stay in line.
            duration: git == null || git.running
                ? const SizedBox.shrink()
                : Text(
                    '${git.durationMs}ms',
                    maxLines: 1,
                    softWrap: false,
                    style: metaStyle,
                  ),
            exit: git != null && git.failed && git.exitCode != 0
                ? Text(
                    'exit ${git.exitCode}',
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: GbmTypography.textXs,
                      color: statusColor,
                    ),
                  )
                : const SizedBox.shrink(),
            limit: git == null
                ? const SizedBox.shrink()
                : Text(
                    _limitLabel(git),
                    maxLines: 1,
                    softWrap: false,
                    style: metaStyle,
                  ),
          ),
          if (git != null && git.failed && git.stderrText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: GbmSpacing.space1),
              child: SelectableText(
                git.stderrText,
                style: TextStyle(
                  fontSize: GbmTypography.textXs,
                  fontFamily: GbmTypography.fontMono,
                  color: colors.diffDelText,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// spec P10's `icLoader`, at the 14px every other row icon uses, turning once
/// per 1.2 seconds -- and standing still when the platform asks for reduced
/// motion.
class _RunningLoader extends StatefulWidget {
  const _RunningLoader({required this.color});

  final Color color;

  @override
  State<_RunningLoader> createState() => _RunningLoaderState();
}

class _RunningLoaderState extends State<_RunningLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget icon = LucideIcon(
      'loader-circle',
      size: 14,
      color: widget.color,
    );
    if (MediaQuery.of(context).disableAnimations) {
      _turn.stop();
      return icon;
    }
    if (!_turn.isAnimating) _turn.repeat();
    return RotationTransition(turns: _turn, child: icon);
  }
}
