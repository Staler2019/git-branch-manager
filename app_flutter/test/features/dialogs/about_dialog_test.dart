import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/app_version.dart';
import 'package:gbm_flutter/data/repositories/build_version_repository.dart';
import 'package:gbm_flutter/features/dialogs/about/about_dialog.dart';

import '../../support/pump_app.dart';

void main() {
  group('AboutDialogContent', () {
    testWidgets('shows the running release version', (
      WidgetTester tester,
    ) async {
      await pumpGbmWidget(
        tester,
        child: const AboutDialogContent(),
        overrides: <Override>[
          buildVersionProvider.overrideWithValue(const AppVersion(0, 30, 0)),
        ],
      );

      expect(find.text('Version 0.30.0'), findsOneWidget);
    });

    // The `flutter run` case. Rendering "Version 0.0.0" here would be a lie
    // about which build is running, and the update flow reads the same
    // provider to decide it must not offer to replace this build.
    testWidgets('names a developer build instead of inventing a version', (
      WidgetTester tester,
    ) async {
      await pumpGbmWidget(
        tester,
        child: const AboutDialogContent(),
        overrides: <Override>[buildVersionProvider.overrideWithValue(null)],
      );

      expect(find.text('Development build'), findsOneWidget);
      expect(find.textContaining('0.0.0'), findsNothing);
    });

    testWidgets('keeps the existing description', (WidgetTester tester) async {
      await pumpGbmWidget(
        tester,
        child: const AboutDialogContent(),
        overrides: <Override>[
          buildVersionProvider.overrideWithValue(const AppVersion(1, 2, 3)),
        ],
      );

      expect(
        find.text('A fast Git client for very large repositories.'),
        findsOneWidget,
      );
    });
  });
}
