import '../../../data/models/ref_snapshot.dart';

/// Groups refs pointing to a single commit into chip data.
/// Returns a list of RefInfo for all refs targeting the given OID.
List<RefInfo> refChipsForCommit(RefSnapshot refs, String targetOid) {
  final chips = <RefInfo>[];

  // Collect all refs pointing to this commit
  for (final ref in refs.refs) {
    if (ref.target == targetOid) {
      chips.add(ref);
    }
  }

  return chips;
}
