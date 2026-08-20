import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/dialogs/branch_name_validation.dart';

/// The rules here are the ones a user hits by accident, not a reimplementation
/// of `git check-ref-format` -- core still validates before git runs (see
/// `RefStore::isValidBranchName`). These exist so the button can explain
/// itself while typing, which is what spec page 13's RENAMEVALID table asks
/// for ("即時，不等到按 Rename").
void main() {
  const List<String> existing = <String>['main', 'feature/lane-allocator'];

  group('branchNameError', () {
    test('returns null for a name that is free and well-formed', () {
      expect(branchNameError('feature/new', existingNames: existing), isNull);
    });

    test('returns null for an empty name so no red text appears while the '
        'field is still untouched (RENAMEVALID: 空白 -> disabled, 不出現錯誤紅字)', () {
      expect(branchNameError('', existingNames: existing), isNull);
      expect(branchNameError('   ', existingNames: existing), isNull);
    });

    test('names the colliding branch when one already exists', () {
      final String? error = branchNameError(
        'feature/lane-allocator',
        existingNames: existing,
      );
      expect(error, isNotNull);
      expect(error, contains('feature/lane-allocator'));
    });

    test('trims before comparing, so trailing whitespace still collides', () {
      expect(branchNameError('main  ', existingNames: existing), isNotNull);
    });

    test('rejects every character git forbids', () {
      for (final String name in <String>[
        'has space',
        'tilde~',
        'caret^',
        'colon:',
        'question?',
        'star*',
        'bracket[',
        r'backslash\',
      ]) {
        expect(
          branchNameError(name, existingNames: existing),
          isNotNull,
          reason: '"$name" should be rejected',
        );
      }
    });

    test('rejects the structural cases git also refuses', () {
      for (final String name in <String>[
        '/leading-slash',
        'trailing-slash/',
        '.leading-dot',
        'trailing-dot.',
        'double..dot',
        'ends-in.lock',
      ]) {
        expect(
          branchNameError(name, existingNames: existing),
          isNotNull,
          reason: '"$name" should be rejected',
        );
      }
    });
  });
}
