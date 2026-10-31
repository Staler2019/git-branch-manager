// `flutter drive` host side for integration_test/perf/: runs the target in
// profile mode, which `flutter test` cannot. Named without `_test` so the
// device batch loop does not pick it up.
//
//   flutter drive --profile -d macos \
//     --driver=integration_test/perf/driver.dart \
//     --target=integration_test/perf/full_file_view_perf_test.dart
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
