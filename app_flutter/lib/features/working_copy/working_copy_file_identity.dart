import '../../data/models/working_copy_status.dart';

/// The single string that stands for an entry's logical file, used as the key
/// of the Working Copy board's one shared selection set.
///
/// Selecting a file has to light it up on **both** columns at once, and the two
/// sides do not always agree on what it is called. A staged rename is one
/// [WorkingCopyEntry] whose `path` is the new name and whose `oldPath` is the
/// old one; if the old name then reappears in the work tree it arrives as a
/// second entry named after the old path. Those two rows are the same file to
/// the person looking at them, and comparing `path` alone would never say so.
///
///
/// Canonicalises on `oldPath` when there is one, so a rename's two rows
/// produce the same key. That is enough precisely because a
/// [WorkingCopyStatus] holds **at most one entry per `path`** -- the staged
/// and unstaged lists are two filters over the same `entries` list, so two
/// *distinct* rows can only ever be the same logical file via a rename's
/// old/new pair, which is the case this collapses. Two rows that share a
/// `path` are literally the same object.
///
/// Keeping one function as the single source of "which file is this row
/// about" is deliberate: the moment the two columns each derive it their own
/// way, they can disagree, and a selection that highlights one side but not
/// the other is exactly the bug that cannot reproduce itself in a test that
/// only looks at one column.
String logicalFileKey(WorkingCopyEntry entry) =>
    entry.oldPath.isEmpty ? entry.path : entry.oldPath;
