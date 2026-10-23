import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../actions/gbm_action_id.dart';
import '../../../data/ffi/gbm_bindings.dart';
import '../../../data/ffi/json_codec.dart';
import '../../../data/models/app_action_outcome.dart';
import '../../../data/models/base_folder_record.dart';
import '../../../data/models/git_error.dart';
import '../../../data/repositories/app_log_sink.dart';
import '../../../data/repositories/discovery_repository.dart';
import '../../../data/repositories/gbm_bindings_provider.dart';
import '../../../data/services/app_action_runner.dart';
import '../../../data/services/app_actions.dart';
import '../../../data/services/file_save_picker.dart';
import '../../../data/services/target_directory_probe.dart';
import '../../../routing/app_router.dart';
import '../../../routing/route_paths.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_button.dart';
import '../../../widgets/gbm_dialog_field_kinds.dart';
import '../../../widgets/gbm_dialog_shell.dart';
import '../../../widgets/gbm_input_decoration.dart';

/// DLGS 「New repository」, drawn as new-repository-spec.html screen 1:
/// 名稱 / 位置 / 預設分支名, with DLGS's two checkboxes removed (N-D1, N-D4).
/// Routed as [RoutePaths.newRepositoryDialog].
///
/// Create closes the dialog at once and runs `git init` as an app action
/// (N-D5): success and failure are one line each in the Log of the window
/// it was opened from (R4, R13), and a success opens the new repository.
class NewRepositoryDialogContent extends ConsumerStatefulWidget {
  const NewRepositoryDialogContent({super.key, this.originWorkDir});

  /// The repository window this was opened from, whose Log the result goes
  /// to; null for the window with no repository (R13).
  final String? originWorkDir;

  @override
  ConsumerState<NewRepositoryDialogContent> createState() =>
      _NewRepositoryDialogContentState();
}

class _NewRepositoryDialogContentState
    extends ConsumerState<NewRepositoryDialogContent> {
  final TextEditingController _name = TextEditingController();
  late final TextEditingController _location = TextEditingController(
    text: _defaultLocation() ?? '',
  );
  // N-D6: DLGS v:'main'.
  final TextEditingController _branch = TextEditingController(text: 'main');

  @override
  void dispose() {
    _name.dispose();
    _location.dispose();
    _branch.dispose();
    super.dispose();
  }

  /// 「預設為 Preferences 的第一個來源資料夾」, read as the first *enabled*
  /// one, as the Clone dialog's default parent is.
  String? _defaultLocation() {
    for (final BaseFolderRecord folder
        in ref.read(discoveryProvider).baseFolders) {
      if (folder.enabled) return folder.path;
    }
    return null;
  }

  Future<void> _browse() async {
    final String? dir = await ref.read(fileSavePickerProvider).pickDirectory();
    if (dir == null || !mounted) return;
    setState(() => _location.text = dir);
  }

  /// 位置/名稱, or null while either cannot make a path: the name is one
  /// folder, so a separator or a `.`/`..` is refused rather than resolved.
  String? _targetPath() {
    final String name = _name.text.trim();
    final String location = _location.text.trim().replaceAll(
      RegExp(r'[/\\]+$'),
      '',
    );
    if (name.isEmpty || name == '.' || name == '..') return null;
    if (name.contains('/') || name.contains(r'\')) return null;
    if (location.isEmpty) return null;
    return '$location/$name';
  }

  Future<void> _create(String path) async {
    final String branch = _branch.text.trim();
    // Everything the action needs is taken before the pop: this State is
    // gone by the time init returns.
    final GoRouter router = GoRouter.of(context);
    final AppActionRunner runner = ref.read(appActionRunnerProvider);
    final GbmBindings bindings = ref.read(gbmBindingsProvider);
    final AppLogSink sink = appLogSinkFor(ref, widget.originWorkDir);
    context.pop();

    final AppActionOutcome<void> outcome = await runner.run(
      initRepositoryAction(
        path: path,
        init: () {
          final Pointer<Utf8> pathPtr = path.toNativeUtf8();
          final Pointer<Utf8> branchPtr = branch.toNativeUtf8();
          try {
            if (bindings.repoInit(pathPtr, branchPtr) == 0) return null;
          } finally {
            malloc.free(pathPtr);
            malloc.free(branchPtr);
          }
          return _decodeInitErrorMessage(bindings);
        },
      ),
      sink: sink,
    );
    if (outcome is! AppActionSucceeded<void>) return;
    router.go(RoutePaths.workspaceFor(repoIdFor(path)));
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final String? path = _targetPath();
    final TargetDirectoryState target = path == null
        ? TargetDirectoryState.missing
        : probeTargetDirectory(path);
    final bool canCreate =
        path != null &&
        _branch.text.trim().isNotEmpty &&
        target != TargetDirectoryState.gitRepository;
    final VoidCallback? onCreate = canCreate ? () => _create(path) : null;
    final TextStyle label = TextStyle(
      fontSize: GbmTypography.textXs,
      color: colors.textSecondary,
    );
    const TextStyle mono = TextStyle(fontFamily: GbmTypography.fontMono);
    Widget field({
      required String key,
      required TextEditingController controller,
      TextStyle? style,
      bool autofocus = false,
    }) => SizedBox(
      height: GbmSpacing.inputHeight,
      child: TextField(
        key: Key(key),
        controller: controller,
        autofocus: autofocus,
        style: style,
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => onCreate?.call(),
        decoration: gbmInputDecoration(colors: colors),
      ),
    );

    return GbmDialogShell(
      title: 'New repository',
      actionId: GbmActionId.fileNewRepository,
      actions: <Widget>[
        GbmButton(label: 'Cancel', onPressed: () => context.pop()),
        GbmButton(
          label: 'Create repository',
          kind: GbmButtonKind.primary,
          onPressed: onCreate,
        ),
      ],
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SizedBox(height: GbmSpacing.space3),
            Text('名稱', style: label),
            const SizedBox(height: GbmSpacing.space1),
            field(
              key: 'new-repo-name-field',
              controller: _name,
              autofocus: true,
            ),
            const SizedBox(height: GbmSpacing.space3),
            Text('位置', style: label),
            const SizedBox(height: GbmSpacing.space1),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: field(
                    key: 'new-repo-location-field',
                    controller: _location,
                    style: mono,
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
            Text(
              '預設為 Preferences 的第一個來源資料夾',
              style: TextStyle(
                fontSize: GbmTypography.textXs,
                color: colors.textTertiary,
                height: 1.6,
              ),
            ),
            const SizedBox(height: GbmSpacing.space3),
            Text('預設分支名', style: label),
            const SizedBox(height: GbmSpacing.space1),
            field(
              key: 'new-repo-branch-field',
              controller: _branch,
              style: mono,
            ),
            if (target == TargetDirectoryState.gitRepository) ...<Widget>[
              const SizedBox(height: GbmSpacing.space3),
              GbmDialogWarnField(message: '$path 已經是 git repository。'),
            ],
            if (target == TargetDirectoryState.nonEmpty) ...<Widget>[
              const SizedBox(height: GbmSpacing.space3),
              GbmDialogWarnField(
                message: '$path 已存在且不是空的，會在現有檔案上建立 repository。',
              ),
            ],
            const SizedBox(height: GbmSpacing.space3),
          ],
        ),
      ),
    );
  }
}

String _decodeInitErrorMessage(GbmBindings bindings) {
  final String json = readLastResultJson(bindings);
  if (json.isEmpty) return 'The operation failed.';
  return GitError.fromJson(jsonDecode(json) as Map<String, dynamic>).message;
}
