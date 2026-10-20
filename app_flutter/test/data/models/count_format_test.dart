import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/count_format.dart';

void main() {
  for (final (int n, String s) in <(int, String)>[
    (0, '0'),
    (7, '7'),
    (999, '999'),
    (1000, '1,000'),
    (12480, '12,480'),
    (100000, '100,000'),
    (1234567, '1,234,567'),
  ]) {
    test('$n -> $s', () => expect(formatCount(n), s));
  }
}
