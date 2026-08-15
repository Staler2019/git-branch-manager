import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/repositories/panel_layout_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('read returns null when nothing has been stored for that id', () async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final PanelLayoutRepository repo = PanelLayoutRepository(prefs);
    expect(repo.read('main.sidebar'), isNull);
  });

  test('write then read round-trips a List<double> exactly', () async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final PanelLayoutRepository repo = PanelLayoutRepository(prefs);
    final List<double> weights = [0.3, 1.12, 0.58];

    await repo.write('cw.panes', weights);
    final List<double>? result = repo.read('cw.panes');

    expect(result, isNotNull);
    expect(result!.length, 3);
    expect(result[0], closeTo(0.3, 0.0001));
    expect(result[1], closeTo(1.12, 0.0001));
    expect(result[2], closeTo(0.58, 0.0001));
  });

  test('read returns null when stored string is not valid JSON', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'panelLayout.main.sidebar': 'not valid json {[',
    });
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final PanelLayoutRepository repo = PanelLayoutRepository(prefs);

    expect(repo.read('main.sidebar'), isNull);
  });

  test('read returns null when stored JSON is not a list', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'panelLayout.wc.columns': '"just a string"',
    });
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final PanelLayoutRepository repo = PanelLayoutRepository(prefs);

    expect(repo.read('wc.columns'), isNull);
  });

  test('different splitterIds do not collide', () async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final PanelLayoutRepository repo = PanelLayoutRepository(prefs);

    await repo.write('main.sidebar', [200.0]);
    await repo.write('wc.columns', [300.0, 400.0]);

    expect(repo.read('main.sidebar'), [200.0]);
    expect(repo.read('wc.columns'), [300.0, 400.0]);
  });
}
