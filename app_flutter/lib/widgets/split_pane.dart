import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/panel_layout_repository.dart';
import '../theme/gbm_theme.dart';
import '../theme/tokens.dart';

/// The divider's hit width. Wider than the 1px line it draws so the drag
/// target is reachable; the extra 4px come out of the panes, which is why
/// every extent calculation in this file has to subtract it. Previously
/// written out three times (drag maths, divider build, and now the
/// build-time clamp), which is one copy too many to keep in step.
const double _kDividerWidth = 5.0;

/// A resizable split pane widget supporting both extent mode (fixed first pane)
/// and flex mode (weighted multi-pane layout).
///
/// - **Extent mode** (`spec.defaultExtent != null`): exactly 2 children.
///   Pane 0 has fixed pixel width/height; pane 1 fills remaining space.
///
/// - **Flex mode** (`spec.flexRatio != null`): N children with weighted ratios.
///   Each pane resizes proportionally to its flex weight.
///
/// Sizes are persisted to [panelLayoutRepositoryProvider] and restored on app restart.
class GbmSplitPane extends ConsumerStatefulWidget {
  const GbmSplitPane({
    super.key,
    required this.axis,
    required this.children,
    required this.spec,
    required this.storageId,
    this.onFlexChanged,
    this.controller,
  });

  /// [Axis.horizontal] = panes side-by-side, vertical dividers, drag left-right.
  /// [Axis.vertical] = panes stacked, horizontal dividers, drag up-down.
  final Axis axis;

  /// Child widgets occupying the panes.
  final List<Widget> children;

  /// Splitter spec defining default sizes and constraints.
  final GbmSplitterSpec spec;

  /// Stable ID for persistence, e.g. 'main.sidebar', 'cw.panes'.
  /// Main window and conflict window use disjoint namespaces.
  final String storageId;

  /// Called when user resizes a pane via drag or keyboard.
  /// For extent mode: [List<double>] with one element [extentPx].
  /// For flex mode: [List<double>] with N weights matching [spec.flexRatio.length].
  final ValueChanged<List<double>>? onFlexChanged;

  /// Optional external handle for programmatically opening/collapsing an
  /// extent-mode pane -- e.g. a caller reacting to a button tap needs to
  /// un-collapse a `collapsedByDefault: true` pane (like the log drawer)
  /// that the user has never dragged open, since [_currentFlexes] is
  /// otherwise private State the caller has no way to reach.
  final GbmSplitPaneController? controller;

  @override
  ConsumerState<GbmSplitPane> createState() => _GbmSplitPaneState();
}

/// Attaches to a [GbmSplitPane] via its [GbmSplitPane.controller] param to
/// let external code open/collapse an extent-mode pane -- see that field's
/// doc comment for why this indirection exists instead of a plain callback.
/// Mirrors the standard Flutter attach/detach controller idiom (as used by
/// e.g. `ScrollController`, `TabController`).
class GbmSplitPaneController {
  _GbmSplitPaneState? _state;

  void _attach(_GbmSplitPaneState state) => _state = state;

  void _detach(_GbmSplitPaneState state) {
    if (identical(_state, state)) {
      _state = null;
    }
  }

  /// Expands an extent-mode pane 0 to at least [GbmSplitterSpec.minExtent]
  /// if it is currently collapsed/smaller than that. No-op in flex mode, if
  /// already open, or if not currently attached to a mounted [GbmSplitPane].
  void open() => _state?._openToMinimum();
}

class _GbmSplitPaneState extends ConsumerState<GbmSplitPane> {
  late List<double> _currentFlexes;
  late List<FocusNode> _dividerFocusNodes;
  late Map<int, Timer> _hoverTimers;
  late Set<int> _hoveredDividers;
  double _availableExtent = 0;

