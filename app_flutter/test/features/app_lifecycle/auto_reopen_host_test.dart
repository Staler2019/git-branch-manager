import 'dart:convert';
import 'dart:ffi';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/models/git_error.dart';
import 'package:gbm_flutter/data/models/operation_record.dart';
import 'package:gbm_flutter/data/repositories/auto_reopen_marker_repository.dart';
import 'package:gbm_flutter/data/repositories/gbm_bindings_provider.dart';
import 'package:gbm_flutter/data/repositories/recents_repository.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/data/repositories/window_log_repository.dart';
import 'package:gbm_flutter/features/app_lifecycle/auto_reopen_host.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_repo_session.dart';

const String _workDir = '/r/工作樹wt';
const String _logPath = '/logs/gbm-native-errors.log';

const RepoSessionState _refreshing = RepoSessionState(
  isOpen: true,
  isRefreshing: true,
);
const RepoSessionState _settled = RepoSessionState(isOpen: true);

class _LogPathBindings extends FakeGbmBindings {
  final List<int> _bytes = utf8.encode('{"path":"$_logPath"}');

  @override
  NativeErrorLogPathJsonDart get nativeErrorLogPathJson =>
      () => 0;

  @override
  LastResultJsonLenDart get lastResultJsonLen =>
      () => _bytes.length;

  @override
  LastResultJsonCopyDart get lastResultJsonCopy =>
      (Pointer<Uint8> out, int outLen) =>
          out.asTypedList(outLen).setAll(0, _bytes.take(outLen));
}

class _Harness {
  _Harness(this.store, this.container, this.sessions);

  final SharedPreferences store;
  final ProviderContainer container;

  /// Every session the providers created, by identity.
  final Map<RepoIdentity, FakeRepoSessionController> sessions;

  String? get marker => store.getString(AutoReopenMarkerRepository.key);
}

Future<_Harness> _pump(
  WidgetTester tester, {
  String? pending,
  String? skipped,
  RepoSessionState initial = _refreshing,
  Map<String, Object> prefs = const <String, Object>{},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final SharedPreferences store = await SharedPreferences.getInstance();
  final Map<RepoIdentity, FakeRepoSessionController> sessions =
      <RepoIdentity, FakeRepoSessionController>{};
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(store),
      gbmBindingsProvider.overrideWithValue(_LogPathBindings()),
      repoSessionProvider.overrideWith(
        (Ref ref, RepoIdentity identity) =>
            sessions[identity] = FakeRepoSessionController(identity, initial),
      ),
      if (pending != null) pendingAutoReopenProvider.overrideWithValue(pending),
      if (skipped != null) skippedAutoReopenProvider.overrideWithValue(skipped),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const AutoReopenHost(child: SizedBox()),
    ),
  );
  return _Harness(store, container, sessions);
}

List<GbmLogEntry> _rows(_Harness h) =>
    h.container.read(windowLogProvider).entries;

void main() {
  group('isFirstLoadSettled', () {
    test('open and still reading is not settled', () {
      expect(isFirstLoadSettled(_refreshing), isFalse);
    });

    test('open with the first read back is settled', () {
      expect(isFirstLoadSettled(_settled), isTrue);
    });

    test('an error is settled: the app survived it', () {
      expect(
        isFirstLoadSettled(
          const RepoSessionState(
            isRefreshing: true,
            lastError: GitError(
              code: 1,
              codeName: 'NotARepository',
              message: 'x',
              detail: '',
              argv: <String>[],
              exitCode: 1,
            ),
          ),
        ),
        isTrue,
      );
    });

    test('not open and no error is not settled', () {
      expect(isFirstLoadSettled(const RepoSessionState()), isFalse);
    });
  });

  group('the pending marker', () {
    testWidgets('is cleared when the first load settles', (tester) async {
      final _Harness h = await _pump(
        tester,
        pending: _workDir,
        prefs: <String, Object>{AutoReopenMarkerRepository.key: _workDir},
      );
      await tester.pump();
      expect(h.marker, _workDir, reason: 'still reading');

      h.sessions[RepoIdentity.forWorkDir(_workDir)]!.emit(_settled);
      await tester.pump();

      expect(h.marker, isNull);
    });

    testWidgets(
      'is cleared when the load had settled before the host mounted',
      (tester) async {
        final _Harness h = await _pump(
          tester,
          pending: _workDir,
          initial: _settled,
          prefs: <String, Object>{AutoReopenMarkerRepository.key: _workDir},
        );
        await tester.pump();

        expect(h.marker, isNull);
      },
    );

    testWidgets('watches only the pending repository', (tester) async {
      final _Harness h = await _pump(
        tester,
        pending: _workDir,
        prefs: <String, Object>{AutoReopenMarkerRepository.key: _workDir},
      );

      expect(h.sessions.keys, <RepoIdentity>[
        RepoIdentity.forWorkDir(_workDir),
      ]);
    });

    testWidgets('with nothing pending, no session is opened and the marker is '
        'never touched', (tester) async {
      final _Harness h = await _pump(
        tester,
        prefs: <String, Object>{
          'recents.repos': jsonEncode(<Object>[
            const RecentRepoEntry(
              workDir: _workDir,
              lastOpenedEpochMs: 1,
            ).toJson(),
          ]),
          AutoReopenMarkerRepository.key: 'left by someone else',
        },
      );
      await tester.pump();

      expect(h.sessions, isEmpty);
      expect(h.marker, 'left by someone else');
    });
  });

  group('the skipped row', () {
    testWidgets(
      'lands in the window Log once, naming the repository and file',
      (tester) async {
        final _Harness h = await _pump(tester, skipped: _workDir);
        await tester.pump();

        final List<GbmLogEntry> rows = _rows(h);
        expect(rows, hasLength(1));
        expect(rows.single.level, OperationLogLevel.error);
        expect(
          (rows.single as AppLogEntry).message,
          allOf(
            startsWith('Skipped reopening $_workDir:'),
            endsWith('(details: $_logPath)'),
          ),
        );

        // A rebuild of what is below the host does not log it again.
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: h.container,
            child: const AutoReopenHost(
              child: Text('x', textDirection: TextDirection.ltr),
            ),
          ),
        );
        await tester.pump();
        expect(_rows(h), hasLength(1));
      },
    );

    testWidgets('is not written when nothing was skipped', (tester) async {
      final _Harness h = await _pump(tester);
      await tester.pump();

      expect(_rows(h), isEmpty);
    });
  });
}
