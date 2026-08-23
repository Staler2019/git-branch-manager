import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/operation_record.dart';

void main() {
  group('escapeControlChars', () {
    test('leaves an ordinary command untouched', () {
      expect(escapeControlChars('git fetch origin'), 'git fetch origin');
    });

    test('makes the unit separator visible', () {
      // The reported symptom: RefStore.cpp joins for-each-ref's eight
      // %(...) fields with '\x1f', which is invisible in a SelectableText.
      // The whole --format= argument therefore read as one run-together
      // string, and copying it out of the log dropped the separators
      // entirely -- which is how the pasted command reached this repo.
      expect(
        escapeControlChars('%(refname)\u001f%(objecttype)'),
        r'%(refname)\x1f%(objecttype)',
      );
    });

    test('escapes the real for-each-ref format string', () {
      const String sep = '\u001f';
      final String raw =
          '--format=%(refname)$sep%(objecttype)$sep%(objectname)$sep'
          '%(*objectname)$sep%(upstream)$sep%(upstream:track)$sep'
          '%(HEAD)$sep%(worktreepath)';

      final String escaped = escapeControlChars(raw);

      expect(escaped.contains('\u001f'), isFalse);
      expect(RegExp(r'\\x1f').allMatches(escaped).length, 7);
      expect(escaped, startsWith(r'--format=%(refname)\x1f%(objecttype)'));
    });

    test('uses the conventional short forms for tab, newline and return', () {
      expect(escapeControlChars('a\tb'), r'a\tb');
      expect(escapeControlChars('a\nb'), r'a\nb');
      expect(escapeControlChars('a\rb'), r'a\rb');
    });

    test('escapes NUL and DEL', () {
      expect(escapeControlChars('a\u0000b'), r'a\x00b');
      expect(escapeControlChars('a\u007fb'), r'a\x7fb');
    });

    test('does NOT touch backslashes', () {
      // OperationRecord::commandLine() (src/core/base/Logging.cpp:36-38)
      // already doubles a backslash inside a quoted argument, so escaping
      // it again here would render every Windows path with twice the
      // backslashes it has. The cost is that the output is visible rather
      // than strictly round-trippable -- a literal `\x1f` typed by a user
      // into a path is indistinguishable from an escaped 0x1F byte. That
      // trade is deliberate: this is read by a human, not re-parsed.
      expect(escapeControlChars(r'C:\Users\me\repo'), r'C:\Users\me\repo');
    });

    test('leaves non-ASCII text alone', () {
      // Only C0 controls and DEL are escaped -- a branch name in Chinese or
      // an emoji in a commit message must stay legible.
      expect(escapeControlChars('分支/功能 ✨'), '分支/功能 ✨');
    });

    test('an empty string is unchanged', () {
      expect(escapeControlChars(''), '');
    });
  });
}