  @override
  void initState() {
    super.initState();
    _hoverTimers = <int, Timer>{};
    _hoveredDividers = <int>{};

    // Determine number of panes
    final int paneCount = widget.spec.flexRatio?.length ?? 2;

    // Initialize flex weights from storage or spec
    final List<double>? stored = ref
        .read(panelLayoutRepositoryProvider)
        .read(widget.storageId);

    if (widget.spec.defaultExtent != null) {
      // Extent mode: stored should be [extentPx] or null
      if (stored != null && stored.length == 1) {
        _currentFlexes = stored;
      } else {
        // collapsedByDefault: if no stored value and collapsedByDefault is true,
        // start with extent 0; otherwise use defaultExtent
        final double initialExtent =
            (stored == null && widget.spec.collapsedByDefault)
            ? 0.0
            : widget.spec.defaultExtent!;
        _currentFlexes = <double>[initialExtent];
      }
    } else {
      // Flex mode: stored should match flexRatio length or null
      final List<double> defaultRatios = widget.spec.flexRatio!.toList();
      if (stored != null && stored.length == paneCount) {
        _currentFlexes = stored;
      } else {
        _currentFlexes = defaultRatios;
      }
    }

    // Create focus nodes for each divider
    _dividerFocusNodes = List<FocusNode>.generate(
      paneCount - 1,
      (i) => FocusNode(),
    );

    widget.controller?._attach(this);
  }

