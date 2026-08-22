// Unit coverage for the two pure resolvers behind spec page 02 item 16's
// "其餘可開關並拖曳排序 … 欄寬各自可拖曳並記憶".
//
// These exist as pure functions rather than notifier methods because the
// interesting cases are all about *bad stored input* -- a preferences file
// written by an older build, hand-edited, or corrupt -- and a resolver that
// can be called with a literal is far easier to pin than one reachable only
// through SharedPreferences.
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/repositories/graph_columns_repository.dart'
    show kLockedGraphColumnIds;
import 'package:gbm_flutter/data/models/graph_column.dart';
import 'package:gbm_flutter/theme/tokens.dart';

void main() {
  group('kGraphColumnOrderDefault', () {
    test('matches the spec GRAPH_COLS order', () {
      // spec_logic.js:451 GRAPH_COLS -- Graph, Message, Refs, Author, Date,
      // Commit hash, Committer, Changed files. The picker list and the row's
      // render order are the same list in the spec, so there is one default.
      expect(kGraphColumnOrderDefault, <GbmGraphColumnId>[
        GbmGraphColumnId.graph,
        GbmGraphColumnId.message,
        GbmGraphColumnId.refs,
        GbmGraphColumnId.author,
        GbmGraphColumnId.date,
        GbmGraphColumnId.hash,
        GbmGraphColumnId.committer,
        GbmGraphColumnId.changedFiles,
      ]);
    });

    test('every id appears exactly once', () {
      expect(
        kGraphColumnOrderDefault.toSet().length,
        GbmGraphColumnId.values.length,
      );
    });
  });

  group('storage ids', () {
    test('match the strings already persisted by the visibility picker', () {
      // graph_columns_selector.dart's map is what wrote graphColumns.visibility
      // on every existing install. Renaming any of these silently orphans a
      // user's saved settings, so they are pinned here rather than left to
      // whatever the enum name happens to be.
      expect(
        <String>[
          for (final GbmGraphColumnId id in kGraphColumnOrderDefault)
            id.storageId,
        ],
        <String>[
          'graph',
          'message',
          'refs',
          'author',
          'date',
          'hash',
          'committer',
          'changedFiles',
        ],
      );
    });

    test('graphColumnById round-trips every id', () {
      for (final GbmGraphColumnId id in GbmGraphColumnId.values) {
        expect(graphColumnById(id.storageId), id);
      }
      expect(graphColumnById('nope'), isNull);
    });
  });

  group('labels', () {
    test('use the spec spelling, not the old picker Title Case', () {
      // spec writes "Commit hash" and "Changed files"; the picker had "Hash"
      // and "Changed Files".
      expect(GbmGraphColumnId.hash.label, 'Commit hash');
      expect(GbmGraphColumnId.changedFiles.label, 'Changed files');
    });
  });

  // Spec's GRAPH_COLS carries an `on:` flag per column (`spec_logic.js:451`):
  // six true, and Committer / Changed files false. Pinned here because the
  // fallback in `isGraphColumnVisible` is the only thing standing between an
  // existing install -- whose stored map mentions neither -- and two columns
  // switching themselves on.
  group('defaultVisible', () {
    test('matches the spec GRAPH_COLS on-flags', () {
      expect(
        <GbmGraphColumnId>[
          for (final GbmGraphColumnId id in GbmGraphColumnId.values)
            if (!id.defaultVisible) id,
        ],
        <GbmGraphColumnId>[
          GbmGraphColumnId.committer,
          GbmGraphColumnId.changedFiles,
        ],
      );
    });

    test('a locked column is never default-hidden', () {
      for (final GbmGraphColumnId id in GbmGraphColumnId.values) {
        if (id.isLocked) expect(id.defaultVisible, isTrue, reason: id.name);
      }
    });
  });

  group('locked columns', () {
    test('graph and message are locked, nothing else is', () {
      final Set<GbmGraphColumnId> locked = <GbmGraphColumnId>{
        for (final GbmGraphColumnId id in GbmGraphColumnId.values)
          if (id.isLocked) id,
      };
      expect(locked, <GbmGraphColumnId>{
        GbmGraphColumnId.graph,
        GbmGraphColumnId.message,
      });
    });

    test('isLocked agrees with kLockedGraphColumnIds', () {
      for (final GbmGraphColumnId id in GbmGraphColumnId.values) {
        expect(
          id.isLocked,
          kLockedGraphColumnIds.contains(id.storageId),
          reason: 'the enum and the storage-level guard must not drift',
        );
      }
    });

    test('a locked column is pinned in place', () {
      // Not two independent facts: spec's "其餘" governs toggling *and*
      // reordering, so a column that cannot be switched off cannot be
      // dragged to a new position either.
      for (final GbmGraphColumnId id in GbmGraphColumnId.values) {
        if (!id.isLocked) continue;
        expect(id.isMovable, isFalse);
      }
    });

    test('locked does not imply un-resizable: graph is both', () {
      // These used to be the same predicate, and reading them as one is what
      // this case exists to stop. Locked answers "can it be switched off";
      // resizable answers "can its width be dragged". Graph is now the
      // column where the two disagree: a drag changes the cap on how many
      // lanes it draws, never whether the column is there, and even at
      // `minWidth` one lane is still drawn -- so spec's "Graph 與 Message
      // 固定不可關" holds at every width.
      expect(GbmGraphColumnId.graph.isLocked, isTrue);
      expect(GbmGraphColumnId.graph.isMovable, isFalse);
      expect(GbmGraphColumnId.graph.isResizable, isTrue);

      // Message is the one column with no width of its own to drag.
      expect(GbmGraphColumnId.message.isLocked, isTrue);
      expect(GbmGraphColumnId.message.isResizable, isFalse);
    });

    test('graph\'s width bounds are exact lane multiples', () {
      // `graph_column.dart` has no imports on purpose, so it spells these as
      // literals and cannot express the derivation. This is where the
      // derivation is checked: eight lanes for the cap, one for the floor,
      // twenty-four for the ceiling, each plus the trailing half-slot.
      expect(GbmGraphColumnId.graph.defaultWidth, GbmLayout.graphLaneWidth * 9);
      expect(GbmGraphColumnId.graph.minWidth, GbmLayout.graphLaneWidth * 2);
      expect(GbmGraphColumnId.graph.maxWidth, GbmLayout.graphLaneWidth * 25);
    });

    test('every unlocked column is both movable and resizable', () {
      for (final GbmGraphColumnId id in GbmGraphColumnId.values) {
        if (id.isLocked) continue;
        expect(id.isMovable, isTrue, reason: '${id.storageId} should reorder');
        expect(id.isResizable, isTrue, reason: '${id.storageId} should resize');
      }
    });
  });

  group('resolveGraphColumnOrder', () {
    test('empty stored order gives the default', () {
      expect(
        resolveGraphColumnOrder(const <String>[]),
        kGraphColumnOrderDefault,
      );
    });

    test('honours a stored reordering of the movable columns', () {
      final List<GbmGraphColumnId> resolved = resolveGraphColumnOrder(
        const <String>[
          'graph',
          'message',
          'hash',
          'date',
          'author',
          'refs',
          'committer',
          'changedFiles',
        ],
      );
      expect(resolved.map((GbmGraphColumnId c) => c.storageId), <String>[
        'graph',
        'message',
        'hash',
        'date',
        'author',
        'refs',
        'committer',
        'changedFiles',
      ]);
    });

    test('pins graph first and message second however they were stored', () {
      final List<GbmGraphColumnId> resolved = resolveGraphColumnOrder(
        const <String>['hash', 'message', 'author', 'graph', 'date'],
      );
      expect(resolved[0], GbmGraphColumnId.graph);
      expect(resolved[1], GbmGraphColumnId.message);
    });

    test('appends known columns the stored list never mentioned', () {
      // Forward compatibility: a preferences file written before a column
      // existed must not make that column unreachable.
      final List<GbmGraphColumnId> resolved = resolveGraphColumnOrder(
        const <String>['graph', 'message', 'hash'],
      );
      expect(resolved.map((GbmGraphColumnId c) => c.storageId), <String>[
        'graph',
        'message',
        'hash',
        'refs',
        'author',
        'date',
        'committer',
        'changedFiles',
      ]);
    });

    test('drops ids it does not recognise', () {
      final List<GbmGraphColumnId> resolved = resolveGraphColumnOrder(
        const <String>['graph', 'message', 'gravatar', 'hash'],
      );
      expect(resolved.contains(GbmGraphColumnId.hash), isTrue);
      expect(resolved.length, GbmGraphColumnId.values.length);
    });

    test('drops duplicates rather than rendering a column twice', () {
      final List<GbmGraphColumnId> resolved = resolveGraphColumnOrder(
        const <String>['graph', 'message', 'hash', 'hash', 'hash'],
      );
      expect(resolved.length, GbmGraphColumnId.values.length);
      expect(resolved.toSet().length, resolved.length);
    });

    test('always returns every id exactly once, whatever the input', () {
      for (final List<String> stored in <List<String>>[
        <String>[],
        <String>['message'],
        <String>['changedFiles', 'committer', 'graph'],
        <String>['x', 'y', 'z'],
        <String>['graph', 'graph', 'message', 'message'],
      ]) {
        final List<GbmGraphColumnId> resolved = resolveGraphColumnOrder(stored);
        expect(
          resolved.toSet(),
          GbmGraphColumnId.values.toSet(),
          reason: 'stored=$stored lost or duplicated a column',
        );
        expect(resolved.length, GbmGraphColumnId.values.length);
      }
    });
  });

  group('resolveGraphColumnWidths', () {
    test('empty stored map gives every column its default', () {
      final Map<GbmGraphColumnId, double> resolved = resolveGraphColumnWidths(
        const <String, double>{},
      );
      for (final GbmGraphColumnId id in GbmGraphColumnId.values) {
        expect(resolved[id], id.defaultWidth);
      }
    });

    test('honours a stored width inside the allowed range', () {
      final Map<GbmGraphColumnId, double> resolved = resolveGraphColumnWidths(
        const <String, double>{'author': 150},
      );
      expect(resolved[GbmGraphColumnId.author], 150);
    });

    test('clamps a width below the minimum and above the maximum', () {
      final Map<GbmGraphColumnId, double> resolved = resolveGraphColumnWidths(
        const <String, double>{'author': 1, 'date': 100000},
      );
      expect(
        resolved[GbmGraphColumnId.author],
        GbmGraphColumnId.author.minWidth,
      );
      expect(resolved[GbmGraphColumnId.date], GbmGraphColumnId.date.maxWidth);
    });

    test('falls back to the default for NaN, infinity and non-positive', () {
      final Map<GbmGraphColumnId, double> resolved = resolveGraphColumnWidths(
        <String, double>{
          'author': double.nan,
          'date': double.infinity,
          'hash': 0,
          'refs': -40,
        },
      );
      expect(
        resolved[GbmGraphColumnId.author],
        GbmGraphColumnId.author.defaultWidth,
      );
      expect(
        resolved[GbmGraphColumnId.date],
        GbmGraphColumnId.date.defaultWidth,
      );
      expect(
        resolved[GbmGraphColumnId.hash],
        GbmGraphColumnId.hash.defaultWidth,
      );
      expect(
        resolved[GbmGraphColumnId.refs],
        GbmGraphColumnId.refs.defaultWidth,
      );
    });

    test('ignores unknown ids instead of throwing', () {
      final Map<GbmGraphColumnId, double> resolved = resolveGraphColumnWidths(
        const <String, double>{'gravatar': 42},
      );
      expect(resolved.length, GbmGraphColumnId.values.length);
    });

    test('ignores a stored width for a non-resizable column', () {
      // Message is the sole flex column, so a stored value for it is stale
      // data rather than a user setting. Graph is deliberately *not* in this
      // case any more -- see the companion below.
      final Map<GbmGraphColumnId, double> resolved = resolveGraphColumnWidths(
        const <String, double>{'message': 999},
      );
      expect(
        resolved[GbmGraphColumnId.message],
        GbmGraphColumnId.message.defaultWidth,
      );
    });

    test('honours a stored width for graph, clamped to its bounds', () {
      final Map<GbmGraphColumnId, double> resolved = resolveGraphColumnWidths(
        const <String, double>{'graph': 200},
      );
      expect(resolved[GbmGraphColumnId.graph], 200);

      // 999 is past `maxWidth`, and the documented rule is to clamp rather
      // than reject: a user who dragged to an extreme lands at the extreme.
      final Map<GbmGraphColumnId, double> tooWide = resolveGraphColumnWidths(
        const <String, double>{'graph': 999},
      );
      expect(tooWide[GbmGraphColumnId.graph], GbmGraphColumnId.graph.maxWidth);

      // And a drag past the floor still leaves one lane on screen.
      final Map<GbmGraphColumnId, double> tooNarrow = resolveGraphColumnWidths(
        const <String, double>{'graph': 1},
      );
      expect(
        tooNarrow[GbmGraphColumnId.graph],
        GbmGraphColumnId.graph.minWidth,
      );
    });

    test('every default sits inside its own [min, max]', () {
      for (final GbmGraphColumnId id in GbmGraphColumnId.values) {
        expect(
          id.defaultWidth,
          greaterThanOrEqualTo(id.minWidth),
          reason: id.storageId,
        );
        expect(
          id.defaultWidth,
          lessThanOrEqualTo(id.maxWidth),
          reason: id.storageId,
        );
      }
    });

    // The Refs column's floor, and the only direction this tier can guard.
    //
    // `_RefChipStrip` clips left-aligned, so a Refs column narrower than the
    // HEAD chip renders `HEAD → ` and nothing that identifies anything --
    // and since the standalone `HEAD` text label was removed, that chip is
    // the row's only "you are here" mark. 91 is the measured chip width
    // (90.6) rounded up; see the enum's own comment for how it was measured
    // and why a widget test cannot reproduce it (the Ahem test font puts the
    // same chip at 141.75px).
    //
    // Deliberately a floor and not an equality: the *ceiling* is owned by
    // `workspace_narrow_window_test.dart`'s twelve-lane 1280x720 case, which
    // goes red at 93. Restating 92 here would duplicate that guard and make
    // both red for one cause; each end is pinned once.
    test('Refs is wide enough for the HEAD chip at its default', () {
      expect(GbmGraphColumnId.refs.defaultWidth, greaterThanOrEqualTo(91));
    });
  });
}
