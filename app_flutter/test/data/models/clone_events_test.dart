// The two clone-job payloads gbm_capi.h documents for
// GBM_EVENT_CLONE_PROGRESS and GBM_EVENT_CLONE_FINISHED.
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/clone_events.dart';

void main() {
  group('CloneProgress', () {
    test('decodes both phases', () {
      final CloneProgress receiving = CloneProgress.fromJson(<String, dynamic>{
        'phase': 'receiving',
        'current': 12480,
        'total': 31206,
      });
      expect(receiving.phase, ClonePhase.receiving);
      expect(receiving.current, 12480);
      expect(receiving.total, 31206);
      expect(
        CloneProgress.fromJson(<String, dynamic>{
          'phase': 'resolving',
          'current': 1,
          'total': 2,
        }).phase,
        ClonePhase.resolving,
      );
    });

    // W-D7: the label names the phase in git's own words.
    test('label is git\'s phase name with grouped counts', () {
      expect(
        const CloneProgress(
          phase: ClonePhase.receiving,
          current: 12480,
          total: 31206,
        ).label,
        'receiving objects 12,480 / 31,206',
      );
      expect(
        const CloneProgress(
          phase: ClonePhase.resolving,
          current: 3912,
          total: 20477,
        ).label,
        'resolving deltas 3,912 / 20,477',
      );
      expect(
        const CloneProgress(
          phase: ClonePhase.receiving,
          current: 7,
          total: 1234567,
        ).label,
        'receiving objects 7 / 1,234,567',
      );
    });
  });

  group('CloneFinished', () {
    test('success', () {
      final CloneFinished f = CloneFinished.fromJson(<String, dynamic>{
        'ok': true,
        'error': null,
        'removedPath': null,
        'removalError': null,
      });
      expect(f.ok, isTrue);
      expect(f.error, isNull);
      expect(f.removedPath, isNull);
      expect(f.removalError, isNull);
    });

    test('cancelled with the destination removed', () {
      final CloneFinished f = CloneFinished.fromJson(<String, dynamic>{
        'ok': false,
        'error': <String, dynamic>{
          'code': 9,
          'codeName': 'Cancelled',
          'message': 'Cancelled',
          'detail': '',
          'argv': <String>[],
          'exitCode': 0,
        },
        'removedPath': '/Users/alice/src/design-tokens',
        'removalError': null,
      });
      expect(f.ok, isFalse);
      expect(f.error?.codeName, 'Cancelled');
      expect(f.removedPath, '/Users/alice/src/design-tokens');
    });

    test('a removal that stopped short says why', () {
      final CloneFinished f = CloneFinished.fromJson(<String, dynamic>{
        'ok': false,
        'error': null,
        'removedPath': null,
        'removalError': 'Permission denied',
      });
      expect(f.removalError, 'Permission denied');
    });
  });
}
