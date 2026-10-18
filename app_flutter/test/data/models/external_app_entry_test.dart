import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/external_app_entry.dart';

/// `ExternalAppEntry.create` is the only way an entry comes into being --
/// typed into Preferences or read back from storage -- so every rule the
/// launcher relies on (open-with-apps-spec.html, rules table; security
/// review F4/F6/Q3) is pinned here once.
void main() {
  String nextId() => 'id-1';

  ExternalAppEntry accepted(String label, String command) {
    final ExternalAppEntryResult result = ExternalAppEntry.create(
      label: label,
      command: command,
      newId: nextId,
    );
    return switch (result) {
      ExternalAppEntryAccepted(:final ExternalAppEntry entry) => entry,
      ExternalAppEntryRejected(:final String reason) => fail(
        'rejected: $reason',
      ),
    };
  }

  String rejected(String label, String command) {
    final ExternalAppEntryResult result = ExternalAppEntry.create(
      label: label,
      command: command,
      newId: nextId,
    );
    return switch (result) {
      ExternalAppEntryAccepted(:final ExternalAppEntry entry) => fail(
        'accepted: ${entry.command}',
      ),
      ExternalAppEntryRejected(:final String reason) => reason,
    };
  }

  group('create', () {
    test('accepts a plain command and trims both fields', () {
      final ExternalAppEntry e = accepted('  Rider ', ' rider . ');
      expect(e.id, 'id-1');
      expect(e.label, 'Rider');
      expect(e.command, 'rider .');
    });

    test('accepts a bare {path}', () {
      expect(accepted('VS Code', 'code {path}').command, 'code {path}');
    });

    // `code "{path}"` would expand to `code ""$1""`, which leaves $1
    // unquoted (F4); the quotes the user meant are the ones the launcher
    // already adds.
    test('normalises a double-quoted {path}', () {
      expect(accepted('VS Code', 'code "{path}"').command, 'code {path}');
    });

    test('normalises a single-quoted {path}', () {
      expect(accepted('VS Code', "code '{path}'").command, 'code {path}');
    });

    test('rejects {path} inside a longer double-quoted word', () {
      expect(rejected('X', 'open "a {path}"'), isNotEmpty);
    });

    test('rejects {path} inside a longer single-quoted word', () {
      expect(rejected('X', "open 'x{path}'"), isNotEmpty);
    });

    test('rejects an empty or blank label', () {
      expect(rejected('', 'code .'), isNotEmpty);
      expect(rejected('   ', 'code .'), isNotEmpty);
    });

    test('rejects an empty or blank command', () {
      expect(rejected('Code', ''), isNotEmpty);
      expect(rejected('Code', '  \t'), isNotEmpty);
    });

    // After `sh -c` a leading dash is read as a shell option (F6).
    test('rejects a command that starts with a dash', () {
      expect(rejected('X', '-a Finder .'), isNotEmpty);
      expect(rejected('X', '  -x'), isNotEmpty);
    });
  });

  group('edit', () {
    test('keeps the id and applies the same rules', () {
      final ExternalAppEntry e = accepted('Rider', 'rider .');
      final ExternalAppEntryResult ok = e.edit(command: 'code "{path}"');
      expect(ok, isA<ExternalAppEntryAccepted>());
      final ExternalAppEntry edited = (ok as ExternalAppEntryAccepted).entry;
      expect(edited.id, 'id-1');
      expect(edited.label, 'Rider');
      expect(edited.command, 'code {path}');
      expect(e.edit(command: '-x'), isA<ExternalAppEntryRejected>());
      expect(e.edit(label: ' '), isA<ExternalAppEntryRejected>());
    });
  });

  group('JSON', () {
    test('round-trips an accepted entry', () {
      final ExternalAppEntry e = accepted('Rider', 'rider .');
      final ExternalAppEntry? back = ExternalAppEntry.fromJson(e.toJson());
      expect(back?.id, 'id-1');
      expect(back?.label, 'Rider');
      expect(back?.command, 'rider .');
    });

    test('normalises on read as create does', () {
      expect(
        ExternalAppEntry.fromJson(<String, dynamic>{
          'id': 'a',
          'label': 'Code',
          'command': 'code "{path}"',
        })?.command,
        'code {path}',
      );
    });

    // Storage is the second way in; it gets no rule the factory does not
    // apply (Q3).
    test('reads back null for everything create rejects', () {
      for (final String command in <String>[
        '',
        '  ',
        '-x',
        'open "a {path}"',
        "open 'x{path}'",
      ]) {
        expect(
          ExternalAppEntry.fromJson(<String, dynamic>{
            'id': 'a',
            'label': 'L',
            'command': command,
          }),
          isNull,
          reason: command,
        );
      }
      expect(
        ExternalAppEntry.fromJson(<String, dynamic>{
          'id': 'a',
          'label': ' ',
          'command': 'code .',
        }),
        isNull,
      );
    });

    test('reads back null for a malformed object', () {
      expect(
        ExternalAppEntry.fromJson(<String, dynamic>{
          'label': 'L',
          'command': 1,
        }),
        isNull,
      );
      expect(
        ExternalAppEntry.fromJson(<String, dynamic>{
          'label': 'L',
          'command': 'code .',
        }),
        isNull,
      );
    });
  });
}
