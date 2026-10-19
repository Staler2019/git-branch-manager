import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/app_action_cancel_token.dart';

void main() {
  test(
    'cancel is seen by isCancelled, whenCancelled and throwIfCancelled',
    () async {
      final AppActionCancelToken token = AppActionCancelToken();
      expect(token.isCancelled, isFalse);
      token.throwIfCancelled();

      token.cancel();
      token.cancel();

      expect(token.isCancelled, isTrue);
      await token.whenCancelled;
      expect(
        token.throwIfCancelled,
        throwsA(isA<AppActionCancelledException>()),
      );
    },
  );

  test('none can never be cancelled', () {
    AppActionCancelToken.none.cancel();
    expect(AppActionCancelToken.none.isCancelled, isFalse);
    AppActionCancelToken.none.throwIfCancelled();
  });
}
