// The prepared-message episode survives a restart (使用者 2026-10-10):
//
//   上次（磁碟上的 episode）  這次重開                → 框
//   有                        pending 且同一筆         → 沿用
//   有                        pending 且不同筆         → 重抓、覆蓋（開關關＋框非空則不覆蓋）
//   有                        沒有 pending             → 清空
//
// "A restart" is a new ProviderContainer over the same SharedPreferences,
// as in working_copy_draft_repository_test.dart.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/prepared_message_policy.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/working_copy_draft_repository.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const RepoIdentity _repo = RepoIdentity(workDir: '/repo', gitDir: '/repo/.git');
const String _draftKey = 'workingCopyDraft:/repo';
const String _episodeKey = 'workingCopyPreparedEpisode:/repo';
const String _mergeRaw = "Merge branch 'topic'\n\nmerged body";

/// In-memory preferences whose writes can be held open, so a test can stop
/// the draft's writer between its two writes.
class _HoldablePrefs implements SharedPreferences {
  final Map<String, List<String>> lists = <String, List<String>>{};
  final List<String> ops = <String>[];
  Completer<void>? gate;

  Future<bool> _land(String op, void Function() apply) async {
    ops.add(op);
    final Completer<void>? held = gate;
    if (held != null) await held.future;
    apply();
    return true;
  }

  @override
  List<String>? getStringList(String key) => lists[key];

  @override
  Future<bool> setStringList(String key, List<String> value) => _land(
    'set $key ${value.first}',
    () => lists[key] = List<String>.of(value),
  );

  @override
  Future<bool> remove(String key) =>
      _land('remove $key', () => lists.remove(key));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _HoldablePrefs prefs;
  setUp(() => prefs = _HoldablePrefs());

  late ProviderContainer last;

