// CLAUDE.md's layering puts `lib/data/` below `lib/features/**`, and routing
// beside the views. Nothing in the type system stops a repository from
// importing a route or a widget, and the clone job's success navigation was
// built around exactly that boundary: `CloneJobController.opened` is a
// Stream, and the app-level `CloneJobListener` does the `router.go`. This
// pins the boundary by reading the source, as
// `test/routing/dialog_push_single_source_test.dart` does for dialog pushes.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final RegExp _directive = RegExp(
  r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
  multiLine: true,
);

/// The `lib/`-relative path [uri] names when written in [file], or null for
/// `dart:` and other packages. Relative imports are real in `lib/data/`
/// (`'../../theme/theme_mode_provider.dart'`), so they are resolved too.
String? _libPath(File file, String uri) {
  const String package = 'package:gbm_flutter/';
  if (uri.startsWith(package)) return uri.substring(package.length);
  if (uri.contains(':')) return null;
  final Uri resolved = Uri.file(file.absolute.path).resolve(uri);
  final String lib = '${Directory('lib').absolute.path}/';
  final String path = resolved.toFilePath();
  return path.startsWith(lib) ? path.substring(lib.length) : null;
}

void main() {
  test('lib/data/ 不 import routing 或 features', () {
    final List<String> offenders = <String>[];
    for (final FileSystemEntity entity in Directory(
      'lib/data',
    ).listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final String source = entity.readAsStringSync();
      for (final RegExpMatch match in _directive.allMatches(source)) {
        final String? path = _libPath(entity, match.group(1)!);
        if (path == null) continue;
        if (path.startsWith('routing/') || path.startsWith('features/')) {
          offenders.add('${entity.path}: ${match.group(1)}');
        }
      }
    }

    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
