import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/ref_snapshot.dart';
import '../../../data/repositories/repo_identity.dart';
import '../../../data/repositories/repo_session_repository.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_button.dart';
import '../../../widgets/gbm_dialog_shell.dart';
import '../branch_name_validation.dart';

/// The three start-point kinds spec page 06's New branch row lists in its
/// dropdown: "目前分支 / 指定 commit / tag".
enum NewBranchStartKind { currentBranch, branchOrCommit, tag }

/// Branch → New branch… (Ctrl/Cmd+Shift+B), and the "New branch from here…"
/// entries in context menus 05-B and 05-E.
///
/// Spec page 06: "名稱、起點（下拉：目前分支 / 指定 commit / tag）、是否立刻
/// checkout。名稱重複即時擋下" -- the duplicate-name check runs on every
/// keystroke and disables the primary button, rather than letting the create
/// round-trip to git and come back as an error banner.
///
/// Routed as `/repo/:repoId/dialogs/new-branch`. [initialStartPoint] is set
/// when opened from a branch or commit row, which preselects
/// [NewBranchStartKind.branchOrCommit] with that ref filled in.
class NewBranchDialogContent extends ConsumerStatefulWidget {
  const NewBranchDialogContent({
    super.key,
    required this.identity,
    this.initialStartPoint,
  });

  final RepoIdentity identity;
  final String? initialStartPoint;

  @override
  ConsumerState<NewBranchDialogContent> createState() =>
      _NewBranchDialogContentState();
}

