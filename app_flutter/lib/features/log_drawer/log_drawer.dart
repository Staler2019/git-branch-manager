import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/models/operation_record.dart';
import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';

enum _LogLevel { all, info, warning, error }

/// The log drawer widget for displaying operation records. Self-contained with
/// local filtering state. Supports filtering by level (all/info/warning/error),
/// copying all entries, and saving them to a plain-text file.
///
/// Shows time, level icon, command, exit code, and duration. Entries are
/// displayed newest-first. No external dependencies — takes record list as
/// constructor param only.
class LogDrawer extends StatefulWidget {
  const LogDrawer({super.key, required this.records});

  final List<GbmLogEntry> records;

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
    final String when = DateTime.fromMillisecondsSinceEpoch(
      entry.whenEpochMs,
    ).toIso8601String();
    final String head =
        '$when  ${entry.levelLabel}  ${escapeControlChars(entry.message)}';
    // An app-level event is not a process: printing `(exit 0, 0ms)` after it
    // would read as a git invocation that succeeded instantly.
    return switch (entry) {
      OperationRecord(:final int exitCode, :final int durationMs) =>
        '$head  (exit $exitCode, ${durationMs}ms)',
      AppLogEntry() => head,
    };
  }

  String get _exportText => _filteredRecords.map(_formatRecord).join('\n');

  Future<void> _copyAll() async {
    await Clipboard.setData(ClipboardData(text: _exportText));

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
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
                      return _LogRow(entry: record);
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

class _LogRow extends StatelessWidget {
  const _LogRow({required this.entry});

  final GbmLogEntry entry;

  /// The icon for a git invocation stays a four-way on the *cause*, which is
  /// finer than the three levels and orthogonal to them -- a timeout and a
  /// rejected exit are both errors but not the same thing. An app-level
  /// event has no process outcome to be finer about, so it falls back to the
  /// level.
  static IconData _iconFor(GbmLogEntry entry) => switch (entry) {
    OperationRecord(cancelled: true) => Icons.stop_circle,
    OperationRecord(timedOut: true) => Icons.schedule,
    OperationRecord(:final int exitCode) when exitCode != 0 => Icons.error,
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
    final Color statusColor = switch (entry.level) {
      OperationLogLevel.info => colors.textTertiary,
      OperationLogLevel.warning => colors.warning,
      OperationLogLevel.error => colors.danger,
    };
    final IconData statusIcon = _iconFor(entry);
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
          Row(
            children: <Widget>[
              Icon(statusIcon, size: 14, color: statusColor),
              const SizedBox(width: GbmSpacing.space2),
              // Spec page 10 item 4 lists the level as a field of a log row.
              // It existed only in the export until now; on screen the sole
              // signal was the icon's colour, so "cancelled" and "failed"
              // were indistinguishable at a glance. Fixed width so the
              // timestamps below it stay in a column.
              SizedBox(
                width: 68,
                child: Text(
                  entry.levelLabel,
                  style: TextStyle(
                    fontSize: GbmTypography.textXs,
                    fontFamily: GbmTypography.fontMono,
                    color: statusColor,
                  ),
                ),
              ),
              const SizedBox(width: GbmSpacing.space2),
              Text(
                _formatTime(entry.whenEpochMs),
                style: TextStyle(
                  fontSize: GbmTypography.textXs,
                  fontFamily: GbmTypography.fontMono,
                  color: colors.textTertiary,
                ),
              ),
              const SizedBox(width: GbmSpacing.space2),
              Expanded(
                child: SelectableText(
                  escapeControlChars(entry.message),
                  style: TextStyle(
                    fontSize: GbmTypography.textSm,
                    fontFamily: GbmTypography.fontMono,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              if (git != null) ...<Widget>[
                const SizedBox(width: GbmSpacing.space2),
                Text(
                  '${git.durationMs}ms',
                  style: TextStyle(
                    fontSize: GbmTypography.textXs,
                    color: colors.textTertiary,
                  ),
                ),
                if (git.failed && git.exitCode != 0) ...<Widget>[
                  const SizedBox(width: GbmSpacing.space1),
                  Text(
                    'exit ${git.exitCode}',
                    style: TextStyle(
                      fontSize: GbmTypography.textXs,
                      color: statusColor,
                    ),
                  ),
                ],
              ],
            ],
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