  @override
  void didUpdateWidget(GbmSplitPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    for (final Timer timer in _hoverTimers.values) {
      timer.cancel();
    }
    for (final FocusNode node in _dividerFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  /// See [GbmSplitPaneController.open].
  void _openToMinimum() {
    if (widget.spec.defaultExtent == null) return;
    final double target = math.max(_currentFlexes[0], widget.spec.minExtent);
    if (target == _currentFlexes[0]) return;
    setState(() => _currentFlexes[0] = target);
    widget.onFlexChanged?.call(_currentFlexes);
    unawaited(_persistFlexes());
  }

  Future<void> _persistFlexes() async {
    await ref
        .read(panelLayoutRepositoryProvider)
        .write(widget.storageId, _currentFlexes);
  }

  void _onDividerDelta(int dividerIndex, double deltaPixels) {
    if (widget.spec.defaultExtent != null) {
      // Extent mode
      final double minExtent = widget.spec.minExtent;
      // For vertical axis with pane 0 at the bottom, invert delta: drag-down shrinks
      final double adjustedDelta = widget.axis == Axis.vertical
          ? -deltaPixels
          : deltaPixels;
      final double newExtent = (_currentFlexes[0] + adjustedDelta).clamp(
        minExtent,
        _availableExtent - minExtent,
      );

      setState(() {
        _currentFlexes[0] = newExtent;
      });

      widget.onFlexChanged?.call(_currentFlexes);
      unawaited(_persistFlexes());
    } else {
      // Flex mode
      final List<double> defaultRatios = widget.spec.flexRatio!;
      final double flexSum = _currentFlexes.reduce((a, b) => a + b);
      final int paneCount = defaultRatios.length;
      final double availableFlexSpace =
          _availableExtent - (paneCount - 1) * _kDividerWidth;
      final double pixelsPerFlexUnit = availableFlexSpace / flexSum;

      final double flexDelta = deltaPixels / pixelsPerFlexUnit;

      // Compute new weights
      final List<double> newFlexes = _currentFlexes.toList();
      final double minPixels = widget.spec.minExtent;

      // Try to apply the full delta
      double appliedDelta = flexDelta;

      // Clamp so neither pane stays above minExtent
      final double pane0Pixels =
          (newFlexes[dividerIndex] + appliedDelta) * pixelsPerFlexUnit;
      final double pane1Pixels =
          (newFlexes[dividerIndex + 1] - appliedDelta) * pixelsPerFlexUnit;

      if (pane0Pixels < minPixels) {
        appliedDelta =
            (minPixels / pixelsPerFlexUnit) - newFlexes[dividerIndex];
      }
      if (pane1Pixels < minPixels) {
        appliedDelta =
            newFlexes[dividerIndex + 1] - (minPixels / pixelsPerFlexUnit);
      }

      newFlexes[dividerIndex] += appliedDelta;
      newFlexes[dividerIndex + 1] -= appliedDelta;

      setState(() {
        _currentFlexes = newFlexes;
      });

      widget.onFlexChanged?.call(_currentFlexes);
      unawaited(_persistFlexes());
    }
  }

  void _resetToDefault() {
    if (widget.spec.defaultExtent != null) {
      _currentFlexes = <double>[widget.spec.defaultExtent!];
    } else {
      _currentFlexes = widget.spec.flexRatio!.toList();
    }

    setState(() {});

    widget.onFlexChanged?.call(_currentFlexes);
    unawaited(_persistFlexes());
  }

  void _startHoverTimer(int dividerIndex) {
    _hoverTimers[dividerIndex] = Timer(const Duration(milliseconds: 120), () {
      if (mounted) {
        setState(() {
          _hoveredDividers.add(dividerIndex);
        });
      }
    });
  }

  void _cancelHoverTimer(int dividerIndex) {
    _hoverTimers[dividerIndex]?.cancel();
    _hoverTimers.remove(dividerIndex);
    if (mounted) {
      setState(() {
        _hoveredDividers.remove(dividerIndex);
      });
    }
  }

  Widget _buildDivider(int dividerIndex) {
    const double dividerVisualWidth = 1.0;
    final bool isHovered = _hoveredDividers.contains(dividerIndex);

    final Color dividerColor = isHovered
        ? context.gbmColors.accent
        : context.gbmColors.borderSubtle;

    if (widget.axis == Axis.horizontal) {
      return Focus(
        key: Key('gbm-split-divider-$dividerIndex'),
        focusNode: _dividerFocusNodes[dividerIndex],
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) {
            return KeyEventResult.ignored;
          }
          final bool isShifted = HardwareKeyboard.instance.isShiftPressed;
          final int delta = isShifted ? 64 : 16;

          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            _onDividerDelta(dividerIndex, delta.toDouble());
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _onDividerDelta(dividerIndex, -delta.toDouble());
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          onEnter: (_) => _startHoverTimer(dividerIndex),
          onExit: (_) => _cancelHoverTimer(dividerIndex),
          child: GestureDetector(
            onHorizontalDragUpdate: (details) {
              _onDividerDelta(dividerIndex, details.delta.dx);
            },
            onDoubleTap: _resetToDefault,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: _kDividerWidth,
              color: Colors.transparent,
              child: Center(
                child: Container(
                  width: dividerVisualWidth,
                  height: double.infinity,
                  color: dividerColor,
                ),
              ),
            ),
          ),
        ),
      );
    } else {
      return Focus(
        key: Key('gbm-split-divider-$dividerIndex'),
        focusNode: _dividerFocusNodes[dividerIndex],
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) {
            return KeyEventResult.ignored;
          }
          final bool isShifted = HardwareKeyboard.instance.isShiftPressed;
          final int delta = isShifted ? 64 : 16;

          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            _onDividerDelta(dividerIndex, delta.toDouble());
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            _onDividerDelta(dividerIndex, -delta.toDouble());
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeRow,
          onEnter: (_) => _startHoverTimer(dividerIndex),
          onExit: (_) => _cancelHoverTimer(dividerIndex),
          child: GestureDetector(
            onVerticalDragUpdate: (details) {
              _onDividerDelta(dividerIndex, details.delta.dy);
            },
            onDoubleTap: _resetToDefault,
            behavior: HitTestBehavior.opaque,
            child: Container(
              height: _kDividerWidth,
              color: Colors.transparent,
              child: Center(
                child: Container(
                  width: double.infinity,
                  height: dividerVisualWidth,
                  color: dividerColor,
                ),
              ),
            ),
          ),
        ),
      );
    }
  }

  /// The size this pane starts at with nothing persisted: the spec default,
  /// or 0 for a `collapsedByDefault` drawer (the log panel, which spec page
  /// 09 lists with `def: '收合'`).
  List<double> _specDefaultFlexes() {
    if (widget.spec.defaultExtent != null) {
      return <double>[
        widget.spec.collapsedByDefault ? 0.0 : widget.spec.defaultExtent!,
      ];
    }
    return widget.spec.flexRatio!.toList();
  }

  /// Snaps back to [_specDefaultFlexes]. Deliberately does not re-persist:
  /// [PanelLayoutRepository.clear] has already removed the stored keys, and
  /// writing the defaults back would make "never resized" indistinguishable
  /// from "resized to exactly the default" on the next start.
  void _resetToSpecDefault() {
    setState(() => _currentFlexes = _specDefaultFlexes());
    widget.onFlexChanged?.call(_currentFlexes);
  }

  /// Extent mode's fixed pane width/height for this build -- the persisted
  /// value, reduced if it no longer fits. See the call site for why the
  /// filling pane is the one held at [GbmSplitterSpec.minExtent].
  ///
  /// Deliberately does **not** write back to `_currentFlexes`: a window that
  /// is temporarily narrow must not overwrite the size the user dragged to,
  /// or restoring the window would not restore the layout.
  double _clampedFixedExtent() {
    final double maxFixed = math.max(
      0,
      _availableExtent - _kDividerWidth - widget.spec.minExtent,
    );
    return _currentFlexes[0].clamp(0, maxFixed);
  }

  @override
  Widget build(BuildContext context) {
    // View → Reset panel sizes (Ctrl/Cmd+0). See panelLayoutGenerationProvider
    // for why this is a counter rather than a re-read of storage.
    ref.listen<int>(panelLayoutGenerationProvider, (int? previous, int next) {
      if (previous != null && previous != next) _resetToSpecDefault();
    });

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        _availableExtent = widget.axis == Axis.horizontal
            ? constraints.maxWidth
            : constraints.maxHeight;

        if (widget.spec.defaultExtent != null) {
          // Extent mode: two children, first is fixed, second fills.
          //
          // The stored extent has to be clamped against the space this build
          // actually got. It is persisted (and defaulted) independently of
          // the window, so a container narrower than it -- the user shrinks
          // the window below the sidebar width they last dragged to -- used
          // to hand SizedBox a width larger than the Row, i.e. a thrown
          // RenderFlex overflow. _availableExtent was already being read
          // here, but only the drag path consulted it.
          //
          // The clamp protects the *filling* pane, not the fixed one: it
          // keeps at least spec.minExtent, and the fixed pane gives up
          // whatever is left over. That is the right way round because the
          // filling pane is the content the window exists to show, and the
          // fixed pane (sidebar, log drawer) is the one with a toggle. When
          // even that is impossible the fixed pane collapses to zero rather
          // than overflowing.
          final double clampedExtent = _clampedFixedExtent();
          if (widget.axis == Axis.horizontal) {
            return Row(
              children: <Widget>[
                SizedBox(width: clampedExtent, child: widget.children[0]),
                _buildDivider(0),
                Expanded(child: widget.children[1]),
              ],
            );
          } else {
            // Vertical: render main content first, then divider, then fixed drawer
            return Column(
              children: <Widget>[
                Expanded(child: widget.children[1]),
                _buildDivider(0),
                SizedBox(height: clampedExtent, child: widget.children[0]),
              ],
            );
          }
        } else {
          // Flex mode: N children with flex weights
          final double flexSum = _currentFlexes.reduce((a, b) => a + b);

          final List<Widget> paneWidgets = <Widget>[];
          for (int i = 0; i < widget.children.length; i++) {
            final int flexPercent = (_currentFlexes[i] * 100 / flexSum).round();
            paneWidgets.add(
              Flexible(
                flex: flexPercent,
                fit: FlexFit.tight,
                child: widget.children[i],
              ),
            );

            if (i < widget.children.length - 1) {
              paneWidgets.add(_buildDivider(i));
            }
          }

          if (widget.axis == Axis.horizontal) {
            return Row(children: paneWidgets);
          } else {
            return Column(children: paneWidgets);
          }
        }
      },
    );
  }
}
