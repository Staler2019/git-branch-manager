import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/actions/auto_fetch_gate.dart';

/// Every condition false: the one state in which an auto fetch may run.
const AutoFetchConditions _clear = AutoFetchConditions(
  pausedAfterAuthFailure: false,
  autoFetchInFlight: false,
  dialogOpen: false,
  credentialPromptPending: false,
  conflictActive: false,
  foregroundOperationActive: false,
);

void main() {
  test('runs when nothing stands in the way', () {
    expect(decideAutoFetch(_clear), isA<AutoFetchRun>());
  });

  // One row per reason, every other condition held clear, so each row can
  // only pass by reading its own input.
  final Map<AutoFetchSkipReason, AutoFetchConditions>
  rows = <AutoFetchSkipReason, AutoFetchConditions>{
    AutoFetchSkipReason.pausedAfterAuthFailure: _clear.copyWith(
      pausedAfterAuthFailure: true,
    ),
    AutoFetchSkipReason.autoFetchInFlight: _clear.copyWith(
      autoFetchInFlight: true,
    ),
    // 使用者裁定 2026-10-24: 「開 dialog 時都不能做背景 fetch」 -- a
    // dialog may be showing counts read from origin/X.
    AutoFetchSkipReason.dialogOpen: _clear.copyWith(dialogOpen: true),
    AutoFetchSkipReason.credentialPromptPending: _clear.copyWith(
      credentialPromptPending: true,
    ),
    // Spec P11 item 9: 「有前景作業或處於 conflict 狀態時自動跳過該次」.
    AutoFetchSkipReason.conflictActive: _clear.copyWith(conflictActive: true),
    AutoFetchSkipReason.foregroundOperationActive: _clear.copyWith(
      foregroundOperationActive: true,
    ),
  };

  for (final MapEntry<AutoFetchSkipReason, AutoFetchConditions> row
      in rows.entries) {
    test('skips with ${row.key.name} when only that holds', () {
      final AutoFetchDecision decision = decideAutoFetch(row.value);
      expect(decision, isA<AutoFetchSkip>());
      expect((decision as AutoFetchSkip).reason, row.key);
    });
  }

  test('the table covers every skip reason', () {
    expect(rows.keys.toSet(), AutoFetchSkipReason.values.toSet());
  });

  test('a pause outranks everything else, so its notice is what the log '
      'keeps saying', () {
    const AutoFetchConditions all = AutoFetchConditions(
      pausedAfterAuthFailure: true,
      autoFetchInFlight: true,
      dialogOpen: true,
      credentialPromptPending: true,
      conflictActive: true,
      foregroundOperationActive: true,
    );
    expect(
      (decideAutoFetch(all) as AutoFetchSkip).reason,
      AutoFetchSkipReason.pausedAfterAuthFailure,
    );
  });
}
