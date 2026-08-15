import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/repositories/graph_columns_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('GraphColumnsRepository', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    test('creates instance with SharedPreferences', () {
      final repo = GraphColumnsRepository(prefs);
      expect(repo, isNotNull);
    });

    group('readVisibility', () {
      test('returns empty map when nothing is stored', () {
        final repo = GraphColumnsRepository(prefs);
        final visibility = repo.readVisibility();

        expect(visibility, isEmpty);
      });

      test('reads persisted visibility state', () async {
        final visibility = {'graph': true, 'message': true, 'refs': false};
        await prefs.setString(
          '${GraphColumnsRepository.keyPrefix}visibility',
          jsonEncode(visibility),
        );

        final repo = GraphColumnsRepository(prefs);
        final result = repo.readVisibility();

        expect(result, visibility);
      });

      test('returns empty map on corrupt data', () async {
        await prefs.setString(
          '${GraphColumnsRepository.keyPrefix}visibility',
          'invalid json {',
        );

        final repo = GraphColumnsRepository(prefs);
        final result = repo.readVisibility();

        expect(result, isEmpty);
      });
    });

    group('readOrder', () {
      test('returns empty list when nothing is stored', () {
        final repo = GraphColumnsRepository(prefs);
        final order = repo.readOrder();

        expect(order, isEmpty);
      });

      test('reads persisted column order', () async {
        final order = ['graph', 'message', 'refs', 'author'];
        await prefs.setString(
          '${GraphColumnsRepository.keyPrefix}order',
          jsonEncode(order),
        );

        final repo = GraphColumnsRepository(prefs);
        final result = repo.readOrder();

        expect(result, order);
      });

      test('returns empty list on corrupt data', () async {
        await prefs.setString(
          '${GraphColumnsRepository.keyPrefix}order',
          'invalid json [',
        );

        final repo = GraphColumnsRepository(prefs);
        final result = repo.readOrder();

        expect(result, isEmpty);
      });
    });

    group('readWidths', () {
      test('returns empty map when nothing is stored', () {
        final repo = GraphColumnsRepository(prefs);
        final widths = repo.readWidths();

        expect(widths, isEmpty);
      });

      test('reads persisted column widths', () async {
        final widths = {'graph': 80.0, 'message': 300.0, 'author': 120.0};
        await prefs.setString(
          '${GraphColumnsRepository.keyPrefix}widths',
          jsonEncode(widths),
        );

        final repo = GraphColumnsRepository(prefs);
        final result = repo.readWidths();

        expect(result['graph'], 80.0);
        expect(result['message'], 300.0);
        expect(result['author'], 120.0);
      });

      test('returns empty map on corrupt data', () async {
        await prefs.setString(
          '${GraphColumnsRepository.keyPrefix}widths',
          'invalid json {',
        );

        final repo = GraphColumnsRepository(prefs);
        final result = repo.readWidths();

        expect(result, isEmpty);
      });
    });

    group('write methods', () {
      test('writes and reads visibility state round-trip', () async {
        final repo = GraphColumnsRepository(prefs);
        final visibility = {'graph': true, 'message': false, 'refs': true};

        await repo.writeVisibility(visibility);
        final result = repo.readVisibility();

        expect(result, visibility);
      });

      test('writes and reads column order round-trip', () async {
        final repo = GraphColumnsRepository(prefs);
        final order = ['refs', 'author', 'date', 'graph'];

        await repo.writeOrder(order);
        final result = repo.readOrder();

        expect(result, order);
      });

      test('writes and reads column widths round-trip', () async {
        final repo = GraphColumnsRepository(prefs);
        final widths = {'graph': 75.0, 'message': 280.0, 'author': 125.0};

        await repo.writeWidths(widths);
        final result = repo.readWidths();

        expect(result['graph'], 75.0);
        expect(result['message'], 280.0);
        expect(result['author'], 125.0);
      });

      test('overwrites previous visibility state', () async {
        final repo = GraphColumnsRepository(prefs);

        await repo.writeVisibility({'graph': true, 'message': true});
        expect(repo.readVisibility()['message'], true);

        await repo.writeVisibility({'graph': false, 'message': false});
        expect(repo.readVisibility()['message'], false);
      });

      test('overwrites previous column order', () async {
        final repo = GraphColumnsRepository(prefs);

        await repo.writeOrder(['a', 'b', 'c']);
        expect(repo.readOrder(), ['a', 'b', 'c']);

        await repo.writeOrder(['c', 'b', 'a']);
        expect(repo.readOrder(), ['c', 'b', 'a']);
      });

      test('overwrites previous column widths', () async {
        final repo = GraphColumnsRepository(prefs);

        await repo.writeWidths({'a': 100.0});
        expect(repo.readWidths()['a'], 100.0);

        await repo.writeWidths({'a': 200.0});
        expect(repo.readWidths()['a'], 200.0);
      });
    });
  });
}
