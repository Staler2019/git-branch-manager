import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/update_installer.dart';

/// How long after launch [UpdateLeftoverSweep] runs.
///
/// A provider rather than a constructor parameter, mirroring
/// `autoUpdateCheckDelayProvider`: `GbmApp` builds the widget itself, so an
/// ancestor scope is the only place that can reach it. The device-tier
/// harness overrides this past every test's lifetime -- without it, running
/// the real app under `integration_test/` would sweep the developer's own
/// `Directory.systemTemp`.
final Provider<Duration> updateLeftoverSweepDelayProvider = Provider<Duration>(
  (Ref ref) => const Duration(seconds: 3),
);

/// Deletes what a completed update left behind, shortly after launch.
///
/// Separate from [AutoUpdateCheck] on purpose, and not gated on the same
/// preference: turning off *checking* for updates says nothing about the
/// leftovers of one that already happened, and a user who switches it off
/// right after updating would otherwise keep a full copy of the old install
/// forever.
///
/// Deliberately not run from `main()` before `runApp`: reaching this code
/// is what proves the new build starts, and deleting the rollback copy
/// before the window appears would throw the fallback away a moment too
/// early.
///
/// Renders [child] unchanged -- this widget contributes no layout.
class UpdateLeftoverSweep extends ConsumerStatefulWidget {
  const UpdateLeftoverSweep({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<UpdateLeftoverSweep> createState() =>
      _UpdateLeftoverSweepState();
}

class _UpdateLeftoverSweepState extends ConsumerState<UpdateLeftoverSweep> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(ref.read(updateLeftoverSweepDelayProvider), _sweep);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _sweep() async {
    // `sweepUpdateLeftovers` never throws, so there is nothing to catch --
    // see its own doc comment for why housekeeping stays silent.
    await ref.read(updateInstallerProvider).sweepUpdateLeftovers();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
