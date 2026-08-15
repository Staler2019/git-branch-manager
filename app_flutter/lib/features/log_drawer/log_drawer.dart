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

  final List<OperationRecord> records;

  @override
  State<LogDrawer> createState() => _LogDrawerState();
}

class _LogDrawerState extends State<LogDrawer> {
  _LogLevel _selectedLevel = _LogLevel.all;

  List<OperationRecord> get _filteredRecords {
    return widget.records.where((record) {
      switch (_selectedLevel) {
        case _LogLevel.all:
          return true;
        case _LogLevel.info:
          return !record.failed;
        case _LogLevel.warning:
          return record.failed && !record.cancelled && !record.timedOut;
        case _LogLevel.error:
          return record.cancelled || record.timedOut || record.exitCode != 0;
      }
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
  static String _formatRecord(OperationRecord r) {
    final String when = DateTime.fromMillisecondsSinceEpoch(
      r.whenEpochMs,
    ).toIso8601String();
    final String level = r.cancelled
        ? 'CANCELLED'
        : r.timedOut
        ? 'TIMEOUT'
        : r.failed
        ? 'ERROR'
        : 'INFO';
    return '$when  $level  ${r.commandLine}  '
        '(exit ${r.exitCode}, ${r.durationMs}ms)';
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
  /// rather than opening a native save panel: this app has no file-picker
  /// dependency (see pubspec.yaml), and a log that reliably lands somewhere
  /// findable — with the full path shown afterwards so it can be attached to
  /// a bug report — beats a button that stays disabled.
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
                      return _OperationRow(record: record);
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

class _OperationRow extends StatelessWidget {
  const _OperationRow({required this.record});

  final OperationRecord record;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final Color statusColor = record.failed
        ? colors.danger
        : colors.textTertiary;
    final IconData statusIcon = record.cancelled
        ? Icons.stop_circle
        : record.timedOut
        ? Icons.schedule
        : record.exitCode != 0
        ? Icons.error
        : Icons.check_circle;

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
              Text(
                _formatTime(record.whenEpochMs),
                style: TextStyle(
                  fontSize: GbmTypography.textXs,
                  fontFamily: GbmTypography.fontMono,
                  color: colors.textTertiary,
                ),
              ),
              const SizedBox(width: GbmSpacing.space2),
              Expanded(
                child: SelectableText(
                  record.commandLine,
                  style: TextStyle(
                    fontSize: GbmTypography.textSm,
                    fontFamily: GbmTypography.fontMono,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: GbmSpacing.space2),
              Text(
                '${record.durationMs}ms',
                style: TextStyle(
                  fontSize: GbmTypography.textXs,
                  color: colors.textTertiary,
                ),
              ),
              if (record.failed && record.exitCode != 0) ...<Widget>[
                const SizedBox(width: GbmSpacing.space1),
                Text(
                  'exit ${record.exitCode}',
                  style: TextStyle(
                    fontSize: GbmTypography.textXs,
                    color: statusColor,
                  ),
                ),
              ],
            ],
          ),
          if (record.failed && record.stderrText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: GbmSpacing.space1),
              child: SelectableText(
                record.stderrText,
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
