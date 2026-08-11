import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ffi/gbm_bindings.dart';

/// One [GbmBindings] instance for the whole app -- symbol lookups are cheap
/// to cache and there is exactly one `gbm_capi` library loaded per process.
final Provider<GbmBindings> gbmBindingsProvider = Provider<GbmBindings>((ref) {
  return GbmBindings.open();
});
