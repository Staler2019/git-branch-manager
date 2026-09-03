import 'package:flutter/material.dart';

import '../theme/gbm_theme.dart';
import '../theme/tokens.dart';
import 'gbm_row.dart';
import 'lucide_icon.dart';

/// What a picked row *is*, which decides what the caller does with it.
///
/// Not folded into a bare `String`: `origin/main` checks out as a new local
/// branch tracking it (context menu 05-C's 「Checkout as new local…」) while
/// `main` checks out directly, and only the kind tells the two apart. The
/// declaration order is the order the groups are drawn in, which is the
/// order spec page 06's mockup lists them.
enum GbmRefKind {
  localBranch,
  remoteBranch,
  tag,
  commit;

  /// The group heading this kind sits under, upper-cased at the render site.
  String get groupLabel => switch (this) {
    GbmRefKind.localBranch => 'Local branches',
    GbmRefKind.remoteBranch => 'Remote branches',
    GbmRefKind.tag => 'Tags',
    GbmRefKind.commit => 'Commit',
  };

  /// The mockup's 「以圖示區分」: ⎇ / ☁ / 🏷 / ⌥ in the design sketch, which
  /// are these four Lucide names in the shipped icon set.
  String get iconName => switch (this) {
    GbmRefKind.localBranch => 'git-branch',
    GbmRefKind.remoteBranch => 'cloud',
    GbmRefKind.tag => 'tag',
    GbmRefKind.commit => 'git-commit-horizontal',
  };
}

/// One row of [GbmRefPicker].
@immutable
class GbmRefPickerEntry {
  const GbmRefPickerEntry({
    required this.name,
    required this.kind,
    this.annotation = '',
    this.enabled = true,
  });

  /// What git is handed: a short branch name, a tag name, or a commit-ish.
  final String name;

  final GbmRefKind kind;

  /// A dimmer note at the row's right edge — 「目前分支」, 「已在 gbm-0.5」.
  ///
  /// Separate from [enabled] because the two are genuinely independent: New
  /// branch annotates the current branch and still lets it be picked, while
  /// Add worktree annotates a branch another worktree holds and must not.
  final String annotation;

  /// False draws the row dimmed and swallows taps. Reserved for a row git
  /// itself would refuse, so the refusal is stated before the button is
  /// pressed rather than as an error banner afterwards.
  final bool enabled;
}

/// The searchable branch / tag / commit list spec page 06 names for Checkout
/// (「可搜尋的分支 / tag / commit 清單」) and P17 reuses for New branch's
/// 從哪裡分出 field.
///
/// **One control, three callers.** It was Checkout's private list plus New
/// branch's `DropdownButtonFormField` + a second bare `TextField`, which is
/// not the same shape, and the second of those shipped with **no controller
/// and no initialValue** — so a start point handed in from a commit row was
/// held in state and drawn nowhere.
///
/// The picker owns the query. Everything a call site differs on is a
/// constructor parameter rather than a condition inside here: which entries
/// exist, which are disabled and what they are annotated with are the
/// caller's, because「哪些能選」is a question about git's rules for *that*
/// operation, not about a list widget.
class GbmRefPicker extends StatefulWidget {
  const GbmRefPicker({
    super.key,
    required this.entries,
    required this.selected,
    required this.onSelected,
    this.allowCommitHash = false,
    this.autofocus = false,
    this.hintText = 'Search branches, tags and commits',
    this.emptyMessage = 'Nothing to pick.',
    this.maxListHeight = 280,
  });

  /// Given in any order: the picker sorts by [GbmRefKind] itself. A heading
  /// is emitted where the previous row's kind differs, so an interleaved
  /// list would print the same heading twice — sorting here rather than at
  /// three call sites is what stops that being a rule each of them has to
  /// remember.
  final List<GbmRefPickerEntry> entries;

  /// The picked [GbmRefPickerEntry.name], or null. Held by the caller so a
  /// dialog's primary button can gate on it.
  final String? selected;

  final ValueChanged<GbmRefPickerEntry> onSelected;

  /// Whether a hash-shaped query that matches no entry is offered as a
  /// commit of its own. Off for a caller that only accepts a named ref.
  final bool allowCommitHash;

  final bool autofocus;
  final String hintText;
  final String emptyMessage;
  final double maxListHeight;

  @override
  State<GbmRefPicker> createState() => _GbmRefPickerState();
}

