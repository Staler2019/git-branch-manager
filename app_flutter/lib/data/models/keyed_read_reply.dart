import 'git_error.dart';

/// The latest answer to one read whose surface waits on it, together with
/// the request it answers (read-failure-states-spec.html).
///
/// A request installs [KeyedReadReply.pending] for its key at once, so the
/// previous subject's content is gone the moment the subject changes (ruling
/// 4); a reply whose key differs from the installed one is dropped. A
/// surface draws [value] or [error] only while [key] is the key it last sent.
class KeyedReadReply<K extends Object, V extends Object> {
  /// Sent, not yet answered.
  const KeyedReadReply.pending(this.key) : value = null, error = null;

  const KeyedReadReply.succeeded(this.key, V this.value) : error = null;

  /// A failed read: a failure reply, or an export that queued nothing.
  const KeyedReadReply.failed(this.key, GitError this.error) : value = null;

  final K key;
  final V? value;
  final GitError? error;
}
