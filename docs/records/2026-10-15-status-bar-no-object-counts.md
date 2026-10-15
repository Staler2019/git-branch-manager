# The status bar's git tasks show no object counts; the spec's `N / M objects` is revised away

- **Kind**: ruling · **Pins**: `TEST-no-pumpandsettle-with-spinner` · **Code**: `running_git_tasks.dart`'s `backgroundTasksFromOperationLog` (`total: 0`), `status_bar.dart`'s `_barValue`

## Situation
Spec page 10's status-bar mockup draws a running fetch as `Fetching origin · 199,960 / 199,960 objects` with a Cancel button. Core reports no object counts: a git invocation's progress reaches Dart only as a running `OperationRecord`, which carries argv and a queued id, never a `Receiving objects` figure. Before this round a task with no total drew a static empty bar and the text `N/0`, which the user read as 「不知道有沒有在跑」.

## Task
Decide what a git task shows when its total is unknown, and whether to plan parsing git's `--progress` stream for counts.

## Action
- 使用者裁定（2026-10-15，原文）：計數「改spec，沒有計畫」. The spec is revised by this record: a git task shows its label and an **indeterminate** bar; no `N / M objects` text, and no plan to produce one.
- `BackgroundTask.gitCommand` sets `total: 0`; `_barValue` returns `null` (indeterminate) while `total <= 0`, so the count text is omitted rather than drawn as `N/0`.
- The spec HTML itself (`docs/claude-design-demo/`) is a design import and is not edited; this record is where the deviation lives, as with every other spec ruling under `docs/records/`.

## Result
Pinned by `running_git_tasks_test.dart` ('no object counts from core') and `status_bar_test.dart`'s indeterminate-bar tests. Consequence for tests: an indeterminate bar schedules frames forever, so `pumpAndSettle` cannot be used while a git task runs ([TEST-no-pumpandsettle-with-spinner]). Evidence: [ledger: fix/status-bar-running-tasks](../ledger/2026-10-15-fix-status-bar-running-tasks.md).
