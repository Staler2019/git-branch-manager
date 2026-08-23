import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/services/update_installer.dart';
import 'package:gbm_flutter/features/update/update_leftover_sweep.dart';

/// Records the request instead of touching the filesystem.
///
/// A real installer would read `Directory.systemTemp` -- the machine's
/// actual temp directory -- and delete from it, so a widget test using one
/// would have side effects on the developer's machine. What the sweep
/// *does* is pinned by `update_leftover_sweep_test.dart` under
/// `test/data/services/`; what this tier owns is that it is asked for at
/// all.
class _RecordingInstaller extends UpdateInstaller {
  const _RecordingInstaller(this.calls);

  final List<String> calls;

  @override
  Future<void> sweepUpdateLeftovers({
    Directory? tempDir,
    DateTime Function()? now,
  }) async {
    calls.add('sweep');
  }
}

Future<List<String>> _pump(
  WidgetTester tester, {
  Duration delay = Duration.zero,
}) async {
  final List<String> calls = <String>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        updateInstallerProvider.overrideWithValue(_RecordingInstaller(calls)),
      ],
      child: MaterialApp(
        home: UpdateLeftoverSweep(
          delay: delay,
          child: const Scaffold(body: Text('app')),
        ),
      ),
    ),
  );
  return calls;
}

void main() {
  group('UpdateLeftoverSweep', () {
    testWidgets('sweeps once, after the delay', (WidgetTester tester) async {
      final List<String> calls = await _pump(
        tester,
        delay: const Duration(seconds: 3),
      );

      expect(calls, isEmpty);

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      // Counted, not `contains`: a second sweep would mean two timers, and
      // `.any(...)` cannot see that.
      expect(calls, <String>['sweep']);
    });

    testWidgets('renders its child unchanged', (WidgetTester tester) async {
      await _pump(tester);
      await tester.pumpAndSettle();

      expect(find.text('app'), findsOneWidget);
    });

    testWidgets('closing before the delay cancels the sweep', (
      WidgetTester tester,
    ) async {
      final List<String> calls = await _pump(
        tester,
        delay: const Duration(seconds: 3),
      );

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(calls, isEmpty);
    });
  });
}
