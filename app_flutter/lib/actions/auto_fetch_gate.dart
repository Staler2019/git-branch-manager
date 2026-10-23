/// Whether the periodic auto fetch (Preferences → General, spec P11 item 9)
/// may run right now. Pure data, no Riverpod/FFI -- the same shape as
/// `isActionEnabled` in `gbm_action_availability.dart`; the scheduler reads
/// each input from its single source and passes it in.
library;

/// Why an auto fetch was skipped this time. The order of the values is the
/// order [decideAutoFetch] checks them in.
enum AutoFetchSkipReason {
  /// An Auth/HostKey failure paused auto fetch until a manual fetch succeeds
  /// (使用者裁定 2026-10-23): retrying a rejected credential every interval
  /// can drop it from the keychain or trip a server's ban.
  pausedAfterAuthFailure,

  /// The previous auto fetch has not finished yet.
  autoFetchInFlight,

  /// 使用者裁定 2026-10-24: 「開 dialog 時都不能做背景 fetch」 -- a dialog
  /// (Force Push most of all) may be showing counts read from a remote-tracking
  /// ref that a fetch would move underneath it.
  dialogOpen,

  /// git is waiting for the user to answer a credential prompt.
  credentialPromptPending,

  /// Spec P11 item 9: 「處於 conflict 狀態時自動跳過該次」.
  conflictActive,

  /// Spec P11 item 9: 「有前景作業…時自動跳過該次」.
  foregroundOperationActive,
}

/// The inputs, each read by the caller from its single source.
class AutoFetchConditions {
  const AutoFetchConditions({
    required this.pausedAfterAuthFailure,
    required this.autoFetchInFlight,
    required this.dialogOpen,
    required this.credentialPromptPending,
    required this.conflictActive,
    required this.foregroundOperationActive,
  });

  final bool pausedAfterAuthFailure;
  final bool autoFetchInFlight;
  final bool dialogOpen;
  final bool credentialPromptPending;
  final bool conflictActive;
  final bool foregroundOperationActive;

  AutoFetchConditions copyWith({
    bool? pausedAfterAuthFailure,
    bool? autoFetchInFlight,
    bool? dialogOpen,
    bool? credentialPromptPending,
    bool? conflictActive,
    bool? foregroundOperationActive,
  }) => AutoFetchConditions(
    pausedAfterAuthFailure:
        pausedAfterAuthFailure ?? this.pausedAfterAuthFailure,
    autoFetchInFlight: autoFetchInFlight ?? this.autoFetchInFlight,
    dialogOpen: dialogOpen ?? this.dialogOpen,
    credentialPromptPending:
        credentialPromptPending ?? this.credentialPromptPending,
    conflictActive: conflictActive ?? this.conflictActive,
    foregroundOperationActive:
        foregroundOperationActive ?? this.foregroundOperationActive,
  );
}

sealed class AutoFetchDecision {
  const AutoFetchDecision();
}

final class AutoFetchRun extends AutoFetchDecision {
  const AutoFetchRun();
}

final class AutoFetchSkip extends AutoFetchDecision {
  const AutoFetchSkip(this.reason);

  final AutoFetchSkipReason reason;
}

/// Run, or skip with the first reason in [AutoFetchSkipReason]'s order. A
/// skipped tick is not retried early: the next one comes at the next
/// interval, as spec P11 item 9's 「自動跳過該次」 says.
AutoFetchDecision decideAutoFetch(AutoFetchConditions c) {
  final AutoFetchSkipReason? reason = switch (c) {
    AutoFetchConditions(pausedAfterAuthFailure: true) =>
      AutoFetchSkipReason.pausedAfterAuthFailure,
    AutoFetchConditions(autoFetchInFlight: true) =>
      AutoFetchSkipReason.autoFetchInFlight,
    AutoFetchConditions(dialogOpen: true) => AutoFetchSkipReason.dialogOpen,
    AutoFetchConditions(credentialPromptPending: true) =>
      AutoFetchSkipReason.credentialPromptPending,
    AutoFetchConditions(conflictActive: true) =>
      AutoFetchSkipReason.conflictActive,
    AutoFetchConditions(foregroundOperationActive: true) =>
      AutoFetchSkipReason.foregroundOperationActive,
    _ => null,
  };
  return reason == null ? const AutoFetchRun() : AutoFetchSkip(reason);
}
