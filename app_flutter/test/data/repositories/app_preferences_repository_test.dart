import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/external_app_entry.dart';
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
      // Spec page 06's Force push row: the confirmation is on until the user
      // turns it off.
      expect(p.confirmForcePush, isTrue);
      // Spec page 10's LOGRULES retention row.
      expect(p.logMemoryLimit, 2000);
      expect(p.logRetentionDays, 7);
      // The startup update check is on until the user turns it off.
      expect(p.autoUpdateCheckEnabled, isTrue);
      // No release has been skipped. Empty rather than null: `copyWith`
      // cannot clear a nullable field, and `AppVersion.tryParse('')` is
      // already null, so '' is the honest "none" for both readers.
      expect(p.skippedVersion, '');
      // Off, and that is the flip: every file view wrapped unconditionally
      // before this field existed, because a bare `Text` defaults to
      // `softWrap: true`. See the field's own doc comment.
      expect(p.softWrapEnabled, isFalse);
      // Developer flags (fix/refresh-ui-first-tiering): the two behaviour
      // flags default to the new behaviour so a fresh profile gets it
      // without visiting Preferences; the timing readout defaults off since
      // it is a debugging aid, not something every user wants painted on
      // the status bar.
      expect(p.showRefreshTimings, isFalse);
      expect(p.keepDiffDuringRefresh, isTrue);
      expect(p.tieredRefresh, isTrue);
      // LOG group: both off, like the timing readout beside them.
      expect(p.showLogTimeouts, isFalse);
      expect(p.showLogColumnHeaders, isFalse);
      // Ruling ⑪ (prepared-commit-message-spec.html): git's prepared message
      // replaces whatever the commit box holds, unless the user turns it off.
      expect(p.overwriteWithPreparedMessage, isTrue);
    });

    test('round-trips every field through SharedPreferences', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final AppPreferencesRepository repo = AppPreferencesRepository(prefs);

      const AppPreferences written = AppPreferences(
        autoFetchEnabled: true,
        autoFetchMinutes: 3,
        cherryPickAddsSourceLine: false,
        confirmForcePush: false,
        logMemoryLimit: 500,
        logRetentionDays: 30,
        autoUpdateCheckEnabled: false,
        skippedVersion: '9.9.9',
        softWrapEnabled: true,
        showRefreshTimings: true,
        keepDiffDuringRefresh: false,
        tieredRefresh: false,
        showLogTimeouts: true,
        showLogColumnHeaders: true,
        overwriteWithPreparedMessage: false,
      );
      await repo.write(written);

      final AppPreferences read = repo.read();
      expect(read.autoFetchEnabled, isTrue);
      expect(read.autoFetchMinutes, 3);
      expect(read.cherryPickAddsSourceLine, isFalse);
      expect(read.confirmForcePush, isFalse);
      expect(read.logMemoryLimit, 500);
      expect(read.logRetentionDays, 30);
      expect(read.autoUpdateCheckEnabled, isFalse);
      expect(read.skippedVersion, '9.9.9');
      expect(read.softWrapEnabled, isTrue);
      expect(read.showRefreshTimings, isTrue);
      expect(read.keepDiffDuringRefresh, isFalse);
      expect(read.tieredRefresh, isFalse);
      expect(read.showLogTimeouts, isTrue);
      expect(read.showLogColumnHeaders, isTrue);
      expect(read.overwriteWithPreparedMessage, isFalse);
    });

    // Written with the two LOG flags set differently, each way round: with
    // both true a key read from the wrong place still reads true.
    test('the two LOG flags are stored under their own keys', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final AppPreferencesRepository repo = AppPreferencesRepository(prefs);

      await repo.write(
        const AppPreferences(
          showLogTimeouts: true,
          showLogColumnHeaders: false,
        ),
      );
      expect(repo.read().showLogTimeouts, isTrue);
      expect(repo.read().showLogColumnHeaders, isFalse);

      await repo.write(
        const AppPreferences(
          showLogTimeouts: false,
          showLogColumnHeaders: true,
        ),
      );
      expect(repo.read().showLogTimeouts, isFalse);
      expect(repo.read().showLogColumnHeaders, isTrue);
    });

    test('copyWith changes one field and leaves the rest alone', () {
      const AppPreferences base = AppPreferences();
      final AppPreferences next = base.copyWith(confirmForcePush: false);

      expect(next.confirmForcePush, isFalse);
      expect(next.autoFetchMinutes, base.autoFetchMinutes);
      expect(next.logMemoryLimit, base.logMemoryLimit);
      expect(next.logRetentionDays, base.logRetentionDays);
    });
  });

  // open-with-apps-spec.html: the worktree panel's ▾ list. Ruling D4 --
  // one file-manager entry per platform until the user edits the list.
  // Settings removed by user ruling 「移除開關」 (and the earlier
  // 「Prune while fetching」): their stored values have no reader, so 「留著
  // 沒有意義」 -- opening Preferences' store clears them.
  group('AppPreferencesNotifier retired keys', () {
    const Map<String, Object> retired = <String, Object>{
      'appPrefs.recordManualOpens': false,
      'appPrefs.autoScanEnabled': true,
      'appPrefs.autoScanMinutes': 45,
      'appPrefs.globalGitignoreEnabled': true,
      'appPrefs.globalGitignorePath': '~/.config/git/ignore',
      'appPrefs.globalGitignoreSource': 'imported',
      'appPrefs.autoFetchPrune': true,
    };

    test('building the notifier removes every retired key and keeps the '
        'live ones', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        ...retired,
        'appPrefs.confirmForcePush': false,
        'unrelated.key': 'kept',
      });
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      final AppPreferencesNotifier notifier = AppPreferencesNotifier(
        AppPreferencesRepository(prefs),
      );
      addTearDown(notifier.dispose);

      for (final String key in retired.keys) {
        expect(prefs.containsKey(key), isFalse, reason: key);
      }
      expect(prefs.getBool('appPrefs.confirmForcePush'), isFalse);
      expect(prefs.getString('unrelated.key'), 'kept');
      expect(notifier.state.confirmForcePush, isFalse);
    });
  });

  group('AppPreferencesRepository.externalApps', () {
    Future<AppPreferencesRepository> repoWith(
      Map<String, Object> stored, {
      String os = 'macos',
    }) async {
      SharedPreferences.setMockInitialValues(stored);
      return AppPreferencesRepository(
        await SharedPreferences.getInstance(),
        operatingSystem: os,
      );
    }

    List<(String, String)> shape(List<ExternalAppEntry> apps) =>
        <(String, String)>[for (final e in apps) (e.label, e.command)];

    test(
      'defaults to the platform file manager when nothing is stored',
      () async {
        expect(
          shape((await repoWith(<String, Object>{})).read().externalApps),
          <(String, String)>[('Finder', 'open .')],
        );
        expect(
          shape(
            (await repoWith(
              <String, Object>{},
              os: 'windows',
            )).read().externalApps,
          ),
          <(String, String)>[('Explorer', 'explorer .')],
        );
        expect(
          shape(
            (await repoWith(
              <String, Object>{},
              os: 'linux',
            )).read().externalApps,
          ),
          <(String, String)>[('File manager', 'xdg-open .')],
        );
      },
    );

    test(
      'falls back to the defaults when the stored value is not a list',
      () async {
        for (final String bad in <String>['{not json', '{"a":1}', '"x"']) {
          expect(
            shape(
              (await repoWith(<String, Object>{'appPrefs.externalApps': bad}))
                  .read()
                  .externalApps,
            ),
            <(String, String)>[('Finder', 'open .')],
            reason: bad,
          );
        }
      },
    );

    // An entry the factory rejects is dropped on its own; the rest of the
    // user's list survives (Q3: storage gets no rule create does not apply).
    test('drops only the entries the factory rejects', () async {
      final AppPreferencesRepository repo = await repoWith(<String, Object>{
        'appPrefs.externalApps': jsonEncode(<Object>[
          <String, String>{'id': 'a', 'label': 'Bad', 'command': '-x'},
          <String, String>{
            'id': 'b',
            'label': 'Bad',
            'command': "open 'a {path}'",
          },
          <String, String>{'id': 'c', 'label': 'Rider', 'command': 'rider .'},
          'not an object',
        ]),
      });
      expect(shape(repo.read().externalApps), <(String, String)>[
        ('Rider', 'rider .'),
      ]);
    });

    test('an empty stored list stays empty', () async {
      expect(
        (await repoWith(<String, Object>{'appPrefs.externalApps': '[]'}))
            .read()
            .externalApps,
        isEmpty,
      );
    });

    test('writes the list and reads it back in order', () async {
      final AppPreferencesRepository repo = await repoWith(<String, Object>{});
      ExternalAppEntry make(String id, String label, String command) =>
          (ExternalAppEntry.create(
            label: label,
            command: command,
            newId: () => id,
          ) as ExternalAppEntryAccepted).entry;
      await repo.write(
        repo.read().copyWith(
          externalApps: <ExternalAppEntry>[
            make('1', 'VS Code', 'code {path}'),
            make('2', 'Rider', 'rider .'),
          ],
        ),
      );
      final List<ExternalAppEntry> back = repo.read().externalApps;
      expect(shape(back), <(String, String)>[
        ('VS Code', 'code {path}'),
        ('Rider', 'rider .'),
      ]);
      expect(back.map((e) => e.id), <String>['1', '2']);
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
