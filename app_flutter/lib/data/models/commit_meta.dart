import 'signature.dart';

/// Mirrors `gbm::CommitMeta` (src/core/git/CommitMeta.h) as serialized by
/// `capi::toJson(const CommitMeta&)`. Fetched in batches keyed by oid via
/// `gbm_request_commit_meta`/`GBM_EVENT_COMMIT_META_READY` -- see
/// history_repository.dart's `commitMetaProvider`.
class CommitMeta {
  const CommitMeta({
    required this.oid,
    required this.tree,
    required this.parents,
    required this.author,
    required this.committer,
    required this.subject,
    required this.body,
    required this.signedCommit,
  });

  factory CommitMeta.fromJson(Map<String, dynamic> json) {
    return CommitMeta(
      oid: json['oid'] as String,
      tree: json['tree'] as String,
      parents: (json['parents'] as List<dynamic>).cast<String>(),
      author: Signature.fromJson(json['author'] as Map<String, dynamic>),
      committer: Signature.fromJson(json['committer'] as Map<String, dynamic>),
      subject: json['subject'] as String,
      body: json['body'] as String,
      signedCommit: json['signed'] as bool,
    );
  }

  static List<CommitMeta> listFromJson(List<dynamic> json) => json
      .map((e) => CommitMeta.fromJson(e as Map<String, dynamic>))
      .toList(growable: false);

  final String oid;
  final String tree;
  final List<String> parents;
  final Signature author;
  final Signature committer;
  final String subject;
  final String body;
  final bool signedCommit;
}
