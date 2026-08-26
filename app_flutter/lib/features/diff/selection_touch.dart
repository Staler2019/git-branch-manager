import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Which rows of a diff a live text selection is currently touching.
///
/// Spec P03's `SCOPES` makes an ordinary text selection a one-shot scope:
/// drag across some lines and the button acts on those instead of the
/// default block. Flutter will not tell you that directly -- a
/// [SelectionArea] reports the selected *text*, not which widgets it covers
/// -- so each row is wrapped in a [SelectionListener] of its own and asked
/// whether its own subtree holds an uncollapsed selection.
///
/// One notifier per row, because [SelectionListenerNotifier] asserts it is
/// registered to exactly one [SelectionListener].
class SelectionTouchTracker extends ChangeNotifier {
  final Map<String, SelectionListenerNotifier> _notifiers =
      <String, SelectionListenerNotifier>{};
  final Map<String, GlobalKey> _keys = <String, GlobalKey>{};
  final Set<String> _touched = <String>{};
  bool _notifyScheduled = false;
  bool _disposed = false;

  /// Whether reports are being ignored.
  ///
  /// **Latched except while the user is actually dragging**, and that is
  /// load-bearing rather than an optimisation. Every change to this set
  /// rebuilds the rows, rebuilding the rows perturbs the selection
  /// geometry, and the delegates then re-report -- so a tracker that
  /// listened all the time oscillated between "two rows selected" and
  /// "nothing selected" on idle frames, with the temporary card flapping in
  /// and out. Between a pointer down and the matching pointer up the
  /// reports are the user's own; outside that window they are noise.
  bool _latched = true;

  /// The keys of every row the selection currently covers.
  Set<String> get touched => Set<String>.unmodifiable(_touched);

  /// A pointer is down in the well and the set is still moving.
  ///
  /// Callers must draw **nothing** derived from [touched] while this is
  /// true. The one-shot block lives inside the scope card, wrapping the
  /// selected rows in place, so drawing it mid-drag reparents the rows below
  /// it -- and those rows carry the [SelectionListener]s whose reports are
  /// deciding what [touched] holds. The drag then collapses to a single row.
  /// SelectionArea's own text highlight is the live feedback; the block is
  /// what the drag settles into.
  bool get isDragging => !_latched;

  /// A stable [GlobalKey] for [rowKey]'s [SelectionListener].
  ///
  /// **Global, not a [ValueKey].** A row moves between subtrees as the diff
  /// changes -- out of a scope card and into a gap, or the other way -- and
  /// with a local key that is a *new* element built before the old one
  /// unmounts, so both briefly hold the same notifier and
  /// [SelectionListenerNotifier]'s own `!registered` assert fires. A global
  /// key makes Flutter reparent the one element instead, which is also the
  /// only way the registration survives the move.
  ///
  /// One key per tracker per row, so the two columns of a `2 file` diff do
  /// not collide on a shared row number.
  GlobalKey keyFor(String rowKey) =>
      _keys.putIfAbsent(rowKey, () => GlobalKey());

  /// The notifier for [rowKey], created on first use and reused after, so a
  /// rebuild does not hand a fresh notifier to a [SelectionListener] that is
  /// still registered to the old one.
  SelectionListenerNotifier notifierFor(String rowKey) {
    return _notifiers.putIfAbsent(rowKey, () {
      final SelectionListenerNotifier notifier = SelectionListenerNotifier();
      notifier.addListener(() => _onRowChanged(rowKey, notifier));
      return notifier;
    });
  }

  /// Forgets the current selection.
  ///
  /// Called both when the block has been submitted (a one-shot scope is
  /// spent) and when the diff itself is replaced. **The second is not
  /// optional**: keys are positions within a hunk, so a row that is no
  /// longer rendered unregisters without notifying and its key would stay
  /// in [_touched], pointing at whatever line now sits at that index -- the
  /// same stale-index defect the per-line checkbox set guarded against.
  /// Forgets the scope and stops listening until the next drag.
  ///
  /// Called when the scope is spent and when the diff is replaced -- the
  /// plan's 「送出一次…或 staging 狀態改變（diff 重新載入）就清空」. Latching
  /// as well as emptying is what makes it stick: the rows a shorter diff
  /// still has stay selected, and their listeners would otherwise re-report
  /// on the next frame and bring the scope back naming lines the user never
  /// framed.
  void clear() {
    _latched = true;
    if (_touched.isEmpty) return;
    _touched.clear();
    _scheduleNotify();
  }

