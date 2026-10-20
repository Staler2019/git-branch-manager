import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/clone_job.dart';
import '../../../data/repositories/clone_job_repository.dart';
import 'credential_form_body.dart';

/// A clone job's askpass prompt (C2's `gbm_clone_provide_credential` /
/// `_cancel_credential`), owned by no repository session (security review
/// P3-J3). Pushed by `CloneJobListener` when job [jobId] asks.
///
/// Popped without an answer -- Esc, the barrier -- is Cancel, as for the
/// session's dialog, so git is not left waiting. When the job stops asking
/// on its own (it ended, or was answered elsewhere) the dialog closes
/// itself without answering.
class CloneCredentialDialogContent extends ConsumerStatefulWidget {
  const CloneCredentialDialogContent({super.key, required this.jobId});

  final int jobId;

  @override
  ConsumerState<CloneCredentialDialogContent> createState() =>
      _CloneCredentialDialogContentState();
}

class _CloneCredentialDialogContentState
    extends ConsumerState<CloneCredentialDialogContent> {
  final TextEditingController _secret = TextEditingController();
  bool _resolved = false;

  /// Held for [dispose], where `ref` can no longer be used.
  late final CloneJobController _jobs;

  @override
  void initState() {
    super.initState();
    _jobs = ref.read(cloneJobsProvider.notifier);
    // The listener in build() fires only when the prompt *changes* to null
    // ([FLU-listen-misses-the-current-value]). A job that ended before this
    // first build, or a `?job=` naming no live job, leaves it null from the
    // start, so that case is checked once here (verifier A1). initState runs
    // inside a frame's build, so the callback runs at the end of that same
    // frame; nothing has to schedule one ([FLU-postframe-no-frame]), and
    // neither an answer nor a dispose can have happened before it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_prompt(ref.read(cloneJobsProvider)) == null) _close();
    });
  }

  @override
  void dispose() {
    if (!_resolved && _jobs.mounted) {
      // After the frame: clearing the prompt is a provider write, which
      // Riverpod forbids while the tree is being finalized.
      final CloneJobController jobs = _jobs;
      final int id = widget.jobId;
      unawaited(
        Future<void>.microtask(() {
          if (jobs.mounted) jobs.cancelCredential(id);
        }),
      );
    }
    _secret.dispose();
    super.dispose();
  }

  String? _prompt(List<CloneJob> jobs) {
    for (final CloneJob job in jobs) {
      if (job.id == widget.jobId) return job.credentialPrompt;
    }
    return null;
  }

  void _close() {
    _resolved = true;
    context.pop();
  }

  /// Resolved before answering: the answer clears the prompt, and the
  /// listener below must not read that as the job going away.
  void _answer(VoidCallback send) {
    _resolved = true;
    send();
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(cloneJobsProvider.select(_prompt), (_, String? next) {
      if (next == null && !_resolved) _close();
    });
    return CredentialFormBody(
      prompt: _prompt(ref.watch(cloneJobsProvider)) ?? '',
      controller: _secret,
      onCancel: () => _answer(() => _jobs.cancelCredential(widget.jobId)),
      onSubmit: () =>
          _answer(() => _jobs.provideCredential(widget.jobId, _secret.text)),
    );
  }
}
