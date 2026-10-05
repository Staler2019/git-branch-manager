import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/dialogs/repository_settings/repository_settings_dialog.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/fake_repo_session.dart';

const RepoIdentity _identity = RepoIdentity(
  workDir: '/tmp/repo',
  gitDir: '/tmp/repo/.git',
);

Future<void> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(prefs),
        repoSessionProvider(_identity).overrideWith(
          (ref) => FakeRepoSessionController(
            _identity,
            const RepoSessionState(isOpen: true),
          ),
        ),
      ],
      child: MaterialApp(
        theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
        home: const Scaffold(
          body: RepositorySettingsDialogContent(identity: _identity),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Color? _labelColor(WidgetTester tester, String label) =>
    tester.widget<Text>(find.text(label)).style!.color;

void main() {
  // The mockup's settings strip is `.gbm-tab`s, whose `:hover` turns the
  // label `--text-primary` and paints no fill. A hand-rolled InkWell instead
  // inherits `ThemeData.hoverColor`, a grey no real display shows, and leaves
  // the label as it was.
  testWidgets('an inactive tab\'s label turns textPrimary on hover', (
    tester,
  ) async {
    final GbmColors colors = tokensFor(GbmThemeVariant.darkTechnical);
    await _pump(tester);
    expect(_labelColor(tester, 'Remotes'), colors.textSecondary);

    final TestGesture mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: const Offset(799, 599));
    await mouse.moveTo(tester.getCenter(find.text('Remotes')));
    await tester.pump();

    expect(_labelColor(tester, 'Remotes'), colors.textPrimary);
    final InkWell ink = tester.widget<InkWell>(
      find
          .ancestor(of: find.text('Remotes'), matching: find.byType(InkWell))
          .first,
    );
    expect(ink.hoverColor, Colors.transparent);
  });
}
