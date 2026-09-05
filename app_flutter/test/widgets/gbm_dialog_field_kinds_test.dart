// worktree-dialogs-spec.html G8's two field kinds neither existed before
// this round: `ro` (read-only, surface-sunken底 + text-secondary文字, no
// border) and `warn` (surface-sunken底 + 1px border-subtle + 2px
// border-left:--warning, r6). GbmDialogWarnField's box shape is lifted from
// lock_worktree_dialog.dart's existing inline Container -- see that file's
// history and gbm_dialog_field_kinds.dart's own doc comment.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/widgets/gbm_dialog_field_kinds.dart';

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
    home: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  group('GbmDialogReadOnlyField', () {
    testWidgets('draws its child inside a surface-sunken box with no border', (
      tester,
    ) async {
      await _pump(tester, const GbmDialogReadOnlyField(child: Text('main')));
      final BuildContext context = tester.element(find.text('main'));
      final GbmColors colors = context.gbmColors;

      final Container box = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(GbmDialogReadOnlyField),
              matching: find.byType(Container),
            )
            .first,
      );
      final BoxDecoration decoration = box.decoration! as BoxDecoration;

      expect(find.text('main'), findsOneWidget);
      expect(decoration.color, colors.surfaceSunken);
      expect(decoration.border, isNull);
    });

    testWidgets('draws a label above the box when given one, in the P6 '
        'field-label style (G3)', (tester) async {
      await _pump(
        tester,
        const GbmDialogReadOnlyField(label: '檔案', child: Text('a/b.dart')),
      );
      final BuildContext context = tester.element(find.text('a/b.dart'));
      final GbmColors colors = context.gbmColors;

      final Text label = tester.widget<Text>(find.text('檔案'));

      expect(label.style?.fontSize, GbmTypography.textXs);
      expect(label.style?.color, colors.textSecondary);
      expect(label.style?.fontWeight, isNot(FontWeight.w600));
    });

    testWidgets('draws no label at all when none is given', (tester) async {
      await _pump(tester, const GbmDialogReadOnlyField(child: Text('main')));

      // Only the child's own Text should be present -- one Text widget.
      expect(find.byType(Text), findsOneWidget);
    });
  });

  group('GbmDialogWarnField', () {
    testWidgets(
      'the outer box has a uniform border-subtle ring at r6, clipped so its '
      'Row children round off with it',
      (tester) async {
        await _pump(tester, const GbmDialogWarnField(message: '會被覆蓋'));
        final BuildContext context = tester.element(find.text('會被覆蓋'));
        final GbmColors colors = context.gbmColors;

        final Container outer = tester.widget<Container>(
          find
              .descendant(
                of: find.byType(GbmDialogWarnField),
                matching: find.byType(Container),
              )
              .first,
        );
        final BoxDecoration decoration = outer.decoration! as BoxDecoration;

        expect(decoration.border, Border.all(color: colors.borderSubtle));
        expect(
          decoration.borderRadius,
          BorderRadius.circular(GbmSpacing.radiusMd),
        );
        expect(outer.clipBehavior, Clip.antiAlias);
      },
    );

    testWidgets('has a 2px warning-coloured left rail', (tester) async {
      await _pump(tester, const GbmDialogWarnField(message: '會被覆蓋'));
      final BuildContext context = tester.element(find.text('會被覆蓋'));
      final GbmColors colors = context.gbmColors;

      final Size rail = tester.getSize(
        find
            .descendant(
              of: find.byType(GbmDialogWarnField),
              matching: find.byType(Container),
            )
            .at(1),
      );
      final Container railContainer = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(GbmDialogWarnField),
              matching: find.byType(Container),
            )
            .at(1),
      );

      expect(rail.width, 2);
      expect(railContainer.color, colors.warning);
    });

    testWidgets('the message sits on a surface-sunken fill', (tester) async {
      await _pump(tester, const GbmDialogWarnField(message: '會被覆蓋'));
      final BuildContext context = tester.element(find.text('會被覆蓋'));
      final GbmColors colors = context.gbmColors;

      final Container fill = tester.widget<Container>(
        find
            .ancestor(of: find.text('會被覆蓋'), matching: find.byType(Container))
            .first,
      );

      expect(fill.color, colors.surfaceSunken);
    });

    testWidgets('renders the given message', (tester) async {
      await _pump(tester, const GbmDialogWarnField(message: '路徑衝突'));

      expect(find.text('路徑衝突'), findsOneWidget);
    });

    // Regression: every real call site sits inside a Column (a dialog
    // body), never bare under Center like _pump above. RenderFlex hands a
    // Column's non-flex children an *unbounded* max-height along the main
    // axis regardless of whether the Column itself is height-bounded --
    // that is how a Column can overflow at all -- and the inner Row's
    // CrossAxisAlignment.stretch demanded a bounded cross-axis constraint
    // to stretch into. _pump's Center gives bounded constraints straight
    // to the widget with no Column in between, so none of the four tests
    // above could see this ([TEST-fixture-cannot-disagree] shape 4).
    testWidgets(
      'renders without a layout exception inside a Column, the shape every '
      'real dialog body actually uses',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
            home: const Scaffold(
              body: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[GbmDialogWarnField(message: '會被覆蓋')],
              ),
            ),
          ),
        );

        expect(tester.takeException(), isNull);
        expect(find.text('會被覆蓋'), findsOneWidget);
      },
    );
  });
}
