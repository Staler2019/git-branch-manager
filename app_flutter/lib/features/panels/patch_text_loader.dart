import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Reads a `.patch` file's text off disk.
///
/// A provider rather than a bare `File(path).readAsString()` for the same
/// reason [DesktopLauncher] and [FileSavePicker] are: a widget test has to
/// be able to hand the panel canned patch text without writing files.
///
/// `dart:io` and not a capi call, deliberately: a `.patch` on disk is not a
/// git object, nothing in `gbm_capi.h` reads arbitrary files, and adding an
/// entry point for "read this text file" would put a filesystem API through
/// an FFI boundary for no benefit.
typedef PatchTextLoader = Future<String> Function(String path);

final Provider<PatchTextLoader> patchTextLoaderProvider =
    Provider<PatchTextLoader>(
      (ref) =>
          (String path) => File(path).readAsString(),
    );
