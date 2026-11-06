import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/app_bootstrap.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/repositories/gbm_bindings_provider.dart';
import 'package:gbm_flutter/features/app_lifecycle/dart_error_handlers.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_repo_session.dart';

class _Bindings extends FakeGbmBindings {
  final List<(String, String, String)> reported = <(String, String, String)>[];

  @override
  ReportExternalErrorDart get reportExternalError =>
      (Pointer<Utf8> where, Pointer<Utf8> summary, Pointer<Utf8> detail) =>
          reported.add((
            where.toDartString(),
            summary.toDartString(),
            detail.toDartString(),
          ));
}

/// Reads back what the scope [bootstrapApp] built provides.
class _Probe extends ConsumerWidget {
  const _Probe(this.seen);

  final List<Object> seen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    seen
      ..add(ref.read(gbmBindingsProvider))
      ..add(ref.read(sharedPreferencesProvider));
    return const SizedBox();
  }
}

void main() {
  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    prefs = await SharedPreferences.getInstance();
  });

  testWidgets('the handlers report through the same bindings the app reads', (
    WidgetTester tester,
  ) async {
    final _Bindings bindings = _Bindings();
    ExternalErrorReport? installedWith;
    final List<Object> seen = <Object>[];

    final Widget app = await bootstrapApp(
      openBindings: () => bindings,
      loadPrefs: () async => prefs,
      install: ({required ExternalErrorReport report}) {
        installedWith = report;
        return () {};
      },
      child: _Probe(seen),
    );
    await tester.pumpWidget(app);

    expect(seen, <Object>[same(bindings), same(prefs)]);
    installedWith!('FlutterError', 'on screen', 'in the file');
    expect(bindings.reported, <(String, String, String)>[
      ('FlutterError', 'on screen', 'in the file'),
    ]);
  });

  testWidgets(
    'a library that cannot be opened installs nothing and leaves the provider lazy',
    (WidgetTester tester) async {
      int installs = 0;
      final Widget app = await bootstrapApp(
        openBindings: () => throw ArgumentError('no library'),
        loadPrefs: () async => prefs,
        install: ({required ExternalErrorReport report}) {
          installs++;
          return () {};
        },
        child: const SizedBox(),
      );
      await tester.pumpWidget(app);

      expect(installs, 0);
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(SizedBox)),
      );
      expect(
        () => container.read(gbmBindingsProvider),
        throwsA(anything),
        reason: 'not overridden, so it opens the library itself, as before',
      );
    },
  );
}
