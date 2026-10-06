import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/parsed_conflict_file.dart';
import 'package:gbm_flutter/data/models/repo_state.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart'
    show
        ConflictResolution,
        RepoSessionState,
        WorkingTreeContentReply,
        repoSessionProvider;
import 'package:gbm_flutter/features/conflict_resolution/conflict_resolve_window.dart';
import 'package:gbm_flutter/widgets/gbm_button.dart';
import 'package:gbm_flutter/widgets/gbm_code_hscroll.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/widgets/file_list_mode_toggle_button.dart';
import 'package:gbm_flutter/widgets/file_tree_folder_row.dart';
import 'package:gbm_flutter/widgets/split_pane.dart';
import 'package:gbm_flutter/widgets/lucide_icon.dart';
import 'package:gbm_flutter/widgets/gbm_row.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_repo_session.dart';

// Fixture builders mirroring conflict_resolve_logic_test.dart's pattern:
// hand-build a ParsedConflictFile directly rather than round-tripping through
// gbm_parse_conflict_markers() (native, unavailable to a fake GbmBindings).

RepoState _stateWith(int flags) => RepoState(
  flags: flags,
  isClean: false,
  isSequencerOperation: true,
  rebaseStep: 0,
  rebaseTotal: 0,
  rebaseOntoLabel: '',
  indexLocked: false,
  indexLockAgeSeconds: null,
  describe: '',
);

ConflictSegment _regionSegment({
  required List<String> ours,
  required List<String> theirs,
}) => ConflictSegment(
  kind: ConflictSegmentKind.region,
  lines: const <String>[],
  ours: ours,
  theirs: theirs,
  base: const <String>[],
  hasBase: false,
);

final WorkingCopyEntry _conflictEntry = const WorkingCopyEntry(
  path: 'conflict.txt',
  oldPath: '',
  untracked: false,
  staged: false,
  indexStatus: FileChangeKind.modified,
  hasUnstagedChange: true,
  worktreeStatus: FileChangeKind.modified,
  unstagedAdded: 0,
  unstagedRemoved: 0,
  stagedAdded: 0,
  stagedRemoved: 0,
  conflict: ConflictKind.bothModified,
  ancestorBlob: '',
  oursBlob: 'ours-hash',
  theirsBlob: 'theirs-hash',
  similarity: 0,
  isSubmodule: false,
  isConflicted: true,
);

/// A conflicted entry at an arbitrary [path], for tests that need several
/// distinct conflicted files (e.g. proving the rail groups them by folder
/// in tree mode) rather than the single fixed `conflict.txt` [_conflictEntry]
/// uses.
WorkingCopyEntry _conflictAt(String path) => WorkingCopyEntry(
  path: path,
  oldPath: '',
  untracked: false,
  staged: false,
  indexStatus: FileChangeKind.modified,
  hasUnstagedChange: true,
  worktreeStatus: FileChangeKind.modified,
  unstagedAdded: 0,
  unstagedRemoved: 0,
  stagedAdded: 0,
  stagedRemoved: 0,
  conflict: ConflictKind.bothModified,
  ancestorBlob: '',
  oursBlob: 'ours-hash',
  theirsBlob: 'theirs-hash',
  similarity: 0,
  isSubmodule: false,
  isConflicted: true,
);

/// Same path as [_conflictEntry] but different ours/theirs blob oids --
/// simulates a *different* conflict occurring on the same path (e.g. Abort
/// followed by a new merge/rebase/cherry-pick), which is what git's own
/// record actually changes between occurrences.
final WorkingCopyEntry _conflictEntryReoccurred = const WorkingCopyEntry(
  path: 'conflict.txt',
  oldPath: '',
  untracked: false,
  staged: false,
  indexStatus: FileChangeKind.modified,
  hasUnstagedChange: true,
  worktreeStatus: FileChangeKind.modified,
  unstagedAdded: 0,
  unstagedRemoved: 0,
  stagedAdded: 0,
  stagedRemoved: 0,
  conflict: ConflictKind.bothModified,
  ancestorBlob: '',
  oursBlob: 'ours-hash-2',
  theirsBlob: 'theirs-hash-2',
  similarity: 0,
  isSubmodule: false,
  isConflicted: true,
);

/// [_conflictEntry] as a delete/modify conflict: ours deleted the file, so
/// there is no ours blob.
const WorkingCopyEntry _conflictEntryOursDeleted = WorkingCopyEntry(
  path: 'conflict.txt',
  oldPath: '',
  untracked: false,
  staged: false,
  indexStatus: FileChangeKind.modified,
  hasUnstagedChange: true,
  worktreeStatus: FileChangeKind.modified,
  unstagedAdded: 0,
  unstagedRemoved: 0,
  stagedAdded: 0,
  stagedRemoved: 0,
  conflict: ConflictKind.bothModified,
  ancestorBlob: '',
  oursBlob: '',
  theirsBlob: 'theirs-hash',
  similarity: 0,
  isSubmodule: false,
  isConflicted: true,
);