class _GbmRefPickerState extends State<GbmRefPicker> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Substring, case-insensitive — the same matching rule spec page 02 item
  /// 14 gives the sidebar branch filter, so every search field in the app
  /// behaves identically.
  bool _matches(String name) =>
      _query.isEmpty || name.toLowerCase().contains(_query.toLowerCase());

  /// An abbreviated oid is 4–40 hex characters. git's own floor is
  /// `core.abbrev`'s minimum of 4, and anything shorter is ambiguous by
  /// construction rather than merely unlucky.
  static final RegExp _hashShaped = RegExp(r'^[0-9a-fA-F]{4,40}$');

  List<GbmRefPickerEntry> _visible() {
    final List<GbmRefPickerEntry> matched =
        widget.entries.where((GbmRefPickerEntry e) => _matches(e.name)).toList()
          ..sort(
            (GbmRefPickerEntry a, GbmRefPickerEntry b) =>
                a.kind.index.compareTo(b.kind.index),
          );

    final String query = _query.trim();
    if (!widget.allowCommitHash || !_hashShaped.hasMatch(query)) return matched;
    // A query that already names a ref is that ref, not a hash. Offering it
    // twice would ask the user to choose between two identical-looking rows.
    if (widget.entries.any((GbmRefPickerEntry e) => e.name == query)) {
      return matched;
    }
    return <GbmRefPickerEntry>[
      ...matched,
      GbmRefPickerEntry(name: query, kind: GbmRefKind.commit),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final List<GbmRefPickerEntry> visible = _visible();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TextField(
          controller: _searchController,
          autofocus: widget.autofocus,
          onChanged: (String value) => setState(() => _query = value),
          decoration: InputDecoration(
            hintText: widget.hintText,
            isDense: true,
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.search, size: 16),
          ),
        ),
        const SizedBox(height: GbmSpacing.space2),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: widget.maxListHeight),
          child: visible.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: GbmSpacing.space4,
                  ),
                  child: Text(
                    _query.isEmpty
                        ? widget.emptyMessage
                        : 'No branch, tag or commit matches "$_query".',
                    style: TextStyle(
                      fontSize: GbmTypography.textSm,
                      color: colors.textTertiary,
                    ),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: visible.length,
                  itemBuilder: (BuildContext context, int index) {
                    // Recomputed per build: itemBuilder is not guaranteed to
                    // run in order, so the heading is derived from the
                    // previous entry rather than from mutable state.
                    final bool isFirstOfGroup =
                        index == 0 ||
                        visible[index - 1].kind != visible[index].kind;
                    return _EntryRow(
                      entry: visible[index],
                      heading: isFirstOfGroup
                          ? visible[index].kind.groupLabel.toUpperCase()
                          : null,
                      selected: widget.selected == visible[index].name,
                      onTap: widget.onSelected,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.entry,
    required this.heading,
    required this.selected,
    required this.onTap,
  });

  final GbmRefPickerEntry entry;
  final String? heading;
  final bool selected;
  final ValueChanged<GbmRefPickerEntry> onTap;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    // Dimmed rather than hidden: 隱藏會讓人以為功能不存在, and here the row
    // existing is half the message — the branch *is* checked out, elsewhere.
    final Color nameColor = entry.enabled
        ? colors.textPrimary
        : colors.textTertiary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (heading case final String label)
          Padding(
            padding: const EdgeInsets.only(
              top: GbmSpacing.space2,
              bottom: GbmSpacing.space1,
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: GbmTypography.textXs,
                fontWeight: GbmTypography.weightSemibold,
                color: colors.textTertiary,
                letterSpacing: 0.5,
              ),
            ),
          ),
        GbmRow(
          selected: selected,
          height: GbmSpacing.rowHeightCompact,
          padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space2),
          // Null, not a no-op closure: GbmRow reads it to decide whether the
          // row is interactive at all, so a closure that does nothing would
          // still hover and still look pressable.
          onTap: entry.enabled ? () => onTap(entry) : null,
          child: Row(
            children: <Widget>[
              LucideIcon(entry.kind.iconName, size: 12, color: nameColor),
              const SizedBox(width: GbmSpacing.space2),
              Expanded(
                child: Text(
                  entry.name,
                  style: TextStyle(
                    fontSize: GbmTypography.textSm,
                    color: nameColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (entry.annotation.isNotEmpty) ...<Widget>[
                const SizedBox(width: GbmSpacing.space2),
                Text(
                  entry.annotation,
                  style: TextStyle(
                    fontSize: GbmTypography.textXs,
                    color: colors.textTertiary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
