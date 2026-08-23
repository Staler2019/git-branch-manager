import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_version.dart';

/// The running build's version, as an overridable provider.
///
/// [currentBuildVersion] is a compile-time constant, so nothing can vary it
/// from inside a test run — every widget test would be stuck with the
/// developer-build (`null`) reading, and the release path would go
/// unexercised. Reading it through a provider restores the seam, the same
/// way `desktopLauncherProvider` and `fileSavePickerProvider` do for the
/// two other pieces of process-level state this app touches.
///
/// Two consumers share it deliberately: the About dialog renders it, and
/// the update check compares it against the newest published release. A
/// second source of truth for "which version am I" is exactly the drift
/// that would let those two disagree on screen.
final Provider<AppVersion?> buildVersionProvider = Provider<AppVersion?>(
  (Ref ref) => currentBuildVersion,
);