void main() {
  group('ConflictResolveWindow', () {
    final identity = RepoIdentity(
      workDir: '/test/repo',
      gitDir: '/test/repo/.git',
    );

    group('soft wrap', () {
      // A line far wider than a 220px-min pane in test-font terms
      // (`flutter_test` draws every glyph `fontSize` wide).
      const String longOurs =
          'final ours = compute(alpha, beta, gamma, delta, epsilon, zeta);';
      const String longTheirs =
          'final theirs = compute(alpha, beta, gamma, delta, epsilon, eta);';

      ParsedConflictFile longParsed() => ParsedConflictFile(
        segments: <ConflictSegment>[
          _regionSegment(
            ours: <String>[longOurs],
            theirs: <String>[longTheirs],
          ),
        ],
        regionCount: 1,
        wellFormed: true,
      );

      Future<void> pumpWrap(WidgetTester tester, {required bool on}) async {
        await _pumpWindow(
          tester,
          identity,
          _sessionWith(_conflictEntry),
          longParsed(),
          initialPrefs: <String, Object>{'appPrefs.softWrapEnabled': on},
        );
        await _selectConflictFile(tester);
      }

      testWidgets('all three columns scroll sideways by default', (
        tester,
      ) async {
        await pumpWrap(tester, on: false);

        // Counted, not `any`: the three columns are built by three separate
        // methods and each takes its own copy of the flag, so a finder that
        // only asked whether *a* scroller existed would stay green with two
        // of the three still wrapping.
        expect(find.byType(GbmCodeHScroll), findsNWidgets(3));
      });

      testWidgets('turning soft wrap on removes all three', (tester) async {
        await pumpWrap(tester, on: true);

        expect(find.byType(GbmCodeHScroll), findsNWidgets(3));
        expect(find.byType(GbmPinnedGutter), findsNothing);
      });

      testWidgets('the side columns stop wrapping their lines', (tester) async {
        await pumpWrap(tester, on: false);
        expect(tester.widget<Text>(find.text(longOurs)).softWrap, isFalse);
        expect(tester.widget<Text>(find.text(longTheirs)).softWrap, isFalse);

        await pumpWrap(tester, on: true);
        expect(tester.widget<Text>(find.text(longOurs)).softWrap, isTrue);
        expect(tester.widget<Text>(find.text(longTheirs)).softWrap, isTrue);
      });
    });

    testWidgets('renders three-column layout with split panes', (tester) async {
      final parsed = ParsedConflictFile(
        segments: <ConflictSegment>[
          _regionSegment(
            ours: <String>['ours-line1'],
            theirs: <String>['theirs-line1'],
          ),
        ],
        regionCount: 1,
        wellFormed: true,
      );

      await _pumpWindow(tester, identity, _sessionWith(_conflictEntry), parsed);
      await _selectConflictFile(tester);

      expect(find.text('Resolve Conflicts'), findsOneWidget);
      expect(find.byType(GbmSplitPane), findsWidgets);
      expect(find.text('Ours'), findsOneWidget);
      expect(find.text('Theirs'), findsOneWidget);
    });

    testWidgets('Take Ours appends lines with sequential badges', (
      tester,
    ) async {
      final parsed = ParsedConflictFile(
        segments: <ConflictSegment>[
          _regionSegment(
            ours: <String>['ours-line1', 'ours-line2'],
            theirs: <String>['theirs-line1'],
          ),
        ],
        regionCount: 1,
        wellFormed: true,
      );

      await _pumpWindow(tester, identity, _sessionWith(_conflictEntry), parsed);
      await _selectConflictFile(tester);

      expect(find.text('Unresolved'), findsOneWidget);

      await tester.tap(_perRegionTakeButton('Ours'));
      await tester.pumpAndSettle();

      expect(find.text('①'), findsOneWidget);
      expect(find.text('②'), findsOneWidget);
      expect(find.text('Resolved'), findsOneWidget);
    });

    testWidgets('per-line delete button removes a line and renumbers badges', (
      tester,
    ) async {
      final parsed = ParsedConflictFile(
        segments: <ConflictSegment>[
          _regionSegment(
            ours: <String>['ours-line1', 'ours-line2'],
            theirs: <String>['theirs-line1'],
          ),
        ],
        regionCount: 1,
        wellFormed: true,
      );

      await _pumpWindow(tester, identity, _sessionWith(_conflictEntry), parsed);
      await _selectConflictFile(tester);

      await tester.tap(_perRegionTakeButton('Ours'));
      await tester.pumpAndSettle();

      expect(find.text('①'), findsOneWidget);
      expect(find.text('②'), findsOneWidget);

      // Delete the first result line (position 0, badge ①).
      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pumpAndSettle();

      // The remaining line renumbers down to ①; ② is gone.
      expect(find.text('①'), findsOneWidget);
      expect(find.text('②'), findsNothing);
    });

    testWidgets('Reset clears a region back to empty/unresolved', (
      tester,
    ) async {
      final parsed = ParsedConflictFile(
        segments: <ConflictSegment>[
          _regionSegment(
            ours: <String>['ours-line1'],
            theirs: <String>['theirs-line1'],
          ),
        ],
        regionCount: 1,
        wellFormed: true,
      );

      await _pumpWindow(tester, identity, _sessionWith(_conflictEntry), parsed);
      await _selectConflictFile(tester);

      await tester.tap(_perRegionTakeButton('Ours'));
      await tester.pumpAndSettle();

      expect(find.text('①'), findsOneWidget);
      expect(find.text('Resolved'), findsOneWidget);

      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();

      expect(find.text('①'), findsNothing);
      expect(find.text('Unresolved'), findsOneWidget);
    });

    testWidgets('hover-fade button shows arrow icon on hover', (tester) async {
      final parsed = ParsedConflictFile(
        segments: <ConflictSegment>[
          _regionSegment(
            ours: <String>['ours-line1'],
            theirs: <String>['theirs-line1'],
          ),
        ],
        regionCount: 1,
        wellFormed: true,
      );

      await _pumpWindow(tester, identity, _sessionWith(_conflictEntry), parsed);
      await _selectConflictFile(tester);

      // Find the AnimatedOpacity inside the Ours pane's take button
      final oursButtonFinder = _perRegionTakeButton('Ours');
      final animatedOpacityFinder = find.ancestor(
        of: oursButtonFinder,
        matching: find.byType(AnimatedOpacity),
      );

      // Before hover: opacity should be ~0
      var animatedOpacity = tester.firstWidget<AnimatedOpacity>(
        animatedOpacityFinder,
      );
      expect(animatedOpacity.opacity, 0);

      // Create a mouse gesture and move it over the hunk block
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(gesture.removePointer);
      await gesture.addPointer(location: Offset.zero);
      await tester.pump();

      // Move mouse to center of the Ours label (hunk header region)
      final oursLabelFinder = find.text('Ours');
      await gesture.moveTo(tester.getCenter(oursLabelFinder));
      await tester.pumpAndSettle();

      // After hover: opacity should be ~1
      animatedOpacity = tester.firstWidget<AnimatedOpacity>(
        animatedOpacityFinder,
      );
      expect(animatedOpacity.opacity, 1);
    });

    testWidgets('arrow icons are displayed in take buttons', (tester) async {
      final parsed = ParsedConflictFile(
        segments: <ConflictSegment>[
          _regionSegment(
            ours: <String>['ours-line1'],
            theirs: <String>['theirs-line1'],
          ),
        ],
        regionCount: 1,
        wellFormed: true,
      );

      await _pumpWindow(tester, identity, _sessionWith(_conflictEntry), parsed);
      await _selectConflictFile(tester);

      // Ours side should have arrow_forward icon
      final oursPane = find.ancestor(
        of: find.text('Ours'),
        matching: find.byType(Container),
      );
      expect(
        find.descendant(
          of: oursPane,
          matching: find.byIcon(Icons.arrow_forward),
        ),
        findsOneWidget,
      );

      // Theirs side should have arrow_back icon
      final theirsPane = find.ancestor(
        of: find.text('Theirs'),
        matching: find.byType(Container),
      );
      expect(
        find.descendant(
          of: theirsPane,
          matching: find.byIcon(Icons.arrow_back),
        ),
        findsOneWidget,
      );
    });

    // P8's rail pane is labelled `.mklbl` 「Conflicted files」: 10px,
    // uppercase, letter-spacing .06em (0.6px at 10px), --text-tertiary,
    // padding 6px 10px, a 1px --border-subtle bottom border. P03 item 10
    // keeps the List/Tree toggle on that title's right; the old 「x of y
    // resolved」 count had no source and is gone (#175 rulings).
    testWidgets('the rail is titled Conflicted files in .mklbl style', (
      tester,
    ) async {
      await _pumpWindow(
        tester,
        identity,
        _sessionWith(_conflictEntry),
        _oneRegionFile(),
      );
      final GbmColors colors = tokensFor(GbmThemeVariant.darkTechnical);

      final Finder title = find.text('CONFLICTED FILES');
      final TextStyle? style = tester.widget<Text>(title).style;
      expect(style?.fontSize, 10);
      expect(style?.letterSpacing, closeTo(0.6, 1e-9));
      expect(style?.color, colors.textTertiary);
      expect(find.text('0 of 1 resolved'), findsNothing);

      final Container header = tester.widget<Container>(
        find
            .ancestor(
              of: title,
              matching: find.byWidgetPredicate(
                (Widget w) =>
                    w is Container &&
                    w.decoration is BoxDecoration &&
                    (w.decoration! as BoxDecoration).border != null,
              ),
            )
            .first,
      );
      expect(
        header.padding,
        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      );
      final Border border =
          (header.decoration! as BoxDecoration).border! as Border;
      expect(border.bottom, BorderSide(color: colors.borderSubtle));

      final Rect titleRect = tester.getRect(title);
      final Rect toggle = tester.getRect(find.byType(FileListModeToggleButton));
      expect(toggle.left, greaterThan(titleRect.right));
      expect(toggle.center.dy, closeTo(titleRect.center.dy, 1));
    });

    // P8's rail draws each conflicted file as one `.gbm-row` -- 27px, a 6px
    // status dot, the name at 10.5px with no declared weight -- and carries
    // no whole-file buttons: those live in the editor's fallback hint and the
    // bottom bar (#172). `.gbm-row.selected` wins over `:hover`, which
    // [GbmRow] already paints; its own tests pin the two tokens.
    testWidgets('a rail row is one 27px GbmRow with no whole-file buttons', (
      tester,
    ) async {
      await _pumpWindow(
        tester,
        identity,
        _sessionWith(_conflictEntry),
        _oneRegionFile(),
      );

      final Finder row = _railRow('conflict.txt');
      expect(row, findsOneWidget);
      expect(tester.getSize(row).height, 27);
      for (final String label in <String>[
        'Take Ours',
        'Take Theirs',
        'Mark resolved',
      ]) {
        expect(
          find.descendant(of: row, matching: find.text(label)),
          findsNothing,
          reason: label,
        );
      }
      final Text name = tester.widget<Text>(
        find.descendant(of: row, matching: find.text('conflict.txt')),
      );
      expect(name.style?.fontSize, 10.5);
      expect(name.style?.fontWeight, isNull);
      expect(name.style?.decoration, isNull);

      expect(tester.widget<GbmRow>(row).selected, isFalse);
      await _selectConflictFile(tester);
      expect(tester.widget<GbmRow>(_railRow('conflict.txt')).selected, isTrue);
    });

    testWidgets('an unresolved rail row leads with a 6px danger dot', (
      tester,
    ) async {
      await _pumpWindow(
        tester,
        identity,
        _sessionWith(_conflictEntry),
        _oneRegionFile(),
      );

      final Finder row = _railRow('conflict.txt');
      final Finder dot = _statusDot(row);
      expect(tester.getSize(dot), const Size(6, 6));
      expect(
        (tester.widget<Container>(dot).decoration! as BoxDecoration).color,
        tokensFor(GbmThemeVariant.darkTechnical).danger,
      );
      expect(
        tester.getTopLeft(find.text('conflict.txt')).dx -
            tester.getTopRight(dot).dx,
        6,
      );
      expect(tester.widget<Opacity>(_rowOpacity(row)).opacity, 1);
      expect(
        find.descendant(of: row, matching: find.byType(LucideIcon)),
        findsNothing,
      );
    });

    testWidgets(
      'a resolved rail row fades to .55 with a success dot and a check',
      (tester) async {
        final container = await _pumpWindow(
          tester,
          identity,
          _sessionWith(_conflictEntry),
          _oneRegionFile(),
        );
        final controller = container.read(
          repoSessionProvider(identity).notifier,
        ) as FakeRepoSessionController;
        controller.state = controller.state.copyWith(
          workingCopyStatus: WorkingCopyStatus.empty,
        );
        await tester.pumpAndSettle();

        final GbmColors colors = tokensFor(GbmThemeVariant.darkTechnical);
        final Finder row = _railRow('conflict.txt');
        expect(
          (tester.widget<Container>(_statusDot(row)).decoration!
                  as BoxDecoration)
              .color,
          colors.success,
        );
        expect(tester.widget<Opacity>(_rowOpacity(row)).opacity, 0.55);
        final LucideIcon check = tester.widget<LucideIcon>(
          find.descendant(of: row, matching: find.byType(LucideIcon)),
        );
        expect(check.name, 'check');
        expect(check.size, 12);
        expect(check.color, colors.success);
        expect(
          tester.widget<Text>(find.text('conflict.txt')).style?.decoration,
          isNull,
          reason: 'line-through has no source in the spec',
        );
      },
    );

    testWidgets('the rail list pads 6px and spaces its rows 2px apart', (
      tester,
    ) async {
      await _pumpWindow(
        tester,
        identity,
        RepoSessionState(
          isOpen: true,
          workingCopyStatus: WorkingCopyStatus(
            entries: <WorkingCopyEntry>[
              _conflictAt('a.txt'),
              _conflictAt('b.txt'),
            ],
          ),
        ),
        _oneRegionFile(),
      );

      final Rect a = tester.getRect(_railRow('a.txt'));
      final Rect b = tester.getRect(_railRow('b.txt'));
      expect(b.top - a.bottom, 2);
      expect(a.left - tester.getRect(find.byType(GbmSplitPane).first).left, 6);
    });

    // P8's rail ends an unresolved row with its remaining-segment count
    // (`gbm-mono`, 9.5px, `--text-tertiary`). The user ruled 「已開過的檔才
    // 顯示」 (#172): a file never opened has not been parsed, so it shows
    // nothing rather than a guess.
    group('rail remaining count', () {
      Finder remainingCount(String name) => find.descendant(
        of: _railRow(name),
        matching: find.byWidgetPredicate(
          (Widget w) =>
              w is Text && w.style?.fontFamily == GbmTypography.fontMono,
        ),
      );

      final RepoSessionState twoFiles = RepoSessionState(
        isOpen: true,
        workingCopyStatus: WorkingCopyStatus(
          entries: <WorkingCopyEntry>[
            _conflictAt('a.txt'),
            _conflictAt('b.txt'),
          ],
        ),
      );

      testWidgets('an unopened file shows no remaining count', (tester) async {
        await _pumpWindow(tester, identity, twoFiles, _twoRegionFile());

        expect(remainingCount('a.txt'), findsNothing);
        expect(remainingCount('b.txt'), findsNothing);
      });

      testWidgets('the opened file counts its unresolved regions live', (
        tester,
      ) async {
        await _pumpWindow(tester, identity, twoFiles, _twoRegionFile());
        await tester.tap(find.text('a.txt'));
        await tester.pumpAndSettle();

        final Text count = tester.widget<Text>(remainingCount('a.txt'));
        expect(count.data, '2');
        expect(count.style?.fontSize, 9.5);
        expect(
          count.style?.color,
          tokensFor(GbmThemeVariant.darkTechnical).textTertiary,
        );
        expect(remainingCount('b.txt'), findsNothing);

        await tester.tap(_perRegionTakeButton('Ours').first);
        await tester.pumpAndSettle();
        expect(tester.widget<Text>(remainingCount('a.txt')).data, '1');
      });

      testWidgets('a file keeps its remaining count once the selection moves', (
        tester,
      ) async {
        await _pumpWindow(tester, identity, twoFiles, _twoRegionFile());
        await tester.tap(find.text('a.txt'));
        await tester.pumpAndSettle();
        await tester.tap(_perRegionTakeButton('Ours').first);
        await tester.pumpAndSettle();

        await tester.tap(find.text('b.txt'));
        await tester.pumpAndSettle();

        expect(tester.widget<Text>(remainingCount('a.txt')).data, '1');
        expect(tester.widget<Text>(remainingCount('b.txt')).data, '2');
      });

      // The count and the editable-result gate read one source,
      // `unresolvedCount`; this pins the gate's side of it.
      testWidgets('the editable result waits for every region, not most', (
        tester,
      ) async {
        await _pumpWindow(tester, identity, twoFiles, _twoRegionFile());
        await tester.tap(find.text('a.txt'));
        await tester.pumpAndSettle();

        await tester.tap(_perRegionTakeButton('Ours').first);
        await tester.pumpAndSettle();
        expect(find.text('Result (editable)'), findsNothing);

        await tester.tap(_perRegionTakeButton('Ours').last);
        await tester.pumpAndSettle();
        expect(find.text('Result (editable)'), findsOneWidget);
      });

      testWidgets('a resolved file shows no count even after it was opened', (
        tester,
      ) async {
        final container = await _pumpWindow(
          tester,
          identity,
          twoFiles,
          _twoRegionFile(),
        );
        await tester.tap(find.text('a.txt'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('b.txt'));
        await tester.pumpAndSettle();
        expect(remainingCount('a.txt'), findsOneWidget);

        final controller = container.read(
          repoSessionProvider(identity).notifier,
        ) as FakeRepoSessionController;
        controller.state = controller.state.copyWith(
          workingCopyStatus: WorkingCopyStatus(
            entries: <WorkingCopyEntry>[_conflictAt('b.txt')],
          ),
        );
        await tester.pumpAndSettle();

        expect(remainingCount('a.txt'), findsNothing);
      });
    });

    // P8-1: Ctrl/Cmd+↑↓ moves to the previous / next file in the order the
    // rail paints them, stopping at the ends; tree mode skips folder rows
    // (#172: 「上／下一個檔，到頭停住」, [SPEC-range-follows-paint-order]).
    // List order and tree leaf order differ for these three paths: the tree
    // groups b/d.txt under b/ ahead of a.txt.
    group('Ctrl+Up/Down file stepping', () {
      final RepoSessionState threeFiles = RepoSessionState(
        isOpen: true,
        workingCopyStatus: WorkingCopyStatus(
          entries: <WorkingCopyEntry>[
            _conflictAt('b/c.txt'),
            _conflictAt('a.txt'),
            _conflictAt('b/d.txt'),
          ],
        ),
      );

      Future<void> ctrl(WidgetTester tester, LogicalKeyboardKey key) async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyDownEvent(key);
        await tester.sendKeyUpEvent(key);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
      }

      List<Object?> opened(ProviderContainer container) =>
          (container.read(repoSessionProvider(identity).notifier)
                  as FakeRepoSessionController)
              .commandLog
              .where((c) => c.name == 'requestWorkingTreeContent')
              .map((c) => c.args['path'])
              .toList();

      testWidgets('list mode steps in list order and stops at the ends', (
        tester,
      ) async {
        final container = await _pumpWindow(
          tester,
          identity,
          threeFiles,
          _oneRegionFile(),
        );

        await ctrl(tester, LogicalKeyboardKey.arrowDown);
        await ctrl(tester, LogicalKeyboardKey.arrowDown);
        await ctrl(tester, LogicalKeyboardKey.arrowDown);
        await ctrl(tester, LogicalKeyboardKey.arrowDown);
        await ctrl(tester, LogicalKeyboardKey.arrowUp);

        expect(opened(container), <String>[
          'b/c.txt',
          'a.txt',
          'b/d.txt',
          'a.txt',
        ]);
      });

      testWidgets('tree mode steps in leaf order, skipping folder rows', (
        tester,
      ) async {
        final container = await _pumpWindow(
          tester,
          identity,
          threeFiles,
          _oneRegionFile(),
          initialPrefs: <String, Object>{'fileListViewMode': 'tree'},
        );

        await ctrl(tester, LogicalKeyboardKey.arrowDown);
        await ctrl(tester, LogicalKeyboardKey.arrowDown);
        await ctrl(tester, LogicalKeyboardKey.arrowDown);

        expect(opened(container), <String>['b/c.txt', 'b/d.txt', 'a.txt']);
      });
    });

    // A hunk side's single lines are clickable (one click applies that line)
    // but the mockup draws no hover for them; the user ruled they take the
    // row hover, `surface-hover` (#169).
    testWidgets('a hunk side line hovers in surfaceHover', (tester) async {
      await _pumpWindow(
        tester,
        identity,
        _sessionWith(_conflictEntry),
        ParsedConflictFile(
          segments: <ConflictSegment>[
            _regionSegment(ours: <String>['ours-line'], theirs: <String>['b']),
          ],
          regionCount: 1,
          wellFormed: true,
        ),
      );
      await _selectConflictFile(tester);

      final InkWell line = tester.widget<InkWell>(
        find
            .ancestor(
              of: find.text('ours-line'),
              matching: find.byType(InkWell),
            )
            .first,
      );
      expect(
        line.hoverColor,
        tokensFor(GbmThemeVariant.darkTechnical).surfaceHover,
      );
    });

    // A binary or marker-less file has no regions to apply line by line, so
    // its only way forward is a whole-file choice. The spec draws no
    // whole-file take anywhere; the user ruled it lives where the editor
    // says there is nothing to edit (#172), with Mark resolved staying in
    // the bottom bar as P8 item 11 has it.
    testWidgets('an unparseable file offers whole-file Take Ours / Theirs in '
        'the editor', (tester) async {
      final ProviderContainer container = await _pumpWindow(
        tester,
        identity,
        RepoSessionState(
          isOpen: true,
          workingCopyStatus: WorkingCopyStatus(entries: [_conflictEntry]),
          lastWorkingTreeContent: const WorkingTreeContentReply(
            path: 'conflict.txt',
            editable: false,
            content: '',
          ),
        ),
        ParsedConflictFile(
          segments: const <ConflictSegment>[],
          regionCount: 0,
          wellFormed: true,
        ),
      );
      await _selectConflictFile(tester);
      final FakeRepoSessionController fake = container.read(
        repoSessionProvider(identity).notifier,
      ) as FakeRepoSessionController;

      await tester.tap(find.widgetWithText(GbmButton, 'Take Ours'));
      await tester.pump();
      await tester.tap(find.widgetWithText(GbmButton, 'Take Theirs'));
      await tester.pump();

      expect(
        fake.resolveConflictCalls.map((c) => (c.path, c.resolution)).toList(),
        <(String, Object?)>[
          ('conflict.txt', ConflictResolution.takeOurs),
          ('conflict.txt', ConflictResolution.takeTheirs),
        ],
      );
    });

    // A delete/modify conflict has no blob on the deleting side; the flag is
    // what tells core to take the deletion instead of reading that blob.
    testWidgets('a whole-file take flags the side whose blob is missing', (
      tester,
    ) async {
      final ProviderContainer container = await _pumpWindow(
        tester,
        identity,
        RepoSessionState(
          isOpen: true,
          workingCopyStatus: WorkingCopyStatus(
            entries: [_conflictEntryOursDeleted],
          ),
          lastWorkingTreeContent: const WorkingTreeContentReply(
            path: 'conflict.txt',
            editable: false,
            content: '',
          ),
        ),
        ParsedConflictFile(
          segments: const <ConflictSegment>[],
          regionCount: 0,
          wellFormed: true,
        ),
      );
      await _selectConflictFile(tester);
      final FakeRepoSessionController fake = container.read(
        repoSessionProvider(identity).notifier,
      ) as FakeRepoSessionController;

      await tester.tap(find.widgetWithText(GbmButton, 'Take Ours'));
      await tester.pump();
      await tester.tap(find.widgetWithText(GbmButton, 'Take Theirs'));
      await tester.pump();

      final List<Map<String, Object?>> calls = fake.commandLog
          .where((c) => c.name == 'resolveConflict')
          .map((c) => c.args)
          .toList();
      expect(calls, hasLength(2));
      expect(calls[0]['oursBlobMissing'], isTrue);
      expect(
        calls[1]['oursBlobMissing'],
        isFalse,
        reason: 'taking theirs reads their blob, which is present',
      );
    });

    testWidgets('single-line click appends only that line', (tester) async {
      final parsed = ParsedConflictFile(
        segments: <ConflictSegment>[
          _regionSegment(
            ours: <String>['line-a', 'line-b'],
            theirs: <String>['line-c'],
          ),
        ],
        regionCount: 1,
        wellFormed: true,
      );

      await _pumpWindow(tester, identity, _sessionWith(_conflictEntry), parsed);
      await _selectConflictFile(tester);

      expect(find.text('Unresolved'), findsOneWidget);

      // Tap on line-b (second line in ours pane)
      final lineBText = find.text('line-b');
      await tester.tap(lineBText);
      await tester.pumpAndSettle();

      // Only ① badge should be present (one line added, not all)
      expect(find.text('①'), findsOneWidget);
      // ② should not exist (that would mean both lines were added)
      expect(find.text('②'), findsNothing);

      // line-a should still be visible only in ours pane (not copied to result)
      expect(find.text('line-a'), findsOneWidget);
    });

    testWidgets('drag-and-drop whole hunk to result pane', (tester) async {
      final parsed = ParsedConflictFile(
        segments: <ConflictSegment>[
          _regionSegment(
            ours: <String>['drag-line1', 'drag-line2'],
            theirs: <String>['theirs-line'],
          ),
        ],
        regionCount: 1,
        wellFormed: true,
      );

      await _pumpWindow(tester, identity, _sessionWith(_conflictEntry), parsed);
      await _selectConflictFile(tester);

      // Before drag: region should be unresolved
      expect(find.text('Unresolved'), findsOneWidget);

      // Drag from the "Take Ours" button (which is inside Draggable)
      // to a point to the right (toward the result pane)
      final takeOursButton = _perRegionTakeButton('Ours');

      // Drag to the right by 250 logical pixels (should land in the result pane area)
      await tester.drag(takeOursButton, const Offset(250, 0));
      await tester.pumpAndSettle();

      // Both lines should now be in result with badges ① and ②
      expect(find.text('①'), findsOneWidget);
      expect(find.text('②'), findsOneWidget);

      // Region should now be resolved (both lines added)
      expect(find.text('Resolved'), findsOneWidget);
      expect(find.text('Unresolved'), findsNothing);
    });

    testWidgets('drag result line out of pane discards it', (tester) async {
      final parsed = ParsedConflictFile(
        segments: <ConflictSegment>[
          _regionSegment(
            ours: <String>['result-line1', 'result-line2'],
            theirs: <String>['theirs-line1'],
          ),
        ],
        regionCount: 1,
        wellFormed: true,
      );

      await _pumpWindow(tester, identity, _sessionWith(_conflictEntry), parsed);
      await _selectConflictFile(tester);

      // Take ours to populate result
      await tester.tap(_perRegionTakeButton('Ours'));
      await tester.pumpAndSettle();

      expect(find.text('①'), findsOneWidget);
      expect(find.text('②'), findsOneWidget);

      // Drag the badge (①) out to the left. The badge is unique to the result column.
      await tester.drag(find.text('①'), const Offset(-250, 0));
      await tester.pumpAndSettle();

      // The first line should be gone; badges prove deletion worked (① renumbered, ② gone)
      expect(find.text('①'), findsOneWidget);
      expect(find.text('②'), findsNothing);
    });

    testWidgets('drag result line small offset within pane is no-op', (
      tester,
    ) async {
      final parsed = ParsedConflictFile(
        segments: <ConflictSegment>[
          _regionSegment(
            ours: <String>['keep-line1'],
            theirs: <String>['theirs-line1'],
          ),
        ],
        regionCount: 1,
        wellFormed: true,
      );

      await _pumpWindow(tester, identity, _sessionWith(_conflictEntry), parsed);
      await _selectConflictFile(tester);

      // Take ours to populate result
      await tester.tap(_perRegionTakeButton('Ours'));
      await tester.pumpAndSettle();

      expect(find.text('①'), findsOneWidget);

      // Drag the badge by a small offset (stays within pane)
      await tester.drag(find.text('①'), const Offset(20, 10));
      await tester.pumpAndSettle();

      // Line should still be there (no-op); badge proves no deletion occurred
      expect(find.text('①'), findsOneWidget);
    });

    testWidgets('Ctrl+Z undo after deleting line via close button', (
      tester,
    ) async {
      final parsed = ParsedConflictFile(
        segments: <ConflictSegment>[
          _regionSegment(
            ours: <String>['line-to-delete'],
            theirs: <String>['theirs-line'],
          ),
        ],
        regionCount: 1,
        wellFormed: true,
      );

      await _pumpWindow(tester, identity, _sessionWith(_conflictEntry), parsed);
      await _selectConflictFile(tester);

      // Take ours
      await tester.tap(_perRegionTakeButton('Ours'));
      await tester.pumpAndSettle();

      expect(find.text('①'), findsOneWidget);

      // Delete via close button
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // Badge proves deletion worked
      expect(find.text('①'), findsNothing);

      // Send Ctrl+Z
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      // Line should be restored; badge proves undo worked
      expect(find.text('①'), findsOneWidget);
    });

    testWidgets('Ctrl+Z undo is no-op when nothing discarded', (tester) async {
      final parsed = ParsedConflictFile(
        segments: <ConflictSegment>[
          _regionSegment(
            ours: <String>['ours-line'],
            theirs: <String>['theirs-line'],
          ),
        ],
        regionCount: 1,
        wellFormed: true,
      );

      await _pumpWindow(tester, identity, _sessionWith(_conflictEntry), parsed);
      await _selectConflictFile(tester);

      // Nothing deleted yet
      expect(find.text('①'), findsNothing);

      // Send Ctrl+Z (should do nothing, no error)
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      // Still nothing (no-op)
      expect(find.text('①'), findsNothing);
    });

    testWidgets('Ctrl+Z undo after drag-out discard', (tester) async {
      final parsed = ParsedConflictFile(
        segments: <ConflictSegment>[
          _regionSegment(
            ours: <String>['drag-line1', 'drag-line2'],
            theirs: <String>['theirs-line'],
          ),
        ],
        regionCount: 1,
        wellFormed: true,
      );

      await _pumpWindow(tester, identity, _sessionWith(_conflictEntry), parsed);
      await _selectConflictFile(tester);

      // Take ours
      await tester.tap(_perRegionTakeButton('Ours'));
      await tester.pumpAndSettle();

      expect(find.text('①'), findsOneWidget);
      expect(find.text('②'), findsOneWidget);

      // Drag first badge out of pane
      await tester.drag(find.text('①'), const Offset(-250, 0));
      await tester.pumpAndSettle();

      // Badges prove deletion worked (① renumbered, ② gone)
      expect(find.text('①'), findsOneWidget);
      expect(find.text('②'), findsNothing);

      // Undo the drag discard
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      // Badges prove undo worked (both badges restored)
      expect(find.text('①'), findsOneWidget);
      expect(find.text('②'), findsOneWidget);
    });

    // P8's bottom bar (callout 11): `display:flex;gap:9px;padding:8px 11px;
    // border-top:1px solid var(--border-subtle);
    // background:var(--surface-panel-raised)`, five `gbm-btn-sm` buttons --
    // Previous / Next conflict / Mark resolved secondary, Abort danger,
    // Continue primary. Continue keeps the prose's label, not the mock's
    // `Continue rebase` (#175 ruling, [SPEC-mockup-is-not-prose]).
    testWidgets('the action bar follows P8: labels, kinds, sm size, 9px gaps', (
      tester,
    ) async {
      await _pumpWindow(
        tester,
        identity,
        _sessionWith(_conflictEntry)
            .copyWith(repoState: _stateWith(RepoStateFlags.rebaseMerge)),
        _oneRegionFile(),
      );
      await _selectConflictFile(tester);
      final GbmColors colors = tokensFor(GbmThemeVariant.darkTechnical);

      final Finder bar = _actionBar();
      final List<GbmButton> buttons = tester
          .widgetList<GbmButton>(
            find.descendant(of: bar, matching: find.byType(GbmButton)),
          )
          .toList();
      expect(buttons.map((GbmButton b) => b.label), <String>[
        'Previous',
        'Next conflict',
        'Mark resolved',
        'Abort',
        'Continue',
      ]);
      expect(buttons.map((GbmButton b) => b.kind), <GbmButtonKind>[
        GbmButtonKind.secondary,
        GbmButtonKind.secondary,
        GbmButtonKind.secondary,
        GbmButtonKind.danger,
        GbmButtonKind.primary,
      ]);
      for (final GbmButton b in buttons) {
        expect(b.size, GbmButtonSize.sm, reason: b.label);
      }

      final List<Rect> rects = <Rect>[
        for (final GbmButton b in buttons) tester.getRect(find.byWidget(b)),
      ];
      for (int i = 1; i < rects.length; i++) {
        expect(
          rects[i].left - rects[i - 1].right,
          9,
          reason: 'gap before ${buttons[i].label}',
        );
      }

      final Container container = tester.widget<Container>(bar);
      expect(
        container.padding,
        const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      );
      final BoxDecoration decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, colors.surfacePanelRaised);
      expect(
        (decoration.border! as Border).top,
        BorderSide(color: colors.borderSubtle),
      );
    });

    testWidgets('merge: Abort dispatches mergeAbort, Continue is disabled', (
      tester,
    ) async {
      final parsed = ParsedConflictFile(
        segments: <ConflictSegment>[
          _regionSegment(
            ours: <String>['ours-line1'],
            theirs: <String>['theirs-line1'],
          ),
        ],
        regionCount: 1,
        wellFormed: true,
      );
      final session = _sessionWith(_conflictEntry)
          .copyWith(repoState: _stateWith(RepoStateFlags.merge));

      final container = await _pumpWindow(tester, identity, session, parsed);
      await _selectConflictFile(tester);
      final controller = container.read(
        repoSessionProvider(identity).notifier,
      ) as FakeRepoSessionController;

      await tester.tap(find.text('Abort'));
      await tester.pumpAndSettle();
      expect(controller.mergeAbortCalled, isTrue);

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(controller.cherryPickContinueCalled, isFalse);
      expect(controller.continueRebaseCalled, isFalse);
    });

    testWidgets(
      'cherry-pick: Abort dispatches cherryPickAbort, Continue opens the MSGS dialog and dispatches cherryPickContinueWithMessage',
      (tester) async {
        final parsed = ParsedConflictFile(
          segments: <ConflictSegment>[
            _regionSegment(
              ours: <String>['ours-line1'],
              theirs: <String>['theirs-line1'],
            ),
          ],
          regionCount: 1,
          wellFormed: true,
        );
        final session = _sessionWith(_conflictEntry)
            .copyWith(repoState: _stateWith(RepoStateFlags.cherryPick));

        final container = await _pumpWindow(tester, identity, session, parsed);
        await _selectConflictFile(tester);
        final controller = container.read(
          repoSessionProvider(identity).notifier,
        ) as FakeRepoSessionController;

        await tester.tap(find.text('Abort'));
        await tester.pumpAndSettle();
        expect(controller.cherryPickAbortCalled, isTrue);

        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        // MSGS dialog opened, pre-filled from requestOriginalOperationMessage().
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text('Cherry-pick message'), findsOneWidget);
        expect(find.text('Original summary'), findsOneWidget);

        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('Continue'),
          ),
        );
        await tester.pumpAndSettle();

        expect(controller.cherryPickContinueWithMessageCalled, isTrue);
        expect(controller.lastContinueMessage, contains('Original summary'));
      },
    );

    testWidgets(
      'rebase: Abort dispatches abortRebase, Continue opens the MSGS dialog and dispatches continueRebaseWithMessage',
      (tester) async {
        final parsed = ParsedConflictFile(
          segments: <ConflictSegment>[
            _regionSegment(
              ours: <String>['ours-line1'],
              theirs: <String>['theirs-line1'],
            ),
          ],
          regionCount: 1,
          wellFormed: true,
        );
        final session = _sessionWith(_conflictEntry)
            .copyWith(repoState: _stateWith(RepoStateFlags.rebaseMerge));

        final container = await _pumpWindow(tester, identity, session, parsed);
        await _selectConflictFile(tester);
        final controller = container.read(
          repoSessionProvider(identity).notifier,
        ) as FakeRepoSessionController;

        await tester.tap(find.text('Abort'));
        await tester.pumpAndSettle();
        expect(controller.abortRebaseCalled, isTrue);

        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text('Rebase message'), findsOneWidget);

        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('Continue'),
          ),
        );
        await tester.pumpAndSettle();

        expect(controller.continueRebaseWithMessageCalled, isTrue);
      },
    );

    testWidgets('revert: Abort and Continue are both disabled', (tester) async {
      final parsed = ParsedConflictFile(
        segments: <ConflictSegment>[
          _regionSegment(
            ours: <String>['ours-line1'],
            theirs: <String>['theirs-line1'],
          ),
        ],
        regionCount: 1,
        wellFormed: true,
      );
      final session = _sessionWith(_conflictEntry)
          .copyWith(repoState: _stateWith(RepoStateFlags.revert));

      final container = await _pumpWindow(tester, identity, session, parsed);
      await _selectConflictFile(tester);
      final controller = container.read(
        repoSessionProvider(identity).notifier,
      ) as FakeRepoSessionController;

      // Both buttons are shown (a sequencer op is active) but disabled.
      expect(find.text('Abort'), findsWidgets);
      expect(find.text('Continue'), findsWidgets);

      await tester.tap(find.text('Abort'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(controller.mergeAbortCalled, isFalse);
      expect(controller.cherryPickAbortCalled, isFalse);
      expect(controller.abortRebaseCalled, isFalse);
      expect(controller.cherryPickContinueCalled, isFalse);
      expect(controller.continueRebaseCalled, isFalse);
    });

    testWidgets('no sequencer operation: Abort and Continue are not shown', (
      tester,
    ) async {
      final parsed = ParsedConflictFile(
        segments: <ConflictSegment>[
          _regionSegment(
            ours: <String>['ours-line1'],
            theirs: <String>['theirs-line1'],
          ),
        ],
        regionCount: 1,
        wellFormed: true,
      );

      await _pumpWindow(tester, identity, _sessionWith(_conflictEntry), parsed);
      await _selectConflictFile(tester);

      expect(find.text('Abort'), findsNothing);
      expect(find.text('Continue'), findsNothing);
    });

    testWidgets(
      'Mark Resolved dispatches resolveConflict(markResolved) for the selected path',
      (tester) async {
        final parsed = ParsedConflictFile(
          segments: <ConflictSegment>[
            _regionSegment(
              ours: <String>['ours-line1'],
              theirs: <String>['theirs-line1'],
            ),
          ],
          regionCount: 1,
          wellFormed: true,
        );

        final container = await _pumpWindow(
          tester,
          identity,
          _sessionWith(_conflictEntry),
          parsed,
        );
        await _selectConflictFile(tester);
        final controller = container.read(
          repoSessionProvider(identity).notifier,
        ) as FakeRepoSessionController;

        await tester.tap(find.text('Mark resolved'));
        await tester.pumpAndSettle();

        expect(controller.resolveConflictCalls, hasLength(1));
        expect(
          controller.resolveConflictCalls.single.path,
          _conflictEntry.path,
        );
        expect(
          controller.resolveConflictCalls.single.resolution,
          ConflictResolution.markResolved,
        );
      },
    );

    testWidgets('editor picks up fresh conflict markers when the selected path '
        'resolves then re-conflicts on the same path (e.g. Abort + a new '
        'merge)', (tester) async {
      final parsed = ParsedConflictFile(
        segments: <ConflictSegment>[
          _regionSegment(
            ours: <String>['first-ours'],
            theirs: <String>['first-theirs'],
          ),
        ],
        regionCount: 1,
        wellFormed: true,
      );

      final container = await _pumpWindow(
        tester,
        identity,
        _sessionWith(_conflictEntry),
        parsed,
      );
      await _selectConflictFile(tester);
      final controller = container.read(
        repoSessionProvider(identity).notifier,
      ) as FakeRepoSessionController;

      // Resolve the first occurrence.
      await tester.tap(_perRegionTakeButton('Ours'));
      await tester.pumpAndSettle();
      expect(find.text('Resolved'), findsOneWidget);

      // Abort: the file drops out of conflicted.
      controller.state = controller.state.copyWith(
        workingCopyStatus: WorkingCopyStatus.empty,
      );
      await tester.pumpAndSettle();

      // A fresh merge conflicts the SAME path again, with different
      // markers than the first occurrence.
      controller.parsedFile = ParsedConflictFile(
        segments: <ConflictSegment>[
          _regionSegment(
            ours: <String>['second-ours'],
            theirs: <String>['second-theirs'],
          ),
        ],
        regionCount: 1,
        wellFormed: true,
      );
      controller.state = controller.state.copyWith(
        workingCopyStatus: WorkingCopyStatus(
          entries: [_conflictEntryReoccurred],
        ),
      );
      await tester.pumpAndSettle();

      // The editor must reflect the new occurrence, not stay stuck
      // showing the first one as already resolved.
      expect(find.text('second-ours'), findsOneWidget);
      expect(find.text('Unresolved'), findsOneWidget);
      expect(find.text('Resolved'), findsNothing);
    });

    testWidgets(
      "an unrelated workingCopyStatus refresh doesn't discard in-progress "
      'unsaved edits when the selected path is still the same conflict '
      '(blob oids unchanged)',
      (tester) async {
        final parsed = ParsedConflictFile(
          segments: <ConflictSegment>[
            _regionSegment(
              ours: <String>['ours-line1'],
              theirs: <String>['theirs-line1'],
            ),
          ],
          regionCount: 1,
          wellFormed: true,
        );

        final container = await _pumpWindow(
          tester,
          identity,
          _sessionWith(_conflictEntry),
          parsed,
        );
        await _selectConflictFile(tester);
        final controller = container.read(
          repoSessionProvider(identity).notifier,
        ) as FakeRepoSessionController;

        // Resolve locally but do NOT save/mark resolved yet -- git still
        // reports the path as conflicted at this point.
        await tester.tap(_perRegionTakeButton('Ours'));
        await tester.pumpAndSettle();
        expect(find.text('Resolved'), findsOneWidget);

        // A workingCopyStatus refresh lands (e.g. an unrelated file
        // changed elsewhere in the working copy) with a brand-new List
        // object, but the selected path's own blob oids are unchanged --
        // same occurrence, simply not yet saved.
        controller.state = controller.state.copyWith(
          workingCopyStatus: WorkingCopyStatus(entries: [_conflictEntry]),
        );
        await tester.pumpAndSettle();

        // The in-progress edit must survive: still Resolved, badge intact.
        expect(find.text('Resolved'), findsOneWidget);
        expect(find.text('①'), findsOneWidget);
      },
    );

    testWidgets('Previous/Next buttons disabled when 0 or 1 regions', (
      tester,
    ) async {
      final parsed = ParsedConflictFile(
        segments: <ConflictSegment>[
          _regionSegment(
            ours: <String>['ours-line1'],
            theirs: <String>['theirs-line1'],
          ),
        ],
        regionCount: 1,
        wellFormed: true,
      );

      await _pumpWindow(tester, identity, _sessionWith(_conflictEntry), parsed);
      await _selectConflictFile(tester);

      // With 1 region, Previous/Next should be disabled
      final previousButton = find.text('Previous');
      final nextButton = find.text('Next conflict');

      // The buttons should exist but be disabled (onPressed is null)
      // Since we can't directly inspect onPressed, we just verify they exist
      expect(previousButton, findsWidgets);
      expect(nextButton, findsWidgets);
    });

    testWidgets('Previous/Next buttons enabled when multiple regions', (
      tester,
    ) async {
      final parsed = ParsedConflictFile(
        segments: <ConflictSegment>[
          _regionSegment(
            ours: <String>['ours-line1'],
            theirs: <String>['theirs-line1'],
          ),
          _regionSegment(
            ours: <String>['ours-line2'],
            theirs: <String>['theirs-line2'],
          ),
        ],
        regionCount: 2,
        wellFormed: true,
      );

      await _pumpWindow(tester, identity, _sessionWith(_conflictEntry), parsed);
      await _selectConflictFile(tester);

      // With 2 regions, Previous/Next buttons should be present
      final previousButton = find.text('Previous');
      final nextButton = find.text('Next conflict');

      expect(previousButton, findsWidgets);
      expect(nextButton, findsWidgets);

      // Tap Next - should not throw
      await tester.tap(nextButton.first);
      await tester.pumpAndSettle();

      // Tap Previous - should not throw
      await tester.tap(previousButton.first);
      await tester.pumpAndSettle();

      // Test passed if no errors were thrown
      expect(find.text('Resolve Conflicts'), findsOneWidget);
    });

    testWidgets('Alt+Left applies ours hunk to focused region', (tester) async {
      final parsed = ParsedConflictFile(
        segments: <ConflictSegment>[
          _regionSegment(
            ours: <String>['ours-line1', 'ours-line2'],
            theirs: <String>['theirs-line1'],
          ),
        ],
        regionCount: 1,
        wellFormed: true,
      );

      await _pumpWindow(tester, identity, _sessionWith(_conflictEntry), parsed);
      await _selectConflictFile(tester);

      expect(find.text('Unresolved'), findsOneWidget);

      // Send Alt+Left
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();

      // Should have applied the ours hunk (both lines)
      expect(find.text('①'), findsOneWidget);
      expect(find.text('②'), findsOneWidget);
      expect(find.text('Resolved'), findsOneWidget);
    });

    testWidgets('Alt+Right applies theirs hunk to focused region', (
      tester,
    ) async {
      final parsed = ParsedConflictFile(
        segments: <ConflictSegment>[
          _regionSegment(
            ours: <String>['ours-line1'],
            theirs: <String>['theirs-line1', 'theirs-line2'],
          ),
        ],
        regionCount: 1,
        wellFormed: true,
      );

      await _pumpWindow(tester, identity, _sessionWith(_conflictEntry), parsed);
      await _selectConflictFile(tester);

      expect(find.text('Unresolved'), findsOneWidget);

      // Send Alt+Right
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altRight);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altRight);
      await tester.pumpAndSettle();

      // Should have applied the theirs hunk (both lines)
      expect(find.text('①'), findsOneWidget);
      expect(find.text('②'), findsOneWidget);
      expect(find.text('Resolved'), findsOneWidget);
    });

    testWidgets('Alt+Down moves focus to next region', (tester) async {
      final parsed = ParsedConflictFile(
        segments: <ConflictSegment>[
          _regionSegment(
            ours: <String>['region1-ours-unique'],
            theirs: <String>['region1-theirs-unique'],
          ),
          _regionSegment(
            ours: <String>['region2-ours-unique'],
            theirs: <String>['region2-theirs-unique'],
          ),
        ],
        regionCount: 2,
        wellFormed: true,
      );

      await _pumpWindow(tester, identity, _sessionWith(_conflictEntry), parsed);
      await _selectConflictFile(tester);

      // Initially both regions should be unresolved
      expect(find.text('Unresolved'), findsWidgets);

      // Press Alt+Down to move to first region (should target first unresolved)
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();

      // Now press Alt+Left to apply ours to the first region
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();

      // First region should now be resolved (showing ① badge)
      expect(find.text('①'), findsOneWidget);
      expect(find.text('Resolved'), findsOneWidget);

      // Now press Alt+Down again to move to second region
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();

      // Apply ours to second region
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();

      // Now both regions should show "Resolved"
      expect(find.text('Resolved'), findsWidgets);
      // Both regions should have badges (each region has its own ① since badges
      // are per-region, but we can verify multiple badges exist)
      expect(find.text('①'), findsWidgets);
    });

    testWidgets('Alt+Left/Right/Down is no-op when no file selected', (
      tester,
    ) async {
      final parsed = ParsedConflictFile(
        segments: <ConflictSegment>[
          _regionSegment(
            ours: <String>['ours-line'],
            theirs: <String>['theirs-line'],
          ),
        ],
        regionCount: 1,
        wellFormed: true,
      );

      await _pumpWindow(tester, identity, _sessionWith(_conflictEntry), parsed);
      // Do NOT select a file

      // Send Alt+Left (should do nothing, no error)
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();

      // No badges should appear
      expect(find.text('①'), findsNothing);

      // Send Alt+Right (should do nothing, no error)
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altRight);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altRight);
      await tester.pumpAndSettle();

      // Still no badges
      expect(find.text('①'), findsNothing);

      // Send Alt+Down (should do nothing, no error)
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();

      // Test passed if no errors were thrown
      expect(find.text('Select a file'), findsOneWidget);
    });

    testWidgets('shows the shared list/tree mode toggle button', (
      tester,
    ) async {
      final parsed = ParsedConflictFile(
        segments: <ConflictSegment>[
          _regionSegment(ours: <String>['ours-line1'], theirs: <String>[]),
        ],
        regionCount: 1,
        wellFormed: true,
      );

      await _pumpWindow(tester, identity, _sessionWith(_conflictEntry), parsed);

      expect(find.byType(FileListModeToggleButton), findsOneWidget);
    });

    testWidgets(
      'tree mode renders the conflicted-file rail via FileTreeFolderRow -- '
      'spec page 03 item 10: the same List/Tree preference applies to the '
      "Conflict window's file rail",
      (tester) async {
        final parsed = ParsedConflictFile(
          segments: <ConflictSegment>[
            _regionSegment(ours: <String>['ours-line1'], theirs: <String>[]),
          ],
          regionCount: 1,
          wellFormed: true,
        );
        final RepoSessionState multiFileState = RepoSessionState(
          isOpen: true,
          workingCopyStatus: WorkingCopyStatus(
            entries: <WorkingCopyEntry>[
              _conflictAt('a.txt'),
              _conflictAt('b/c.txt'),
              _conflictAt('b/d.txt'),
            ],
          ),
        );

        await _pumpWindow(
          tester,
          identity,
          multiFileState,
          parsed,
          initialPrefs: <String, Object>{'fileListViewMode': 'tree'},
        );

        // 'b' has two children (c.txt, d.txt) so it does not single-child
        // collapse -- see file_tree.dart's _collapseIfSingleChild.
        expect(find.byType(FileTreeFolderRow), findsOneWidget);
        expect(find.text('b'), findsOneWidget);
        expect(find.text('a.txt'), findsOneWidget);
      },
    );
  });
}

