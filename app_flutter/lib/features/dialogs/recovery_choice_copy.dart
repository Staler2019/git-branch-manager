import '../../data/models/operation_choice.dart';

/// Button label and body-list explanation for an [OperationChoiceKind],
/// composed here rather than read off the wire.
///
/// `OperationChoice`'s wire form (`label`/`explanation` strings) used to
/// cross the FFI boundary from `src/core/git/OperationRunner.h` and be
/// painted verbatim -- both fields are gone now, from the C++ struct through
/// to `OperationChoice.fromJson`, because nothing about them was actually
/// "the wire's own words": core's English ("Stash changes and switch") never
/// matched the spec's quoted button text ("Stash and checkout", `DLGS`'s
/// "Checkout blocked" entry), and the explanation needs to be Chinese
/// regardless of what core sends. Composing here, keyed on
/// [OperationChoiceKind] -- the one part of the payload that is not prose --
/// is the single source both recovery dialogs read from.
///
/// Button labels stay English (§03's rule for primary/secondary buttons,
/// counted 26/0 in `DLGS`). Where a `DLGS` entry names this exact control by
/// wording, that wording is used verbatim; otherwise the existing English is
/// kept and the absence of a citation is recorded below.
String recoveryChoiceLabel(
  OperationChoiceKind kind, {
  required bool forDeleteBranch,
}) {
  switch (kind) {
    case OperationChoiceKind.stashAndRetry:
      // `DLGS`'s "Checkout blocked" entry, `primary: 'Stash and checkout'`
      // and its note: "三個選項都給：Stash and checkout（主）、Discard and
      // checkout（danger）、Cancel。" -- core's own "Stash changes and
      // switch" has no such citation.
      return 'Stash and checkout';
    case OperationChoiceKind.forceDiscard:
      // Delete-branch's "Delete anyway" has no `DLGS`/`DIALOGS` entry for
      // this specific recovery choice (only for the Delete branch dialog
      // itself, a different screen) -- kept as core's existing English.
      // Checkout's "Discard and checkout" is the DLGS-cited counterpart.
      return forDeleteBranch ? 'Delete anyway' : 'Discard and checkout';
    case OperationChoiceKind.abort:
      return 'Cancel';
    case OperationChoiceKind.retry:
      // No `DLGS` entry covers the index.lock recovery choices; kept as
      // core's existing English.
      return 'Retry';
    case OperationChoiceKind.removeLock:
      return 'Remove index.lock';
  }
}

/// The Chinese sentence drawn under a choice's label in the body list.
///
/// [forDeleteBranch]'s [OperationChoiceKind.forceDiscard] arm is
/// deliberately generic rather than restating *why* the branch cannot be
/// deleted normally: that reason (whether the branch's commits exist
/// elsewhere, or genuinely nowhere else) is already drawn above the choices
/// list from [RepoSessionState.lastError.message] --
/// `BranchOps.cpp`'s `deleteAnywayExplanation` is exactly the text that
/// becomes that message (`RepoSessionController._errorFromOutcomePayload`
/// falls back to `summary` when there is no formal `GitError`), so this
/// sentence would only repeat it.
String recoveryChoiceExplanation(
  OperationChoiceKind kind, {
  required bool forDeleteBranch,
}) {
  switch (kind) {
    case OperationChoiceKind.stashAndRetry:
      return '你的變更會先存進 stash，之後可以再取回來。';
    case OperationChoiceKind.forceDiscard:
      return forDeleteBranch
          ? '強制刪除；之後只能透過 reflog 找回這個分支上的 commit。'
          : '未提交的變更會被永久丟棄，無法復原。';
    case OperationChoiceKind.abort:
      return forDeleteBranch ? '保留這個分支。' : '留在目前的分支上。';
    case OperationChoiceKind.retry:
      return '等另一個 Git 程序結束後再試一次。';
    case OperationChoiceKind.removeLock:
      return '鎖已經超過 10 分鐘。只有在確定沒有其他 Git 程序在跑的時候才移除——刪掉一個還在使用中的鎖會弄壞 index。';
  }
}
