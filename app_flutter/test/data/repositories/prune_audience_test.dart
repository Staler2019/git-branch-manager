// `PruneAudience` 是「有沒有 UI 正在列這個 remote 的 prune 候選」這件事的 port，由
// 對話框宣告、由背景自動 prune 讀。這個檔案釘的是 token 語意：這些測試存在的理由是
// 前一版的閘門比對 **remote 名稱**，於是兩個列著同一個 remote 的對話框實例互相打開
// 對方的閘門。
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/repositories/prune_audience.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';

final RepoIdentity _identityA = RepoIdentity.forWorkDir('/test/a');
final RepoIdentity _identityB = RepoIdentity.forWorkDir('/test/b');

void main() {
  group('PruneAudienceRegistry', () {
    late PruneAudienceRegistry audience;

    setUp(() => audience = PruneAudienceRegistry());

    test('沒有任何對話框時不 hold 任何 remote', () {
      expect(audience.holdsRemote('origin'), isFalse);
      expect(audience.heldRemotes, isEmpty);
    });

    test('宣告之後 hold 那個 remote，釋放之後不再 hold', () {
      final Object token = Object();
      audience.register(token);
      audience.declare(token, 'origin');
      expect(audience.holdsRemote('origin'), isTrue);

      audience.release(token);
      expect(audience.holdsRemote('origin'), isFalse);
    });

    // 這一顆是整個 token 設計存在的理由。以 remote 名稱當 key 時，第一個實例的
    // dispose 會在第二個實例眼前打開閘門 -- 而使用者看著的那份清單正是第二個在列的。
    test('兩個實例列同一個 remote：第一個釋放後仍 hold，第二個釋放後才放開', () {
      final Object first = Object();
      final Object second = Object();
      audience.register(first);
      audience.declare(first, 'origin');
      audience.register(second);
      audience.declare(second, 'origin');

      audience.release(first);
      expect(audience.holdsRemote('origin'), isTrue, reason: '第二個實例還在列 origin');

      audience.release(second);
      expect(audience.holdsRemote('origin'), isFalse);
    });

    test('兩個實例列不同 remote：各自獨立', () {
      final Object a = Object();
      final Object b = Object();
      audience.register(a);
      audience.declare(a, 'origin');
      audience.register(b);
      audience.declare(b, 'upstream');

      expect(audience.heldRemotes, <String>{'origin', 'upstream'});

      audience.release(a);
      expect(audience.holdsRemote('origin'), isFalse);
      expect(audience.holdsRemote('upstream'), isTrue);
    });

    test('同一個實例換 remote：舊的不會永久卡住', () {
      final Object token = Object();
      audience.register(token);
      audience.declare(token, 'origin');
      audience.declare(token, 'upstream');

      expect(audience.holdsRemote('origin'), isFalse);
      expect(audience.holdsRemote('upstream'), isTrue);
    });

    // P4：對話框存在但還沒挑到 remote（一個沒有任何 remote 的 repo 就停在這裡，因為
    // `initState` 的 microtask 會提早 return）。這是正常的中間狀態，不是 race。
    test('只 register 沒 declare：不 hold 任何東西，釋放也不丟', () {
      final Object token = Object();
      audience.register(token);

      expect(audience.heldRemotes, isEmpty);
      expect(audience.holdsRemote('origin'), isFalse);
      expect(() => audience.release(token), returnsNormally);
    });

    // 前一版靠 `if (!mounted) return;` 擋這件事，那是時序上的防守；token 讓它變成
    // 結構上不可能 -- 一個已經釋放的 token 不再是這份 registry 的成員，所以它遲到的
    // 宣告無處可去，而不是留下一筆永遠沒人釋放的 hold。
    test('已釋放的 token 遲到宣告不成立', () {
      final Object token = Object();
      audience.register(token);
      audience.release(token);

      audience.declare(token, 'origin');

      expect(audience.holdsRemote('origin'), isFalse);
      expect(audience.heldRemotes, isEmpty);
    });

    test('從未 register 的 token 宣告不成立', () {
      audience.declare(Object(), 'origin');
      expect(audience.holdsRemote('origin'), isFalse);
    });

    test('釋放不認識的 token 是 no-op', () {
      final Object token = Object();
      audience.register(token);
      audience.declare(token, 'origin');

      audience.release(Object());

      expect(audience.holdsRemote('origin'), isTrue);
    });
  });

  group('release listener', () {
    test('放開一個 hold 會通知，拿走一個 hold 不會', () {
      final PruneAudienceRegistry audience = PruneAudienceRegistry();
      int calls = 0;
      audience.addReleaseListener(() => calls++);

      final Object token = Object();
      audience.register(token);
      audience.declare(token, 'origin');
      expect(calls, 0, reason: '拿走 hold 不是釋放');

      audience.release(token);
      expect(calls, 1);
    });

    test('換 remote 會通知，因為舊的那個被放開了', () {
      final PruneAudienceRegistry audience = PruneAudienceRegistry();
      int calls = 0;
      audience.addReleaseListener(() => calls++);

      final Object token = Object();
      audience.register(token);
      audience.declare(token, 'origin');
      audience.declare(token, 'upstream');

      expect(calls, 1);
    });

    test('另一個實例還握著時不通知', () {
      final PruneAudienceRegistry audience = PruneAudienceRegistry();
      int calls = 0;
      audience.addReleaseListener(() => calls++);

      final Object first = Object();
      final Object second = Object();
      for (final Object t in <Object>[first, second]) {
        audience.register(t);
        audience.declare(t, 'origin');
      }

      audience.release(first);
      expect(calls, 0, reason: 'origin 仍然被 second 握著');

      audience.release(second);
      expect(calls, 1);
    });

    test('移除函式會取消訂閱', () {
      final PruneAudienceRegistry audience = PruneAudienceRegistry();
      int calls = 0;
      final VoidCallback remove = audience.addReleaseListener(() => calls++);
      remove();

      final Object token = Object();
      audience.register(token);
      audience.declare(token, 'origin');
      audience.release(token);

      expect(calls, 0);
    });
  });

  group('pruneAudienceProvider', () {
    test('每個 RepoIdentity 一份，互不相干', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      final PruneAudienceRegistry a = container.read(
        pruneAudienceProvider(_identityA),
      );
      final PruneAudienceRegistry b = container.read(
        pruneAudienceProvider(_identityB),
      );

      expect(a, isNot(same(b)));

      final Object token = Object();
      a.register(token);
      a.declare(token, 'origin');

      expect(a.holdsRemote('origin'), isTrue);
      expect(b.holdsRemote('origin'), isFalse);
    });
  });
}