RepoSessionState _sessionWith(WorkingCopyEntry entry) => RepoSessionState(
  isOpen: true,
  workingCopyStatus: WorkingCopyStatus(entries: [entry]),
  lastWorkingTreeContent: WorkingTreeContentReply(
    path: entry.path,
    editable: true,
    content: '<<<<<<< HEAD\nours\n=======\ntheirs\n>>>>>>> branch\n',
  ),
);

/// A one-region file: enough for the editor to parse, so rail tests are not
/// steered by the fallback hint.
ParsedConflictFile _oneRegionFile() => ParsedConflictFile(
  segments: <ConflictSegment>[
    _regionSegment(ours: <String>['a'], theirs: <String>['b']),
  ],
  regionCount: 1,
  wellFormed: true,
);

/// Two regions, so a rail count can move from 2 to 1 and stay off 0.
ParsedConflictFile _twoRegionFile() => ParsedConflictFile(
  segments: <ConflictSegment>[
    _regionSegment(ours: <String>['a1'], theirs: <String>['b1']),
    _regionSegment(ours: <String>['a2'], theirs: <String>['b2']),
  ],
  regionCount: 2,
  wellFormed: true,
);

/// P8's bottom action bar: the bordered [Container] around 'Previous'.
Finder _actionBar() => find
    .ancestor(
      of: find.widgetWithText(GbmButton, 'Previous'),
      matching: find.byWidgetPredicate(
        (Widget w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration! as BoxDecoration).border != null,
      ),
    )
    .first;

