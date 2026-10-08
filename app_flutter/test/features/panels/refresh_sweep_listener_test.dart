// A panel whose data is not in the focus/F5 sweep re-reads it itself, but
// only while it is on screen: once per new sweep, never for the sweep that
// was already stamped when it mounted (its own initState read covers that),
// and never after it is gone.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/refresh_timings.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/panels/refresh_sweep_listener.dart';

import '../../support/fake_repo_session.dart';

final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/repo');

class _Listening extends ConsumerWidget {
  const _Listening(this.onSweep);

  final VoidCallback onSweep;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    listenToRefreshSweep(ref, _identity, onSweep);
    return const SizedBox();
  }
}

Future<(FakeRepoSessionController, ValueNotifier<bool>)> _pump(
  WidgetTester tester,
  VoidCallback onSweep,
) async {
  final FakeRepoSessionController fake = FakeRepoSessionController(
    _identity,
    RepoSessionState(
      isOpen: true,
      refreshTimings: RefreshTimings(focusAt: DateTime(2026, 10, 8, 9)),
    ),
  );
  final ValueNotifier<bool> mounted = ValueNotifier<bool>(true);
  addTearDown(mounted.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        repoSessionProvider(_identity).overrideWith((ref) => fake),
      ],
      child: ValueListenableBuilder<bool>(
        valueListenable: mounted,
        builder: (context, isMounted, _) =>
            isMounted ? _Listening(onSweep) : const SizedBox(),
      ),
    ),
  );
  return (fake, mounted);
}

void _startSweep(FakeRepoSessionController fake, int minute) {
  fake.emit(
    fake.state.copyWith(
      refreshTimings: RefreshTimings(focusAt: DateTime(2026, 10, 8, 9, minute)),
    ),
  );
}

void main() {
  testWidgets('a new sweep while mounted calls back exactly once', (
    WidgetTester tester,
  ) async {
    int calls = 0;
    final (FakeRepoSessionController fake, _) = await _pump(
      tester,
      () => calls++,
    );
    expect(calls, 0, reason: 'the sweep stamped before mount is not new');

    _startSweep(fake, 1);
    await tester.pump();
    expect(calls, 1);

    _startSweep(fake, 2);
    await tester.pump();
    expect(calls, 2);
  });

  testWidgets('a state change that is not a new sweep does not call back', (
    WidgetTester tester,
  ) async {
    int calls = 0;
    final (FakeRepoSessionController fake, _) = await _pump(
      tester,
      () => calls++,
    );

    fake.emit(
      fake.state.copyWith(
        refreshTimings: fake.state.refreshTimings.stampBackgroundDoneIfAbsent(
          DateTime(2026, 10, 8, 9, 5),
        ),
      ),
    );
    await tester.pump();

    expect(calls, 0);
  });

  testWidgets('after unmount a new sweep does not call back', (
    WidgetTester tester,
  ) async {
    int calls = 0;
    final (FakeRepoSessionController fake, ValueNotifier<bool> mounted) =
        await _pump(tester, () => calls++);

    mounted.value = false;
    await tester.pump();
    _startSweep(fake, 1);
    await tester.pump();

    expect(calls, 0);
  });
}
