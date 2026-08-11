import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/git_identity.dart';
import '../../../data/repositories/repo_identity.dart';
import '../../../data/repositories/repo_session_repository.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_button.dart';
import '../../../widgets/gbm_dialog_shell.dart';

/// The Dart analog of `PreferencesDialog` (src/app/dialogs/
/// PreferencesDialog.cpp), scoped to what this rewrite actually has a
/// backing store for: the per-repository Git identity override
/// (ConfigOps.h) and the commit-graph performance optimization
/// (MaintenanceOps.h). Routed as `/repo/:repoId/dialogs/preferences`.
///
/// Deliberately does not reproduce the Qt app's proactive "this repository
/// would load faster with a commit-graph" advice banner (shouldOfferCommitGraph()'s
/// per-repository "asked already" state, tracked via QSettings there) --
/// this dialog exposes the same "Optimize Now" action directly instead of
/// gating it behind a dismissible nag, which needs no persisted preference
/// of its own to be useful.
class PreferencesDialogContent extends ConsumerStatefulWidget {
  const PreferencesDialogContent({super.key, required this.identity});

  final RepoIdentity identity;

  @override
  ConsumerState<PreferencesDialogContent> createState() => _PreferencesDialogContentState();
}

class _PreferencesDialogContentState extends ConsumerState<PreferencesDialogContent> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  bool _editedSinceLoad = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final RepoSessionController notifier = ref.read(repoSessionProvider(widget.identity).notifier);
      notifier.refreshLocalIdentity();
      notifier.refreshEffectiveIdentity();
      notifier.refreshHasCommitGraph();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _syncControllersFrom(LocalIdentity identity) {
    if (_editedSinceLoad) return;
    _nameController.text = identity.name;
    _emailController.text = identity.email;
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final RepoSessionState session = ref.watch(repoSessionProvider(widget.identity));
    final RepoSessionController notifier = ref.read(repoSessionProvider(widget.identity).notifier);
    _syncControllersFrom(session.localIdentity);

    return GbmDialogShell(
      title: 'Preferences',
      width: 560,
      actions: <Widget>[GbmButton(label: 'Close', kind: GbmButtonKind.primary, onPressed: () => context.pop())],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('GIT IDENTITY', style: TextStyle(fontSize: GbmTypography.textXs, fontWeight: GbmTypography.weightSemibold, color: colors.textTertiary, letterSpacing: 0.5)),
          const SizedBox(height: GbmSpacing.space2),
          Text(
            'Effective for new commits here: ${session.effectiveIdentity.name} <${session.effectiveIdentity.email}>',
            style: TextStyle(fontSize: GbmTypography.textXs, color: colors.textTertiary),
          ),
          const SizedBox(height: GbmSpacing.space2),
          TextField(
            controller: _nameController,
            onChanged: (_) => setState(() => _editedSinceLoad = true),
            decoration: const InputDecoration(labelText: 'Name (this repository only)', isDense: true, border: OutlineInputBorder()),
          ),
          const SizedBox(height: GbmSpacing.space2),
          TextField(
            controller: _emailController,
            onChanged: (_) => setState(() => _editedSinceLoad = true),
            decoration: const InputDecoration(labelText: 'Email (this repository only)', isDense: true, border: OutlineInputBorder()),
          ),
          const SizedBox(height: GbmSpacing.space2),
          Row(
            children: <Widget>[
              GbmButton(
                label: 'Apply Override',
                kind: GbmButtonKind.primary,
                onPressed: _nameController.text.trim().isEmpty || _emailController.text.trim().isEmpty
                    ? null
                    : () {
                        notifier.setLocalIdentity(_nameController.text.trim(), _emailController.text.trim());
                        setState(() => _editedSinceLoad = false);
                      },
              ),
              const SizedBox(width: GbmSpacing.space2),
              GbmButton(
                label: 'Clear Override',
                onPressed: session.localIdentity.overridden
                    ? () {
                        notifier.clearLocalIdentity();
                        setState(() => _editedSinceLoad = false);
                      }
                    : null,
              ),
            ],
          ),
          const Divider(height: GbmSpacing.space4 * 2),
          Text('PERFORMANCE', style: TextStyle(fontSize: GbmTypography.textXs, fontWeight: GbmTypography.weightSemibold, color: colors.textTertiary, letterSpacing: 0.5)),
          const SizedBox(height: GbmSpacing.space2),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  session.hasCommitGraph
                      ? 'This repository already has a commit-graph.'
                      : 'A commit-graph can speed up history loading for large repositories.',
                  style: TextStyle(fontSize: GbmTypography.textSm, color: colors.textSecondary),
                ),
              ),
              GbmButton(label: 'Optimize Now', onPressed: () => notifier.writeCommitGraph()),
            ],
          ),
          if (session.lastCommitGraphWriteSucceeded case final succeeded?)
            Padding(
              padding: const EdgeInsets.only(top: GbmSpacing.space1),
              child: Text(
                succeeded ? 'Commit-graph written.' : 'Writing the commit-graph failed.',
                style: TextStyle(fontSize: GbmTypography.textXs, color: succeeded ? colors.success : colors.danger),
              ),
            ),
        ],
      ),
    );
  }
}