  /// Opens the repository again: a fresh container over the same preferences.
  WorkingCopyDraftController open() {
    last = ProviderContainer(
      overrides: <Override>[sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(last.dispose);
    return last.read(workingCopyDraftProvider(_repo).notifier);
  }

  /// The draft of the most recently opened repository.
  WorkingCopyDraft now() => last.read(workingCopyDraftProvider(_repo));

  WorkingCopyDraft reopened() {
    open();
    return now();
  }

  PreparedMessageAction pass(
    WorkingCopyDraftController n, {
    bool pending = true,
    PreparedReplyStatus reply = PreparedReplyStatus.none,
    String raw = _mergeRaw,
    String head = 'deadbeef',
    bool overwrite = true,
    bool repoStateKnown = true,
  }) {
    final List<String> lines = raw.split('\n');
    return n.reconcilePreparedMessage(
      pending: pending,
      reply: reply,
      summary: lines.first,
      description: lines.skip(2).join('\n'),
      raw: reply == PreparedReplyStatus.message ? raw : '',
      head: head,
      overwrite: overwrite,
      repoStateKnown: repoStateKnown,
    );
  }

  /// Settles every queued write.
  Future<void> flush() async {
    for (int i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// A merge filled the box over 'mine' / 'my body', and the app closed.
  Future<void> mergeFilledThenClosed({bool overwrite = true}) async {
    final WorkingCopyDraftController n = open();
    n.updateSummary('mine');
    n.updateDescription('my body');
    pass(n);
    pass(n, reply: PreparedReplyStatus.message, overwrite: overwrite);
    await flush();
  }

  group('reopening on the same merge', () {
    test('keeps an edited message', () async {
      final WorkingCopyDraftController first = open();
      first.updateSummary('mine');
      pass(first);
      pass(first, reply: PreparedReplyStatus.message);
      first.updateDescription('my own words');
      await flush();

      final WorkingCopyDraftController n = open();
      expect(pass(n), PreparedMessageAction.revalidate);
      expect(
        pass(n, reply: PreparedReplyStatus.message),
        PreparedMessageAction.keepValidated,
      );
      expect(now().description, 'my own words');
    });

    test('still restores the pre-merge text on Abort', () async {
      await mergeFilledThenClosed();

      final WorkingCopyDraftController n = open();
      pass(n);
      pass(n, reply: PreparedReplyStatus.message);
      expect(pass(n, pending: false), PreparedMessageAction.restoreAndEnd);
      expect(now().summary, 'mine');
      await flush();
      expect(prefs.lists[_episodeKey], isNull);
    });

    // P1 of the epoch-4 review: a kept box has a same-merge key too.
    test('keeps a box the switch kept', () async {
      await mergeFilledThenClosed(overwrite: false);

      final WorkingCopyDraftController n = open();
      pass(n, overwrite: false);
      expect(
        pass(n, reply: PreparedReplyStatus.message, overwrite: false),
        PreparedMessageAction.keepValidated,
      );
      expect(now().summary, 'mine');
    });

    // 使用者 2026-10-10: 「HEAD 沒變就當同一筆，沿用框」.
    test('keeps the box after a failed read when HEAD is the same', () async {
      final WorkingCopyDraftController first = open();
      first.updateSummary('mine');
      pass(first);
      pass(first, reply: PreparedReplyStatus.failed);
      await flush();

      final WorkingCopyDraftController n = open();
      pass(n);
      expect(
        pass(n, reply: PreparedReplyStatus.message),
        PreparedMessageAction.keepValidated,
      );
      expect(now().summary, 'mine');
    });
  });

  group('reopening on a different merge', () {
    test('a new HEAD fetches again, with nothing to restore', () async {
      await mergeFilledThenClosed();

      final WorkingCopyDraftController n = open();
      pass(n, head: 'cafebabe');
      expect(
        pass(n, reply: PreparedReplyStatus.message, head: 'cafebabe'),
        PreparedMessageAction.replaceAsNew,
      );
      expect(pass(n, pending: false), PreparedMessageAction.restoreAndEnd);
      expect(now().summary, isEmpty);
    });

    test('a new message on the same HEAD fetches again', () async {
      await mergeFilledThenClosed();

      final WorkingCopyDraftController n = open();
      pass(n);
      expect(
        pass(
          n,
          reply: PreparedReplyStatus.message,
          raw: "Merge branch 'other'",
        ),
        PreparedMessageAction.replaceAsNew,
      );
      expect(now().summary, "Merge branch 'other'");
    });

    // 使用者 2026-10-10: 「如果開關關著的，不要覆蓋」.
    test('with the switch off, a non-empty box is kept', () async {
      await mergeFilledThenClosed();

      final WorkingCopyDraftController n = open();
      pass(n, head: 'cafebabe', overwrite: false);
      expect(
        pass(
          n,
          reply: PreparedReplyStatus.message,
          head: 'cafebabe',
          overwrite: false,
        ),
        PreparedMessageAction.keep,
      );
      expect(now().summary, "Merge branch 'topic'");
    });
  });

  test('reopening with nothing pending clears the box and the key', () async {
    await mergeFilledThenClosed();

    final WorkingCopyDraftController n = open();
    expect(pass(n, pending: false), PreparedMessageAction.clearAndEnd);
    expect(now().summary, isEmpty);
    await flush();
    expect(prefs.lists[_episodeKey], isNull);
    expect(reopened().summary, isEmpty);
  });

  // P3 of the epoch-4 review: unknown is not "nothing pending".
  test('nothing is decided while RepoState is unknown', () async {
    await mergeFilledThenClosed();

    final WorkingCopyDraftController n = open();
    expect(
      pass(n, pending: false, repoStateKnown: false),
      PreparedMessageAction.nothing,
    );
    await flush();
    expect(now().summary, "Merge branch 'topic'");
    expect(prefs.lists[_episodeKey], isNotNull);
    expect(pass(n), PreparedMessageAction.revalidate);
  });

  // REVISE #2 of epoch 1: an episode still waiting for its reply is not
  // written, so reopening asks again instead of waiting forever.
  test('an episode closed before its reply asks again', () async {
    final WorkingCopyDraftController first = open();
    first.updateSummary('mine');
    pass(first);
    first.updateDescription('typed while waiting');
    await flush();
    expect(prefs.lists[_episodeKey], isNull);

    final WorkingCopyDraftController n = open();
    expect(pass(n), PreparedMessageAction.startAndRequest);
    expect(
      pass(n, reply: PreparedReplyStatus.message),
      PreparedMessageAction.replace,
    );
  });

  // The epoch-5 review: HEAD is half of the same-merge key, and refs arrive
  // after RepoState.
  test('a reply before refs waits, then stores a real HEAD', () async {
    final WorkingCopyDraftController first = open();
    first.updateSummary('mine');
    pass(first, head: '');
    expect(
      pass(first, reply: PreparedReplyStatus.message, head: ''),
      PreparedMessageAction.nothing,
    );
    await flush();
    expect(prefs.lists[_episodeKey], isNull);
    expect(
      pass(first, reply: PreparedReplyStatus.message),
      PreparedMessageAction.replace,
    );
    first.updateDescription('my own words');
    await flush();
    expect(prefs.lists[_episodeKey]![5], 'deadbeef');

    final WorkingCopyDraftController n = open();
    pass(n);
    expect(
      pass(n, reply: PreparedReplyStatus.message),
      PreparedMessageAction.keepValidated,
    );
    expect(now().description, 'my own words');
  });

  group('a stored episode of the wrong shape reads as none', () {
    List<String> valid() => <String>[
      'mine',
      '',
      '1',
      "Merge branch 'topic'",
      'merged body',
      'deadbeef',
      _mergeRaw,
    ];

    test('the valid shape reads back', () {
      prefs.lists[_episodeKey] = valid();
      expect(reopened().preparedEpisodeActive, isTrue);
    });

    test('six entries', () {
      prefs.lists[_episodeKey] = valid().sublist(0, 6);
      expect(reopened().preparedEpisodeActive, isFalse);
    });

    test('a hasAutofill that is not 1 or 0', () {
      prefs.lists[_episodeKey] = valid()..[2] = 'x';
      expect(reopened().preparedEpisodeActive, isFalse);
    });
  });

  test('a two-entry draft from before still reads', () {
    prefs.lists[_draftKey] = <String>['old subject', 'old body'];
    expect(reopened().summary, 'old subject');
  });

  group('every half-written state keeps the user\'s text', () {
    // Write order: starting or updating an episode writes it before the
    // draft; ending one deletes it before the draft.
    test('starting writes the episode first', () async {
      final WorkingCopyDraftController n = open();
      n.updateSummary('mine');
      await flush();
      prefs.ops.clear();
      pass(n);
      pass(n, reply: PreparedReplyStatus.message);
      await flush();
      expect(prefs.ops.first, startsWith('set $_episodeKey'));
    });

    test('ending deletes the episode first', () async {
      await mergeFilledThenClosed();
      final WorkingCopyDraftController n = open();
      pass(n);
      pass(n, reply: PreparedReplyStatus.message);
      await flush();
      prefs.ops.clear();
      pass(n, pending: false);
      await flush();
      expect(prefs.ops.first, 'remove $_episodeKey');
    });

    test('only the episode landed: reopening keeps the old text', () async {
      prefs.lists[_draftKey] = <String>['mine', 'my body'];
      prefs.lists[_episodeKey] = <String>[
        'mine',
        'my body',
        '1',
        "Merge branch 'topic'",
        'merged body',
        'deadbeef',
        _mergeRaw,
      ];

      final WorkingCopyDraftController n = open();
      pass(n);
      pass(n, reply: PreparedReplyStatus.message);
      pass(n, pending: false);
      expect(now().summary, 'mine');
    });

    test('only the deletion landed: reopening keeps the merge text', () {
      prefs.lists[_draftKey] = <String>["Merge branch 'topic'", 'merged body'];

      final WorkingCopyDraftController n = open();
      expect(pass(n, pending: false), PreparedMessageAction.nothing);
      expect(now().summary, "Merge branch 'topic'");
    });

    // The epoch-2 review: reset() used to write around the queue.
    test('a reset between the two writes leaves nothing behind', () async {
      final WorkingCopyDraftController n = open();
      n.updateSummary('mine');
      await flush();
      prefs.gate = Completer<void>();
      pass(n);
      pass(n, reply: PreparedReplyStatus.message);
      await Future<void>.delayed(Duration.zero);
      expect(prefs.ops.last, startsWith('set $_episodeKey'));

      n.commitSubmitted(0);
      n.commitLanded();
      final int resetAt = prefs.ops.length;
      final Completer<void> held = prefs.gate!;
      prefs.gate = null;
      held.complete();
      await flush();

      expect(prefs.lists[_episodeKey], isNull);
      // Not even briefly: a crash after a stale write would bring the
      // committed message back on the next launch.
      expect(
        prefs.ops
            .skip(resetAt)
            .where((String op) => op.startsWith('set $_draftKey')),
        isEmpty,
      );
      open();
      expect(now().summary, isEmpty);
      expect(now().preparedEpisodeActive, isFalse);
    });
  });
}