class _NewBranchDialogContentState
    extends ConsumerState<NewBranchDialogContent> {
  late final TextEditingController _nameController;
  late NewBranchStartKind _startKind;
  String? _startRef;
  bool _checkoutAfter = true;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _startKind = widget.initialStartPoint == null
        ? NewBranchStartKind.currentBranch
        : NewBranchStartKind.branchOrCommit;
    _startRef = widget.initialStartPoint;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String? _nameError(List<String> existingNames) =>
      branchNameError(_nameController.text, existingNames: existingNames);

  /// The ref the new branch is created at, or `''` for "current branch"
  /// (which `branchCreate` reads as HEAD).
  String get _effectiveStartPoint =>
      _startKind == NewBranchStartKind.currentBranch ? '' : (_startRef ?? '');

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final RepoSessionState session = ref.watch(
      repoSessionProvider(widget.identity),
    );
    final String currentBranch = session.refs.head.branchName.isNotEmpty
        ? session.refs.head.branchName
        : 'HEAD';
    final List<String> existingNames = session.refs.localBranches
        .map((RefInfo b) => b.shortName)
        .toList(growable: false);

    final String? error = _nameError(existingNames);
    final bool canCreate =
        _nameController.text.trim().isNotEmpty &&
        error == null &&
        (_startKind == NewBranchStartKind.currentBranch ||
            _effectiveStartPoint.isNotEmpty);

    return GbmDialogShell(
      title: 'New Branch',
      actions: <Widget>[
        GbmButton(label: 'Cancel', onPressed: () => context.pop()),
        const SizedBox(width: GbmSpacing.space2),
        GbmButton(
          label: 'Create branch',
          kind: GbmButtonKind.primary,
          onPressed: canCreate
              ? () {
                  ref
                      .read(repoSessionProvider(widget.identity).notifier)
                      .createBranch(
                        name: _nameController.text.trim(),
                        startPoint: _effectiveStartPoint,
                        checkoutAfter: _checkoutAfter,
                      );
                  context.pop();
                }
              : null,
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            controller: _nameController,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) {
              if (!canCreate) return;
              ref
                  .read(repoSessionProvider(widget.identity).notifier)
                  .createBranch(
                    name: _nameController.text.trim(),
                    startPoint: _effectiveStartPoint,
                    checkoutAfter: _checkoutAfter,
                  );
              context.pop();
            },
            decoration: InputDecoration(
              labelText: 'Branch name',
              errorText: error,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: GbmSpacing.space3),
          Text(
            'START POINT',
            style: TextStyle(
              fontSize: GbmTypography.textXs,
              fontWeight: GbmTypography.weightSemibold,
              color: colors.textTertiary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: GbmSpacing.space1),
          DropdownButtonFormField<NewBranchStartKind>(
            initialValue: _startKind,
            isExpanded: true,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: <DropdownMenuItem<NewBranchStartKind>>[
              DropdownMenuItem(
                value: NewBranchStartKind.currentBranch,
                child: Text('Current branch ($currentBranch)'),
              ),
              const DropdownMenuItem(
                value: NewBranchStartKind.branchOrCommit,
                child: Text('Specific branch or commit'),
              ),
              const DropdownMenuItem(
                value: NewBranchStartKind.tag,
                child: Text('Tag'),
              ),
            ],
            onChanged: (NewBranchStartKind? kind) => setState(() {
              _startKind = kind ?? _startKind;
              // The previously chosen ref belongs to the previous kind's list.
              _startRef = null;
            }),
          ),
          if (_startKind == NewBranchStartKind.branchOrCommit) ...<Widget>[
            const SizedBox(height: GbmSpacing.space2),
            _RefPicker(
              hint: 'Branch, tag or commit',
              options: <String>[
                for (final RefInfo b in session.refs.localBranches) b.shortName,
                for (final RefInfo b in session.refs.remoteBranches)
                  b.shortName,
              ],
              value: _startRef,
              onChanged: (String? value) => setState(() => _startRef = value),
              onFreeText: (String value) => setState(() => _startRef = value),
            ),
          ],
          if (_startKind == NewBranchStartKind.tag) ...<Widget>[
            const SizedBox(height: GbmSpacing.space2),
            _RefPicker(
              hint: 'Tag',
              options: <String>[
                for (final RefInfo t in session.refs.tags) t.shortName,
              ],
              value: _startRef,
              onChanged: (String? value) => setState(() => _startRef = value),
            ),
          ],
          const SizedBox(height: GbmSpacing.space2),
          CheckboxListTile(
            value: _checkoutAfter,
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
              'Check out the new branch immediately',
              style: TextStyle(
                fontSize: GbmTypography.textSm,
                color: colors.textPrimary,
              ),
            ),
            onChanged: (bool? value) =>
                setState(() => _checkoutAfter = value ?? false),
          ),
        ],
      ),
    );
  }
}

/// A dropdown over known refs, plus -- when [onFreeText] is given -- a plain
/// text field for anything not in the list (an abbreviated commit hash, per
/// the spec's "指定 commit").
class _RefPicker extends StatelessWidget {
  const _RefPicker({
    required this.hint,
    required this.options,
    required this.value,
    required this.onChanged,
    this.onFreeText,
  });

  final String hint;
  final List<String> options;
  final String? value;
  final ValueChanged<String?> onChanged;
  final ValueChanged<String>? onFreeText;

  @override
  Widget build(BuildContext context) {
    // A value typed into the free-text field is not one of `options`, and
    // DropdownButtonFormField asserts if `initialValue` is absent from its
    // items -- so only feed it back a value it actually knows.
    final String? dropdownValue = options.contains(value) ? value : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        DropdownButtonFormField<String>(
          initialValue: dropdownValue,
          isExpanded: true,
          decoration: InputDecoration(
            hintText: hint,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          items: <DropdownMenuItem<String>>[
            for (final String option in options)
              DropdownMenuItem<String>(value: option, child: Text(option)),
          ],
          onChanged: onChanged,
        ),
        if (onFreeText case final ValueChanged<String> handler) ...<Widget>[
          const SizedBox(height: GbmSpacing.space1),
          TextField(
            onChanged: handler,
            decoration: const InputDecoration(
              hintText: '…or a commit hash',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ],
    );
  }
}
