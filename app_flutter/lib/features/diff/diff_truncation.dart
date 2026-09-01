/// What every diff surface says when the core refused to parse a diff.
///
/// `ParsedDiff.truncated` means the diff exceeded `UnifiedDiffParser`'s byte
/// cap and **nothing was parsed** -- `files` is empty. It used to mean
/// something weaker: the first 2 MiB was parsed and the tail dropped, which
/// put a diff on screen that looked complete and was not. Either way the flag
/// crossed the FFI and was read by nothing, so both the too-large case and the
/// genuinely-unchanged case drew the same "no changes" text.
///
/// The label is shared rather than written at each surface because the two
/// disagreeing would be exactly the kind of split this repo keeps finding: one
/// pane calling a refusal "no changes" while the other names it.
///
/// It deliberately does **not** name the byte cap. The number lives in
/// `UnifiedDiffParser::Options::maxBytes` on the C++ side, and a copy of it
/// here would be a second source of truth that nothing keeps in step.
const String kDiffTooLargeLabel = 'Diff too large to display';
