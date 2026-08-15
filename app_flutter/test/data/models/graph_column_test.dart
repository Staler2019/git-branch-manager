import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/graph_column.dart';

void main() {
  group('GraphColumn', () {
    test('creates instance with all required fields', () {
      final column = GraphColumn(
        id: 'author',
        label: 'Author',
        visible: true,
        locked: false,
        width: 120.0,
        order: 3,
      );

      expect(column.id, 'author');
      expect(column.label, 'Author');
      expect(column.visible, true);
      expect(column.locked, false);
      expect(column.width, 120.0);
      expect(column.order, 3);
    });

    group('toJson / fromJson', () {
      test('serializes to JSON correctly', () {
        final column = GraphColumn(
          id: 'refs',
          label: 'Refs',
          visible: true,
          locked: true,
          width: 150.0,
          order: 2,
        );

        final json = column.toJson();

        expect(json['id'], 'refs');
        expect(json['label'], 'Refs');
        expect(json['visible'], true);
        expect(json['locked'], true);
        expect(json['width'], 150.0);
        expect(json['order'], 2);
      });

      test('deserializes from JSON correctly', () {
        final json = {
          'id': 'date',
          'label': 'Date',
          'visible': false,
          'locked': false,
          'width': 90.0,
          'order': 4,
        };

        final column = GraphColumn.fromJson(json);

        expect(column.id, 'date');
        expect(column.label, 'Date');
        expect(column.visible, false);
        expect(column.locked, false);
        expect(column.width, 90.0);
        expect(column.order, 4);
      });

      test('round-trip JSON serialization preserves values', () {
        final original = GraphColumn(
          id: 'hash',
          label: 'Commit hash',
          visible: true,
          locked: false,
          width: 100.0,
          order: 5,
        );

        final json = original.toJson();
        final restored = GraphColumn.fromJson(json);

        expect(restored.id, original.id);
        expect(restored.label, original.label);
        expect(restored.visible, original.visible);
        expect(restored.locked, original.locked);
        expect(restored.width, original.width);
        expect(restored.order, original.order);
      });
    });

    group('copyWith', () {
      test('copies all fields when none are provided', () {
        final original = GraphColumn(
          id: 'author',
          label: 'Author',
          visible: true,
          locked: false,
          width: 120.0,
          order: 3,
        );

        final copy = original.copyWith();

        expect(copy.id, original.id);
        expect(copy.label, original.label);
        expect(copy.visible, original.visible);
        expect(copy.locked, original.locked);
        expect(copy.width, original.width);
        expect(copy.order, original.order);
      });

      test('updates only specified fields', () {
        final original = GraphColumn(
          id: 'author',
          label: 'Author',
          visible: true,
          locked: false,
          width: 120.0,
          order: 3,
        );

        final updated = original.copyWith(visible: false, width: 150.0);

        expect(updated.id, original.id);
        expect(updated.label, original.label);
        expect(updated.visible, false);
        expect(updated.locked, original.locked);
        expect(updated.width, 150.0);
        expect(updated.order, original.order);
      });
    });
  });
}
