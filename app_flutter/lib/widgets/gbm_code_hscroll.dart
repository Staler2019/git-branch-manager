import 'package:flutter/material.dart';

/// One horizontal scroll region shared by every code row beneath it.
///
/// This is the "soft wrap off" half of the file views: with wrapping disabled
/// a long line has to go somewhere, and it goes sideways. A *shared* scroller
/// is the whole point -- a per-row one would desync the moment two rows had
/// different lengths, and a `ScrollController` cannot be attached to more than
/// one `Scrollable` anyway.
///
/// Rows opt into a pinned left gutter with [GbmPinnedGutter], which reads this
/// widget's controller out of the context and counter-translates itself.
///
/// **The default `ScrollBehavior` is deliberate -- do not override
/// `dragDevices` here.** It is tempting to clear the set to keep this
/// scroller's drag recogniser away from the `SelectionArea` that
/// `ScopedDiffView` builds its staging scopes out of, but that is wrong twice
/// over. It is unnecessary: `_kTouchLikeDeviceTypes` does not contain
/// `PointerDeviceKind.mouse`, and a desktop selection drag -- trackpad
/// included, per CLAUDE.md -- arrives as `mouse`, so the two never meet in the
/// gesture arena. And it is harmful: a trackpad's two-finger horizontal pan
/// reaches a `Scrollable` precisely *through* membership of that set, so
/// emptying it deletes the main way anyone scrolls here, leaving only the
/// scrollbar thumb and Shift+wheel.
class GbmCodeHScroll extends StatefulWidget {
  const GbmCodeHScroll({
    super.key,
    required this.contentWidth,
    required this.backdrop,
    required this.child,
  });

  /// Total width of the widest row, gutter included -- not just the text.
  /// Below the viewport width no scroller is built at all, so short files keep
  /// their full-width row backgrounds instead of ragged ones.
  final double contentWidth;

  /// What a pinned gutter paints over itself so the code can slide underneath.
  /// The pane knows its own backdrop; an individual row does not, which is why
  /// this is here and not on [GbmPinnedGutter]. A subtree sitting on a
  /// different surface (a scope card inside a sunken well) overrides it with
  /// [GbmPinnedGutterBackdrop].
  final Color backdrop;

  final Widget child;

  /// The enclosing scroller's controller, or null when the content fits and no
  /// scroller was built.
  static ScrollController? maybeControllerOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<GbmCodeHScrollScope>()
      ?.controller;

  static Color? maybeBackdropOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<GbmCodeHScrollScope>()
      ?.backdrop;

  @override
  State<GbmCodeHScroll> createState() => _GbmCodeHScrollState();
}

/// Carries the controller down to the rows.
///
/// A plain [InheritedWidget], **not** an `InheritedNotifier`: an
/// `InheritedNotifier` rebuilds every dependent on every notification, which
/// for a scroll controller means every row of the file rebuilding on every
/// frame of a drag. Dependents here rebuild only when the controller instance
/// itself changes; the per-frame work is confined to [GbmPinnedGutter]'s own
/// `AnimatedBuilder`.
class GbmCodeHScrollScope extends InheritedWidget {
  const GbmCodeHScrollScope({
    super.key,
    required this.controller,
    required this.backdrop,
    required super.child,
  });

  final ScrollController? controller;
  final Color backdrop;

  @override
  bool updateShouldNotify(GbmCodeHScrollScope oldWidget) =>
      oldWidget.controller != controller || oldWidget.backdrop != backdrop;
}

