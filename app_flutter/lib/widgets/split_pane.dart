import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/panel_layout_repository.dart';
import '../theme/gbm_theme.dart';
import '../theme/tokens.dart';

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

  @override
  ConsumerState<GbmSplitPane> createState() => _GbmSplitPaneState();
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
        _currentFlexes = <double>[widget.spec.defaultExtent!];
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
  }

  @override
  void dispose() {
    for (final Timer timer in _hoverTimers.values) {
      timer.cancel();
    }
    for (final FocusNode node in _dividerFocusNodes) {
      node.dispose();
    }
    super.dispose();
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
      final double newExtent = (_currentFlexes[0] + deltaPixels).clamp(
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
      final double dividerWidth = 5.0;
      final double availableFlexSpace =
          _availableExtent - (paneCount - 1) * dividerWidth;
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
    const double dividerWidth = 5.0;
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
              width: dividerWidth,
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
              height: dividerWidth,
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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        _availableExtent = widget.axis == Axis.horizontal
            ? constraints.maxWidth
            : constraints.maxHeight;

        if (widget.spec.defaultExtent != null) {
          // Extent mode: two children, first is fixed, second fills
          return Row(
            children: <Widget>[
              SizedBox(
                width: widget.axis == Axis.horizontal
                    ? _currentFlexes[0]
                    : double.infinity,
                height: widget.axis == Axis.vertical
                    ? _currentFlexes[0]
                    : double.infinity,
                child: widget.children[0],
              ),
              if (widget.axis == Axis.horizontal)
                _buildDivider(0)
              else
                SizedBox(height: 5, child: _buildDivider(0)),
              Expanded(child: widget.children[1]),
            ],
          );
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
