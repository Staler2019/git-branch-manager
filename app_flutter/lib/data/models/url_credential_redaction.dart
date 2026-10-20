/// Masks credentials carried inside URLs in [text], wherever they appear:
/// a git argv element, a command line, stderr, or a message the app composed.
///
/// Rulings R6/R7/ASK-4 (2026-10-19), applied at the source so the log, its
/// export and any future telemetry exporter all receive the same masked
/// text:
///
///  * userinfo with a `:` keeps the user and masks the password
///    (`alice:••••@`);
///  * userinfo without a `:` is masked whole (`••••@`) -- except for the ssh
///    schemes (`ssh`, `git+ssh`, `ssh+git`), where it is a login name, not a
///    secret;
///  * a password that is empty or GitHub's `x-oauth-basic` placeholder means
///    the token is in the user slot, so the whole userinfo is masked;
///  * scp syntax (`git@host:org/repo`) is not a URL and is left alone.
///
/// The userinfo ends at the authority's *last* `@`, and the authority ends at
/// the first `/`, `?`, `#`, whitespace, quote or bracket, so a URL quoted in
/// git's stderr or wrapped in parentheses is still found. Idempotent: masked
/// text comes back unchanged.
String redactUrlCredentials(String text) {
  return text.replaceAllMapped(_urlAuthority, (Match m) {
    final String scheme = m.group(1)!;
    final String authority = m.group(2)!;
    final int at = authority.lastIndexOf('@');
    if (at < 0) return m.group(0)!;
    final String userinfo = authority.substring(0, at);
    final String host = authority.substring(at + 1);
    return '$scheme://${_maskUserinfo(scheme, userinfo)}@$host';
  });
}

const String _mask = '••••';

final RegExp _urlAuthority = RegExp(
  r'''([A-Za-z][A-Za-z0-9+.\-]*)://([^\s/?#'"<>()`\\]*)''',
);

const Set<String> _sshSchemes = <String>{'ssh', 'git+ssh', 'ssh+git'};

String _maskUserinfo(String scheme, String userinfo) {
  final int colon = userinfo.indexOf(':');
  if (colon < 0) {
    return _sshSchemes.contains(scheme.toLowerCase()) ? userinfo : _mask;
  }
  final String password = userinfo.substring(colon + 1);
  if (password.isEmpty || password == 'x-oauth-basic') return _mask;
  return '${userinfo.substring(0, colon)}:$_mask';
}
