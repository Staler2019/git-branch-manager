import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/update_installer.dart';

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
  const UpdateLeftoverSweep({
    super.key,
    required this.child,
    this.delay = const Duration(seconds: 3),
  });

  final Widget child;

  /// A plain parameter rather than a provider: nothing outside a test ever
  /// changes it, and the sweep has no other configuration to carry.
  final Duration delay;

  @override
  ConsumerState<UpdateLeftoverSweep> createState() =>
      _UpdateLeftoverSweepState();
}

class _UpdateLeftoverSweepState extends ConsumerState<UpdateLeftoverSweep> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.delay, _sweep);
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
