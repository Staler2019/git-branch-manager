import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../actions/gbm_action_id.dart';
import '../../../data/models/base_folder_record.dart';
import '../../../data/models/clone_url.dart';
import '../../../data/models/git_version.dart';
import '../../../data/repositories/clone_job_repository.dart';
import '../../../data/repositories/discovery_repository.dart';
import '../../../data/repositories/repo_identity.dart';
import '../../../data/repositories/repo_session_repository.dart';
import '../../../data/repositories/window_log_repository.dart';
import '../../../data/services/file_save_picker.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_button.dart';
import '../../../widgets/gbm_dialog_shell.dart';
import '../../../widgets/gbm_input_decoration.dart';

/// DLGS 「Clone repository」, drawn as welcome-and-clone-spec.html screen 4.
/// Routed as [RoutePaths.cloneRepositoryDialog].
///
/// Clone starts a background job and closes the dialog at once (DLGS note:
/// 「進行中不卡 dialog」); progress, failure and cancel are the status bar's
/// and the Log's (P15 B, R11). Nothing is ever written under the fields and
/// the dialog never comes back (R14).
class CloneRepositoryDialogContent extends ConsumerStatefulWidget {
  const CloneRepositoryDialogContent({super.key, this.originWorkDir});

  /// The repository window this was opened from, whose Log a refusal or
  /// failure goes to; null for the window with no repository (R13).
  final String? originWorkDir;

  @override
  ConsumerState<CloneRepositoryDialogContent> createState() =>
      _CloneRepositoryDialogContentState();
}

class _CloneRepositoryDialogContentState
    extends ConsumerState<CloneRepositoryDialogContent> {
  final TextEditingController _url = TextEditingController();
  final TextEditingController _dest = TextEditingController();
  bool _destEdited = false;

  /// The folder 瀏覽… picked; until then the first enabled base folder.
  String? _pickedParent;
  late final GitVersion? _git;
  late bool _recurseSubmodules;
  bool _shallow = false;

  @override
  void initState() {
    super.initState();
    _git = ref.read(cloneJobsProvider.notifier).gitVersion();
    // ASK-3 (a) / W-D5: below the fix, unchecked by default.
    _recurseSubmodules = _git?.clonesSubmodulesByDefault ?? false;
  }

  @override
  void dispose() {
    _url.dispose();
    _dest.dispose();
    super.dispose();
  }

  /// 「URL 貼上後自動帶出資料夾名，可手改」: under the folder 瀏覽… picked,
  /// else the first enabled base folder, until the destination is typed in
  /// by hand. With neither there is no parent to put it under, so the field
  /// is left alone.
  void _onUrlChanged(String url) {
    if (!_destEdited) {
      final String? parent = _pickedParent ?? _defaultParent();
      if (parent != null && cloneFolderNameFromUrl(url).isNotEmpty) {
        _dest.text = cloneDestinationPath(parent, url);
      }
    }
    setState(() {});
  }

  /// C-D1: the picked folder is the parent, and picking one hands the
  /// destination back to the URL.
  Future<void> _browse() async {
    final String? dir = await ref.read(fileSavePickerProvider).pickDirectory();
    if (dir == null || !mounted) return;
    setState(() {
      _pickedParent = dir;
      _destEdited = false;
      _dest.text = cloneDestinationPath(dir, _url.text);
    });
  }

  String? _defaultParent() {
    for (final BaseFolderRecord folder
        in ref.read(discoveryProvider).baseFolders) {
      if (folder.enabled) return folder.path;
    }
    return null;
  }

  CloneLogTarget _origin() {
    final String? origin = widget.originWorkDir;
    return origin == null
        ? CloneLogTarget.window(ref.read(windowLogProvider.notifier))
        : CloneLogTarget.session(
            ref.read(
              repoSessionProvider(RepoIdentity.forWorkDir(origin)).notifier,
            ),
          );
  }

  void _clone() {
    ref
        .read(cloneJobsProvider.notifier)
        .start(
          url: _url.text.trim(),
          destPath: _dest.text.trim(),
          recurseSubmodules: _recurseSubmodules,
          shallow: _shallow,
          origin: _origin(),
        );
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final bool canClone =
        _url.text.trim().isNotEmpty && _dest.text.trim().isNotEmpty;
    final GitVersion? git = _git;
    TextStyle label() =>
        TextStyle(fontSize: GbmTypography.textXs, color: colors.textSecondary);
    TextStyle hint({double height = 1.6}) => TextStyle(
      fontSize: GbmTypography.textXs,
      color: colors.textTertiary,
      height: height,
    );
    const TextStyle mono = TextStyle(fontFamily: GbmTypography.fontMono);
    Widget check(String text, bool value, ValueChanged<bool> onChanged) =>
        CheckboxListTile(
          value: value,
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(
            text,
            style: TextStyle(
              fontSize: GbmTypography.textSm,
              color: colors.textPrimary,
            ),
          ),
          onChanged: (bool? v) => setState(() => onChanged(v ?? false)),
        );

    return GbmDialogShell(
      title: 'Clone repository',
      actionId: GbmActionId.fileCloneRepository,
      actions: <Widget>[
        GbmButton(label: 'Cancel', onPressed: () => context.pop()),
        GbmButton(
          label: 'Clone',
          kind: GbmButtonKind.primary,
          onPressed: canClone ? _clone : null,
        ),
      ],
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SizedBox(height: GbmSpacing.space3),
            Text('URL', style: label()),
            const SizedBox(height: GbmSpacing.space1),
            SizedBox(
              height: GbmSpacing.inputHeight,
              child: TextField(
                key: const Key('clone-url-field'),
                controller: _url,
                autofocus: true,
                style: mono,
                onChanged: _onUrlChanged,
                decoration: gbmInputDecoration(colors: colors),
              ),
            ),
            const SizedBox(height: GbmSpacing.space3),
            Text('目標路徑', style: label()),
            const SizedBox(height: GbmSpacing.space1),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: SizedBox(
                    height: GbmSpacing.inputHeight,
                    child: TextField(
                      key: const Key('clone-dest-field'),
                      controller: _dest,
                      style: mono,
                      onChanged: (_) => setState(() => _destEdited = true),
                      onSubmitted: (_) {
                        if (canClone) _clone();
                      },
                      decoration: gbmInputDecoration(colors: colors),
                    ),
                  ),
                ),
                const SizedBox(width: GbmSpacing.space2),
                GbmButton(
                  label: '瀏覽…',
                  kind: GbmButtonKind.secondary,
                  icon: const Icon(Icons.folder_open_outlined),
                  onPressed: _browse,
                ),
              ],
            ),
            const SizedBox(height: GbmSpacing.space1),
            Text('URL 貼上後自動帶出資料夾名，可手改', style: hint()),
            const SizedBox(height: GbmSpacing.space2),
            check(
              '一併 clone submodule',
              _recurseSubmodules,
              (bool v) => _recurseSubmodules = v,
            ),
            if (git != null && !git.clonesSubmodulesByDefault)
              Text(
                'git $git 低於 2.50.1，clone 不信任的 repository 時遞迴 '
                'submodule 有已知漏洞（CVE-2025-48384），所以預設不勾。',
                style: hint(),
              ),
            check('淺層 clone（--depth 1）', _shallow, (bool v) => _shallow = v),
            const SizedBox(height: GbmSpacing.space2),
            Text(
              '進行中不卡 dialog：進度走 P10 背景作業列，完成後自動開啟。',
              style: hint(height: 1.7),
            ),
            const SizedBox(height: GbmSpacing.space3),
          ],
        ),
      ),
    );
  }
}
