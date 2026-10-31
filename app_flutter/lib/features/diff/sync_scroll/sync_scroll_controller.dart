import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'sync_slot_heights.dart';

/// Scrolls synced columns together (plan: Slice S, E2/F3/F4).
///
/// The **leader** is the column the user last moved -- set only by [lead],
/// which each column calls on a pointer down and on a user's own scroll (a
/// non-idle `UserScrollNotification` -- the wheel sends one -- or a drag's
/// `ScrollStartNotification`), and which a programmatic jump calls before
/// it moves. Any other movement of a column (the ballistic settle a
/// `jumpTo` ends in, an extent correction) leads nothing and mirrors
/// nothing.
///
/// A follower takes the leader's offset, clamped to its own extent (past it, `jumpTo` would bounce back through a
/// ballistic settle). Its own listener drives nothing back, because only the
/// leader's movement mirrors. **The leader is never jumped**: a user's drag,
/// a fling or a selection autoscroll runs uninterrupted (`jumpTo` would
/// `goIdle` it, B3).
///
/// Every segment starts at the same slot top in every column
/// ([SyncSlotHeights.offsetOf]), but a sliver list keeps the offsets it laid
/// a released item out at, so once a spacer above the viewport changes after
/// its item was released, the two columns' pixels no longer mean the same
/// place. So after each move, and after each batch of measured heights, the
/// follower is corrected against the geometry: a spacer both columns have
/// built ends its segment in both.
class SyncScrollController {
  SyncScrollController(List<ScrollController> columns)
    : _columns = List<ScrollController>.unmodifiable(columns),
      _jumps = List<int>.filled(columns.length, 0),
      _spacers = <Map<int, BuildContext>>[
        for (int i = 0; i < columns.length; i++) <int, BuildContext>{},
      ] {
    for (int c = 0; c < _columns.length; c++) {
      void listener() => _onMoved(c);
      _listeners.add(listener);
      _columns[c].addListener(listener);
    }
    // E6: a column opened at a stored offset brings the others along once
    // they are all laid out.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_disposed || _leader != null) return;
      lead(0);
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  final List<ScrollController> _columns;
  final List<VoidCallback> _listeners = <VoidCallback>[];
  final List<int> _jumps;
  final List<Map<int, BuildContext>> _spacers;
  SyncSlotHeights? _heights;
  int? _leader;
  bool _disposed = false;
  bool _correctionScheduled = false;

  /// How many times this controller has jumped [column]; for the counting
  /// tests.
  int jumpCount(int column) => _jumps[column];

  /// The column that leads now, if any has yet.
  @visibleForTesting
  int? get leader => _leader;

  /// The slot heights the columns pad to. A batch of measured heights moves
  /// spacers, so it earns the followers another correction.
  set heights(SyncSlotHeights? value) {
    if (identical(value, _heights)) return;
    _heights?.removeListener(_onHeights);
    _heights = value?..addListener(_onHeights);
  }

  /// Makes [column] the leader: the user is about to move it, or a caller is
  /// about to move it by program. Taking the lead mirrors at once, so a
  /// column still settling a fling stops where the new leader is instead of
  /// drifting on until the new leader first moves (a touch drag moves only
  /// past its slop).
  void lead(int column) {
    if (_leader == column) return;
    _leader = column;
    _mirror();
  }

  /// Where a column's [segment] ends: its spacer's context while built.
  void registerSpacer(int column, int segment, BuildContext context) =>
      _spacers[column][segment] = context;

  void unregisterSpacer(int column, int segment, BuildContext context) {
    if (identical(_spacers[column][segment], context)) {
      _spacers[column].remove(segment);
    }
  }

  void _onMoved(int column) {
    if (column != _leader) return;
    _mirror();
  }

  void _onHeights() {
    if (_leader == null) return;
    _scheduleCorrection();
  }

  void _mirror() {
    final int? leader = _leader;
    if (leader == null || !_columns[leader].hasClients) return;
    final double pixels = _columns[leader].position.pixels;
    for (int c = 0; c < _columns.length; c++) {
      if (c != leader) _jumpTo(c, pixels);
    }
    _scheduleCorrection();
  }

  /// Jumps follower [column] to [target], clamped to its own extent.
  void _jumpTo(int column, double target) {
    if (!_columns[column].hasClients) return;
    final ScrollPosition position = _columns[column].position;
    final double clamped = target.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((clamped - position.pixels).abs() < 0.01) return;
    position.jumpTo(clamped);
    _jumps[column]++;
  }

  /// Runs one correction per trigger. The plan's 「最多重試 3 次」 loop is
  /// not here: a follower that moves builds items whose measured heights
  /// reach [heights], and that earns the next correction through
  /// [_onHeights]; no test reddened without the loop.
  void _scheduleCorrection() {
    if (_correctionScheduled) return;
    _correctionScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _correctionScheduled = false;
      if (_disposed) return;
      _correct();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  /// Moves each follower so a spacer both it and the leader have built
  /// ends at the same height in both viewports. A
  /// follower that shares none with the leader is left where the mirror put
  /// it.
  void _correct() {
    final int? leader = _leader;
    if (leader == null || !_columns[leader].hasClients) return;
    for (int c = 0; c < _columns.length; c++) {
      if (c == leader || !_columns[c].hasClients) continue;
      final double? drift = _driftOf(leader, c);
      if (drift == null || drift.abs() <= 0.5) continue;
      _jumpTo(c, _columns[c].position.pixels + drift);
    }
  }

  /// How far below the leader's [follower]'s copy of the topmost spacer
  /// both have built sits, each measured from its own viewport's top; null
  /// when they share none.
  double? _driftOf(int leader, int follower) {
    final double? leaderTop = _viewportTop(leader);
    final double? followerTop = _viewportTop(follower);
    if (leaderTop == null || followerTop == null) return null;
    double? best;
    double? drift;
    for (final MapEntry<int, BuildContext> e in _spacers[leader].entries) {
      final BuildContext? other = _spacers[follower][e.key];
      if (other == null) continue;
      final double? l = _bottomOf(e.value);
      final double? f = _bottomOf(other);
      if (l == null || f == null) continue;
      // The one nearest the leader's top edge: what the user is reading.
      final double distance = (l - leaderTop).abs();
      if (best == null || distance < best) {
        best = distance;
        drift = (f - followerTop) - (l - leaderTop);
      }
    }
    return drift;
  }

  double? _viewportTop(int column) {
    final RenderObject? box = _columns[column].position.context.storageContext
        .findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero).dy;
  }

  static double? _bottomOf(BuildContext context) {
    final RenderObject? box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return null;
    return box.localToGlobal(Offset(0, box.size.height)).dy;
  }

  void dispose() {
    _disposed = true;
    _heights?.removeListener(_onHeights);
    for (int c = 0; c < _columns.length; c++) {
      _columns[c].removeListener(_listeners[c]);
    }
  }
}