  /// Replaces the touched set from something other than a drag, and latches.
  ///
  /// Spec `SCOPES` gives 任意連續行 two inputs (「按住拖過多行，或 Shift + ↑
  /// ↓」) and 單一 hunk one more (「點 hunk 標頭列」), and only the drag
  /// produces a [SelectionListener] report at all -- a keyboard extension
  /// and a heading click emit no pointer events, so the row delegates never
  /// speak. Those two paths compute the set themselves and hand it here.
  ///
  /// Latching afterwards is the same guarantee [endGesture] gives: the set
  /// stays exactly what the caller asked for until the next pointer down in
  /// the well, so the row delegates -- which are still reporting whatever
  /// the *text* selection is, and for these two inputs that is nothing --
  /// cannot immediately erase it.
  void setTouched(Set<String> rows) {
    _latched = true;
    if (_touched.length == rows.length && _touched.containsAll(rows)) return;
    _touched
      ..clear()
      ..addAll(rows);
    _scheduleNotify();
  }

  /// A pointer went down in the diff: whatever was selected is being
  /// replaced, so start over and start listening.
  void beginGesture() {
    _latched = false;
    if (_touched.isEmpty) return;
    _touched.clear();
    _scheduleNotify();
  }

  /// The drag is over. What the set holds now is what the user framed.
  ///
  /// Notifies, because this is the transition the view draws on: with
  /// [isDragging] suppressing every rebuild in between, the pointer coming
  /// up is the only signal that the settled set is ready to render.
  void endGesture() {
    if (_latched) return;
    _latched = true;
    _scheduleNotify();
  }

  void _onRowChanged(String rowKey, SelectionListenerNotifier notifier) {
    if (_disposed || _latched) return;
    final bool isTouched =
        notifier.registered &&
        notifier.selection.status == SelectionStatus.uncollapsed;
    final bool changed = isTouched
        ? _touched.add(rowKey)
        : _touched.remove(rowKey);
    if (changed) _scheduleNotify();
  }

  /// Selection geometry settles during layout, and a listener that called
  /// `setState` from there would be writing to a widget mid-frame. Coalesced
  /// to one notification per frame as well, since dragging across ten rows
  /// fires ten times.
  ///
  /// **[SchedulerBinding.ensureVisualUpdate] is not optional here**, even
  /// though every caller before [setTouched] happened not to need it:
  /// `addPostFrameCallback` registers a callback for the end of the next
  /// frame and *does not ask for one*. A drag hides that, because the drag
  /// itself keeps frames coming; a single click does not, so the
  /// notification simply never arrived and the scope a hunk-heading click
  /// had already recorded stayed invisible until something else happened to
  /// draw. In a widget test the same gap is total rather than intermittent,
  /// since `tester.pump()` runs a frame only `if (hasScheduledFrame)` -- six
  /// pumps in a row did nothing at all.
  void _scheduleNotify() {
    if (_notifyScheduled || _disposed) return;
    _notifyScheduled = true;
    SchedulerBinding.instance.ensureVisualUpdate();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _notifyScheduled = false;
      if (_disposed) return;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    for (final SelectionListenerNotifier notifier in _notifiers.values) {
      notifier.dispose();
    }
    _notifiers.clear();
    _keys.clear();
    super.dispose();
  }
}

/// Reports to [tracker] whether the selection covers [rowKey]'s subtree.
class SelectionTouchRow extends StatelessWidget {
  const SelectionTouchRow({
    super.key,
    required this.tracker,
    required this.rowKey,
    required this.child,
  });

  final SelectionTouchTracker tracker;
  final String rowKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SelectionListener(
      key: tracker.keyFor(rowKey),
      selectionNotifier: tracker.notifierFor(rowKey),
      child: child,
    );
  }
}

/// The key a diff row is tracked under. Positional, so it is only valid for
/// as long as the diff it was computed from is on screen.
String selectionRowKey(int hunkIndex, int lineIndex) => '$hunkIndex:$lineIndex';

/// Splits [touched] back into line indices per hunk, dropping anything that
/// is not in [changedByHunk] -- only added and removed lines move, so a drag
/// that crossed only context has nothing to stage.
Map<int, List<int>> touchedChangedLines(
  Set<String> touched,
  Map<int, Set<int>> changedByHunk,
) {
  final Map<int, List<int>> result = <int, List<int>>{};
  for (final String key in touched) {
    final List<String> parts = key.split(':');
    if (parts.length != 2) continue;
    final int? hunkIndex = int.tryParse(parts[0]);
    final int? lineIndex = int.tryParse(parts[1]);
    if (hunkIndex == null || lineIndex == null) continue;
    if (!(changedByHunk[hunkIndex]?.contains(lineIndex) ?? false)) continue;
    (result[hunkIndex] ??= <int>[]).add(lineIndex);
  }
  for (final List<int> lines in result.values) {
    lines.sort();
  }
  // Ascending hunk order, so the fan-out below submits patches in the order
  // they appear in the file rather than in hash order.
  return <int, List<int>>{
    for (final int hunkIndex in result.keys.toList()..sort())
      hunkIndex: List<int>.unmodifiable(result[hunkIndex]!),
  };
}
