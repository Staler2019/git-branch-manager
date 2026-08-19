import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/repositories/app_preferences_repository.dart';
import 'package:gbm_flutter/data/repositories/chrome_visibility_repository.dart';
import 'package:gbm_flutter/data/repositories/panel_layout_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppPreferencesRepository', () {
    test('reads the spec defaults when nothing is stored', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final AppPreferences p = AppPreferencesRepository(prefs).read();

      // Spec page 11 item 9: auto-fetch defaults to every 10 minutes.
      expect(p.autoFetchMinutes, 10);
      expect(p.autoFetchEnabled, isFalse);
      // Spec page 11 item 6: recording manual opens is on by default.
      expect(p.recordManualOpens, isTrue);
      // Spec page 06's Force push row: the confirmation is on until the user
      // turns it off.
      expect(p.confirmForcePush, isTrue);
      // Spec page 10's LOGRULES retention row.
      expect(p.logMemoryLimit, 2000);
      expect(p.logRetentionDays, 7);
      // Nothing has been imported yet -- see the field's own doc comment for
      // why detection is not wired up this round.
      expect(p.globalGitignoreSource, '');
    });

    test('round-trips every field through SharedPreferences', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final AppPreferencesRepository repo = AppPreferencesRepository(prefs);

      const AppPreferences written = AppPreferences(
        autoFetchEnabled: true,
        autoFetchMinutes: 3,
        autoFetchPrune: true,
        recordManualOpens: false,
        autoScanEnabled: true,
        autoScanMinutes: 45,
        globalGitignoreEnabled: true,
        globalGitignorePath: '~/.config/git/ignore',
        globalGitignoreSource: 'imported',
        cherryPickAddsSourceLine: false,
        confirmForcePush: false,
        logMemoryLimit: 500,
        logRetentionDays: 30,
      );
      await repo.write(written);

      final AppPreferences read = repo.read();
      expect(read.autoFetchEnabled, isTrue);
      expect(read.autoFetchMinutes, 3);
      expect(read.autoFetchPrune, isTrue);
      expect(read.recordManualOpens, isFalse);
      expect(read.autoScanEnabled, isTrue);
      expect(read.autoScanMinutes, 45);
      expect(read.globalGitignoreEnabled, isTrue);
      expect(read.globalGitignorePath, '~/.config/git/ignore');
      expect(read.globalGitignoreSource, 'imported');
      expect(read.cherryPickAddsSourceLine, isFalse);
      expect(read.confirmForcePush, isFalse);
      expect(read.logMemoryLimit, 500);
      expect(read.logRetentionDays, 30);
    });

    test('copyWith changes one field and leaves the rest alone', () {
      const AppPreferences base = AppPreferences();
      final AppPreferences next = base.copyWith(confirmForcePush: false);

      expect(next.confirmForcePush, isFalse);
      expect(next.autoFetchMinutes, base.autoFetchMinutes);
      expect(next.recordManualOpens, base.recordManualOpens);
      expect(next.logRetentionDays, base.logRetentionDays);
    });
  });

  group('ChromeVisibilityRepository', () {
    test('both toggles default to visible', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final ChromeVisibilityRepository repo = ChromeVisibilityRepository(prefs);

      expect(repo.readStatusBarVisible(), isTrue);
      expect(repo.readCommitDetailVisible(), isTrue);
    });

    test('persists each toggle independently', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final ChromeVisibilityRepository repo = ChromeVisibilityRepository(prefs);

      await repo.writeStatusBarVisible(false);
      expect(repo.readStatusBarVisible(), isFalse);
      expect(
        repo.readCommitDetailVisible(),
        isTrue,
        reason: 'hiding the status bar must not hide the commit detail',
      );
    });
  });

  group('PanelLayoutRepository.clear', () {
    test('drops splitter sizes and nothing else', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'panelLayout.main.sidebar': '[250.0]',
        'panelLayout.cw.panes': '[1.0,1.12,1.0]',
        'fileListViewMode': 'tree',
        'appPrefs.confirmForcePush': false,
      });
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final PanelLayoutRepository repo = PanelLayoutRepository(prefs);

      expect(repo.read('main.sidebar'), <double>[250.0]);
      await repo.clear();

      expect(repo.read('main.sidebar'), isNull);
      expect(repo.read('cw.panes'), isNull);
      expect(
        prefs.getString('fileListViewMode'),
        'tree',
        reason: 'a layout reset must not reset unrelated preferences',
      );
      expect(prefs.getBool('appPrefs.confirmForcePush'), isFalse);
    });
  });
}
