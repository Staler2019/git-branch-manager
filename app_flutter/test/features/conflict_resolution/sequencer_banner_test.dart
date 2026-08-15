import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/repo_state.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/features/conflict_resolution/conflict_resolve_window.dart'
    show SequencerBanner;
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';

RepoState _stateWith({
  required int flags,
  int rebaseStep = 0,
  int rebaseTotal = 0,
}) {
  return RepoState(
    flags: flags,
    isClean: false,
    isSequencerOperation: true,
    rebaseStep: rebaseStep,
    rebaseTotal: rebaseTotal,
    rebaseOntoLabel: '',
    indexLocked: false,
    indexLockAgeSeconds: null,
    describe: '',
  );
}

Future<void> _pump(WidgetTester tester, RepoState state) {
  final identity = RepoIdentity(
    workDir: '/test/repo',
    gitDir: '/test/repo/.git',
  );
  return tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
        home: Scaffold(
          body: SequencerBanner(identity: identity, state: state),
        ),
      ),
    ),
  );
}

void main() {
  group('SequencerBanner', () {
    testWidgets('merge: shows label and Abort Merge button', (tester) async {
      await _pump(tester, _stateWith(flags: RepoStateFlags.merge));

      expect(find.text('Merge in progress'), findsOneWidget);
      expect(find.text('Abort Merge'), findsOneWidget);
    });

    testWidgets('cherry-pick: shows label, no Abort button', (tester) async {
      await _pump(tester, _stateWith(flags: RepoStateFlags.cherryPick));

      expect(find.text('Cherry-pick in progress'), findsOneWidget);
      expect(find.text('Abort Merge'), findsNothing);
    });

    testWidgets('revert: shows label, no Abort button', (tester) async {
      await _pump(tester, _stateWith(flags: RepoStateFlags.revert));

      expect(find.text('Revert in progress'), findsOneWidget);
      expect(find.text('Abort Merge'), findsNothing);
    });

    testWidgets(
      'rebase (rebaseMerge): shows label with step/total, no Abort button',
      (tester) async {
        await _pump(
          tester,
          _stateWith(
            flags: RepoStateFlags.rebaseMerge,
            rebaseStep: 3,
            rebaseTotal: 8,
          ),
        );

        expect(find.text('Rebase in progress (3/8)'), findsOneWidget);
        expect(find.text('Abort Merge'), findsNothing);
      },
    );

    testWidgets(
      'rebase (rebaseApply): shows label with step/total, no Abort button',
      (tester) async {
        await _pump(
          tester,
          _stateWith(
            flags: RepoStateFlags.rebaseApply,
            rebaseStep: 1,
            rebaseTotal: 4,
          ),
        );

        expect(find.text('Rebase in progress (1/4)'), findsOneWidget);
        expect(find.text('Abort Merge'), findsNothing);
      },
    );

    testWidgets('rebase without step/total omits the fraction suffix', (
      tester,
    ) async {
      await _pump(tester, _stateWith(flags: RepoStateFlags.rebaseMerge));

      expect(find.text('Rebase in progress'), findsOneWidget);
    });
  });
}
