import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/repositories/auto_reopen_marker_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<SharedPreferences> prefs([
    Map<String, Object> values = const <String, Object>{},
  ]) {
    SharedPreferences.setMockInitialValues(values);
    return SharedPreferences.getInstance();
  }

  test('nothing pending until set', () async {
    expect(AutoReopenMarkerRepository(await prefs()).read(), isNull);
  });

  test('set is read back, by this run and the next', () async {
    final SharedPreferences store = await prefs();
    await AutoReopenMarkerRepository(store).set('/r/工作樹wt');

    expect(AutoReopenMarkerRepository(store).read(), '/r/工作樹wt');
    expect(store.getString(AutoReopenMarkerRepository.key), '/r/工作樹wt');
  });

  test('clear removes it', () async {
    final SharedPreferences store = await prefs(<String, Object>{
      AutoReopenMarkerRepository.key: '/r',
    });
    await AutoReopenMarkerRepository(store).clear();

    expect(AutoReopenMarkerRepository(store).read(), isNull);
    expect(store.containsKey(AutoReopenMarkerRepository.key), isFalse);
  });
}
