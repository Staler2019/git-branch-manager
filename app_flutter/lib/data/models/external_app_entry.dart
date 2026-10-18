/// One user-defined "open this worktree with…" entry: a display label and a
/// one-line command run in the worktree directory. Spec:
/// `docs/claude-design-demo/open-with-apps-spec.html`.
///
/// [create] is the only way one comes into being -- typed into Preferences
/// or read back from storage through [fromJson] -- so the launcher can rely
/// on every rule it enforces:
///
/// - label and command are non-empty after trimming;
/// - the command does not start with `-`, which `sh -c` would read as one
///   of its own options (security review F6);
/// - [pathToken] is never inside quotes. The launcher substitutes `"$1"`
///   for it, so `code "{path}"` would become `code ""$1""` and leave the
///   path unquoted -- open to word splitting and globbing (F4). The two
///   spellings that plainly mean "the path, quoted", `"{path}"` and
///   `'{path}'`, are normalised to a bare [pathToken]; any other quoted
///   [pathToken] is rejected.
///
/// The list these live in is application-wide and never read from a
/// repository's own content (Q3): whoever can write it can already edit the
/// user's shell profile.
class ExternalAppEntry {
  const ExternalAppEntry._({
    required this.id,
    required this.label,
    required this.command,
  });

  /// Replaced by the worktree path at launch: `"$1"` on macOS/Linux, `.` on
  /// Windows (the working directory already is the worktree).
  static const String pathToken = '{path}';

  final String id;
  final String label;
  final String command;

  static ExternalAppEntryResult create({
    required String label,
    required String command,
    required String Function() newId,
  }) => _validate(id: null, label: label, command: command, newId: newId);

  /// The same rules as [create]; null for anything it would reject, or for
  /// an object that is not the shape [toJson] writes.
  static ExternalAppEntry? fromJson(Map<String, dynamic> json) {
    final Object? id = json['id'];
    final Object? label = json['label'];
    final Object? command = json['command'];
    if (id is! String || id.isEmpty || label is! String || command is! String) {
      return null;
    }
    return switch (_validate(
      id: id,
      label: label,
      command: command,
      newId: () => id,
    )) {
      ExternalAppEntryAccepted(:final ExternalAppEntry entry) => entry,
      ExternalAppEntryRejected() => null,
    };
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'label': label,
    'command': command,
  };

  /// A copy with new text, through the same rules. The id is kept.
  ExternalAppEntryResult edit({String? label, String? command}) => _validate(
    id: id,
    label: label ?? this.label,
    command: command ?? this.command,
    newId: () => id,
  );

  static ExternalAppEntryResult _validate({
    required String? id,
    required String label,
    required String command,
    required String Function() newId,
  }) {
    final String l = label.trim();
    final String c = command
        .trim()
        .replaceAll('"$pathToken"', pathToken)
        .replaceAll("'$pathToken'", pathToken);
    if (l.isEmpty) return const ExternalAppEntryRejected('名稱不能是空的');
    if (c.isEmpty) return const ExternalAppEntryRejected('指令不能是空的');
    if (c.startsWith('-')) {
      return const ExternalAppEntryRejected('指令不能以 - 開頭');
    }
    if (_quotedPathToken(c)) {
      return const ExternalAppEntryRejected('{path} 不能放在引號裡');
    }
    return ExternalAppEntryAccepted(
      ExternalAppEntry._(id: id ?? newId(), label: l, command: c),
    );
  }

  /// Whether any [pathToken] sits inside a single- or double-quoted span,
  /// following POSIX quoting: a backslash escapes the next character outside
  /// single quotes, and nothing is special inside them.
  static bool _quotedPathToken(String c) {
    String? quote;
    for (int i = 0; i < c.length; i++) {
      final String ch = c[i];
      if (quote != "'" && ch == r'\') {
        i++;
        continue;
      }
      if (quote == null) {
        if (ch == "'" || ch == '"') {
          quote = ch;
        }
      } else if (ch == quote) {
        quote = null;
      } else if (c.startsWith(pathToken, i)) {
        return true;
      }
    }
    return false;
  }
}

/// What [ExternalAppEntry.create] decided.
sealed class ExternalAppEntryResult {
  const ExternalAppEntryResult();
}

final class ExternalAppEntryAccepted extends ExternalAppEntryResult {
  const ExternalAppEntryAccepted(this.entry);

  final ExternalAppEntry entry;
}

final class ExternalAppEntryRejected extends ExternalAppEntryResult {
  const ExternalAppEntryRejected(this.reason);

  /// Shown under the row in Preferences, as the spec's reject hint.
  final String reason;
}