class _GbmCodeHScrollState extends State<GbmCodeHScroll> {
  final ScrollController _horizontal = ScrollController();

  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = widget.contentWidth;
        if (!width.isFinite || width <= constraints.maxWidth) {
          return GbmCodeHScrollScope(
            controller: null,
            backdrop: widget.backdrop,
            child: widget.child,
          );
        }
        return Scrollbar(
          controller: _horizontal,
          thumbVisibility: true,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            controller: _horizontal,
            child: SizedBox(
              width: width,
              child: GbmCodeHScrollScope(
                controller: _horizontal,
                backdrop: widget.backdrop,
                child: widget.child,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Overrides the backdrop a [GbmPinnedGutter] paints, for a subtree that sits
/// on a different surface than the pane does.
class GbmPinnedGutterBackdrop extends StatelessWidget {
  const GbmPinnedGutterBackdrop({
    super.key,
    required this.color,
    required this.child,
  });

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GbmCodeHScrollScope(
      controller: GbmCodeHScroll.maybeControllerOf(context),
      backdrop: color,
      child: child,
    );
  }
}

/// A row's left gutter, held at the viewport's left edge while the code beside
/// it scrolls underneath.
///
/// The row itself is inside the scroller and moves with it; this
/// counter-translates by exactly the scroll offset, which lands it back at the
/// viewport edge. It paints an opaque backdrop because the code it is holding
/// still passes *under* it -- a transparent gutter would show line text to the
/// left of the line numbers.
///
/// The gutter subtree is passed through `AnimatedBuilder`'s `child:` so a
/// scroll frame rebuilds only the `Transform` wrapper. That matters most in
/// `ScopedDiffView`, which builds its rows eagerly and so has every row of the
/// file alive at once.
class GbmPinnedGutter extends StatelessWidget {
  const GbmPinnedGutter({
    super.key,
    required this.width,
    required this.background,
    required this.child,
    this.opaque = true,
  });

  final double width;

  /// The row's own background (an added/removed line has one), or null to fall
  /// back to the pane's backdrop.
  ///
  /// Ignored entirely when [opaque] is false.
  final Color? background;

  /// Whether the gutter paints a backdrop behind itself.
  ///
  /// **True** suits a row that paints its own full-width background, like a
  /// diff line: the code passes under the gutter and something has to hide
  /// it, and repainting the row's own colour is seamless.
  ///
  /// **False** suits a row whose background is drawn by an *ancestor* that
  /// has to stay visible -- a `GbmRow`'s hover and selection tints, which an
  /// opaque strip would cover even at scroll offset zero. Such a row pairs
  /// this with [GbmPinnedGutterClip] around its content, so nothing ever
  /// reaches the area under the gutter and there is nothing to hide.
  final bool opaque;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ScrollController? controller = GbmCodeHScroll.maybeControllerOf(
      context,
    );
    final Widget inner = opaque
        ? ColoredBox(
            color:
                background ??
                GbmCodeHScroll.maybeBackdropOf(context) ??
                Theme.of(context).canvasColor,
            child: child,
          )
        : child;
    final Widget gutter = SizedBox(width: width, child: inner);
    if (controller == null) return gutter;
    return AnimatedBuilder(
      animation: controller,
      child: gutter,
      builder: (BuildContext context, Widget? child) => Transform.translate(
        offset: Offset(controller.hasClients ? controller.offset : 0, 0),
        child: child,
      ),
    );
  }
}

/// Keeps a row's content out of the area a [GbmPinnedGutter] holds.
///
/// The companion to `opaque: false`. The clip is in *viewport* coordinates --
/// its left edge is the scroll offset plus the gutter's width -- so the code
/// disappears exactly at the gutter's right edge however far the pane has
/// scrolled, and the row's own hover and selection tints stay visible
/// underneath because nothing opaque is painted over them.
class GbmPinnedGutterClip extends StatelessWidget {
  const GbmPinnedGutterClip({
    super.key,
    required this.gutterWidth,
    required this.child,
  });

  final double gutterWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ScrollController? controller = GbmCodeHScroll.maybeControllerOf(
      context,
    );
    if (controller == null) {
      return ClipRect(clipper: _RightOfGutter(gutterWidth), child: child);
    }
    return AnimatedBuilder(
      animation: controller,
      child: child,
      builder: (BuildContext context, Widget? child) => ClipRect(
        clipper: _RightOfGutter(
          (controller.hasClients ? controller.offset : 0) + gutterWidth,
        ),
        child: child,
      ),
    );
  }
}

class _RightOfGutter extends CustomClipper<Rect> {
  const _RightOfGutter(this.left);

  final double left;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(left, 0, size.width, size.height);

  @override
  bool shouldReclip(_RightOfGutter oldClipper) => oldClipper.left != left;
}