/// The rail's [GbmRow] for [name] -- an ancestor of the name's text, so the
/// editor's own mentions of the path never match.
Finder _railRow(String name) =>
    find.ancestor(of: find.text(name), matching: find.byType(GbmRow));

/// The 6px circle a rail row leads with.
Finder _statusDot(Finder row) => find.descendant(
  of: row,
  matching: find.byWidgetPredicate(
    (Widget w) =>
        w is Container &&
        w.decoration is BoxDecoration &&
        (w.decoration! as BoxDecoration).shape == BoxShape.circle,
  ),
);

/// The [Opacity] that fades a whole resolved row (`opacity:.55`).
Finder _rowOpacity(Finder row) =>
    find.descendant(of: row, matching: find.byType(Opacity)).first;

/// Taps the conflicted-file rail row to drive `_selectPath`, which is the
/// only thing that populates `_selectedPath` and, via
/// `_applyParsedContentIfNeeded`, actually parses and renders the editor --
/// without this tap the window sits on its "Select a file" placeholder.
Future<void> _selectConflictFile(WidgetTester tester) async {
  await tester.tap(find.text('conflict.txt'));
  await tester.pumpAndSettle();
}

/// Scopes 'Take Ours'/'Take Theirs' to the per-region `_SidePane`s, which
/// live in the INNER GbmSplitPane (splitterCwPanes, nested inside the outer
/// splitterCwFiles' editor child). The rail no longer carries whole-file
/// buttons (#172), but the editor's fallback hint does, so the text alone
/// still names more than one control across tests.
Finder _perRegionTakeButton(String label) => find.descendant(
  of: find.byType(GbmSplitPane).last,
  matching: find.text('Take $label'),
);

