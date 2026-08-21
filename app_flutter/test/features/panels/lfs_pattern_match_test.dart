// lfsPatternMatches is what turns two independent capi lists (patterns,
// files) into P19's 「追蹤型別 + 檔數」 grouping, so a wrong answer here
// shows up as a confidently-wrong number in the UI. It is deliberately an
// approximation of gitattributes -- these tests pin both what it does
// support and what it declines to.
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/panels/lfs_pattern_match.dart';

void main() {
  group('lfsPatternMatches', () {
    test('a pattern with no slash matches the base name at any depth', () {
      expect(lfsPatternMatches('logo.psd', '*.psd'), isTrue);
      expect(lfsPatternMatches('art/brand/logo.psd', '*.psd'), isTrue);
      expect(lfsPatternMatches('art/logo.png', '*.psd'), isFalse);
    });

    test('a pattern with a slash matches the whole path, anchored', () {
      expect(lfsPatternMatches('assets/logo.png', 'assets/*.png'), isTrue);
      // `*` does not cross a slash, so a nested file does not match.
      expect(lfsPatternMatches('assets/ui/logo.png', 'assets/*.png'), isFalse);
      expect(lfsPatternMatches('other/logo.png', 'assets/*.png'), isFalse);
    });

    test('** crosses slashes', () {
      expect(lfsPatternMatches('a/b/c/thing.bin', '**/*.bin'), isTrue);
      expect(lfsPatternMatches('thing.bin', '**/*.bin'), isTrue);
      expect(lfsPatternMatches('a/b/c.bin', 'a/**/c.bin'), isTrue);
      // `a/**/b` must also match `a/b` -- the slash after ** is optional.
      expect(lfsPatternMatches('a/c.bin', 'a/**/c.bin'), isTrue);
    });

    test('a trailing slash means everything under that directory', () {
      expect(lfsPatternMatches('models/big.onnx', 'models/'), isTrue);
      expect(lfsPatternMatches('models/v2/big.onnx', 'models/'), isTrue);
      expect(lfsPatternMatches('other/big.onnx', 'models/'), isFalse);
    });

    test('a leading slash only anchors at the repository root', () {
      expect(lfsPatternMatches('assets/logo.png', '/assets/*.png'), isTrue);
    });

    test('? matches exactly one non-slash character', () {
      expect(lfsPatternMatches('v1.bin', 'v?.bin'), isTrue);
      expect(lfsPatternMatches('v12.bin', 'v?.bin'), isFalse);
    });

    // Unsupported syntax matches nothing rather than guessing, so a group
    // reads 0 instead of claiming a wrong number.
    test('character classes and negation match nothing', () {
      expect(lfsPatternMatches('a.bin', '[ab].bin'), isFalse);
      expect(lfsPatternMatches('a.bin', '!*.txt'), isFalse);
    });

    test('an empty or whitespace pattern matches nothing', () {
      expect(lfsPatternMatches('a.bin', ''), isFalse);
      expect(lfsPatternMatches('a.bin', '   '), isFalse);
    });

    // A dot in a pattern is a literal, not a regex wildcard -- the whole
    // reason the glob is escaped before compiling.
    test('a dot is literal, not a regex wildcard', () {
      expect(lfsPatternMatches('axpsd', '*.psd'), isFalse);
    });
  });
}