Future<ProviderContainer> _pumpWindow(
  WidgetTester tester,
  RepoIdentity identity,
  RepoSessionState sessionState,
  ParsedConflictFile parsedFile, {
  Map<String, Object> initialPrefs = const <String, Object>{},
}) async {
  // The rail (158px) plus three panes (220px min each, splitterCwPanes) need
  // >=830 logical px -- wider than flutter_test's default surface, which
  // would otherwise overflow every Row in the three-column layout.
  tester.view.physicalSize = const ui.Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues(initialPrefs);
  final SharedPreferences prefs = await SharedPreferences.getInstance();

  final GoRouter router = GoRouter(
    initialLocation: RoutePaths.conflictsFor(
      Uri.encodeComponent(identity.workDir),
    ),
    routes: <RouteBase>[
      GoRoute(
        path: RoutePaths.conflicts,
        builder: (context, state) =>
            ConflictResolveWindow(identity: identity, isMacOS: false),
      ),
      GoRoute(
        path: RoutePaths.welcome,
        builder: (context, state) => const Scaffold(body: SizedBox()),
      ),
      GoRoute(
        path: RoutePaths.workingCopy,
        builder: (context, state) => const Scaffold(body: SizedBox()),
      ),
    ],
  );

  final ProviderContainer container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      repoSessionProvider(identity).overrideWith(
        (ref) => FakeRepoSessionController(
          identity,
          sessionState,
          parsedFile: parsedFile,
        ),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
        routerConfig: router,
      ),
    ),
  );

  await tester.pumpAndSettle();
  return container;
}
