import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/url_credential_redaction.dart';

void main() {
  // Rulings R6/R7/ASK-4 (2026-10-19): mask only the password when there is
  // one; with no ':' the whole userinfo for every scheme but ssh's; scp
  // syntax is not a URL and is left alone.
  const List<(String, String, String)> cases = <(String, String, String)>[
    // R7: userinfo with ':' -> only the password segment.
    (
      'user and password',
      'https://alice:s3cret@github.com/org/repo.git',
      'https://alice:••••@github.com/org/repo.git',
    ),
    (
      'ssh with a password',
      'ssh://alice:s3cret@host/repo',
      'ssh://alice:••••@host/repo',
    ),
    // R7: no ':' -> whole userinfo for http(s), kept for ssh.
    (
      'a bare token as the user',
      'https://ghp_abc123@github.com/org/repo',
      'https://••••@github.com/org/repo',
    ),
    (
      'ssh user only',
      'ssh://git@github.com/org/repo',
      'ssh://git@github.com/org/repo',
    ),
    ('git+ssh user only', 'git+ssh://git@host/r', 'git+ssh://git@host/r'),
    ('ssh+git user only', 'ssh+git://git@host/r', 'ssh+git://git@host/r'),
    ('ftp user only', 'ftp://anon@host/f', 'ftp://••••@host/f'),
    // ASK-4: a token in the user slot with an empty or placeholder password.
    (
      'x-oauth-basic',
      'https://TOKEN123:x-oauth-basic@github.com/o/r',
      'https://••••@github.com/o/r',
    ),
    (
      'empty password',
      'https://TOKEN123:@github.com/o/r',
      'https://••••@github.com/o/r',
    ),
    // Not URLs, or no userinfo.
    (
      'scp syntax',
      'git@github.com:org/repo.git',
      'git@github.com:org/repo.git',
    ),
    (
      'no userinfo',
      'https://github.com/org/repo',
      'https://github.com/org/repo',
    ),
    ('plain text', 'Opened repository /tmp/a@b', 'Opened repository /tmp/a@b'),
    // P3-F edge cases.
    (
      'last @ splits the userinfo',
      'https://a@b:p@ss@host/r',
      'https://a@b:••••@host/r',
    ),
    (
      'percent-encoded password',
      'https://alice:p%40ss%3Aword@host/r',
      'https://alice:••••@host/r',
    ),
    (
      'scheme in upper case',
      'HTTPS://alice:s3cret@host/r',
      'HTTPS://alice:••••@host/r',
    ),
    ('SSH in upper case', 'SSH://git@host/r', 'SSH://git@host/r'),
    (
      'two URLs on one line',
      'git clone https://a:x@h1/r https://tok@h2/r',
      'git clone https://a:••••@h1/r https://••••@h2/r',
    ),
    (
      'quoted',
      "fatal: unable to access 'https://alice:s3cret@host/r/': 403",
      "fatal: unable to access 'https://alice:••••@host/r/': 403",
    ),
    ('in parentheses', '(https://tok@host)', '(https://••••@host)'),
    (
      'authority ends at query',
      'https://host/r?x=a:b@c',
      'https://host/r?x=a:b@c',
    ),
    (
      'multi-line stderr',
      'Cloning into x...\nfatal: https://alice:s3cret@host/r not found\n',
      'Cloning into x...\nfatal: https://alice:••••@host/r not found\n',
    ),
    (
      'ipv6 host',
      'https://alice:pw@[::1]:8080/r',
      'https://alice:••••@[::1]:8080/r',
    ),
    // Each terminator matters only when no '/' comes first and an '@'
    // follows later in the text: otherwise the authority would swallow it.
    (
      'ends at whitespace',
      'https://host and bob@corp',
      'https://host and bob@corp',
    ),
    (
      'ends at a quote',
      "url='https://host',user='a@b'",
      "url='https://host',user='a@b'",
    ),
    ('ends at a bracket', '(https://host),(a@b)', '(https://host),(a@b)'),
    ('ends at a query', 'https://host?x=a@b', 'https://host?x=a@b'),
    (
      'password with a colon',
      'https://alice:pa:ss@host/r',
      'https://alice:••••@host/r',
    ),
  ];

  for (final (String name, String input, String expected) in cases) {
    test(name, () => expect(redactUrlCredentials(input), expected));
  }

  test('redacting twice changes nothing more', () {
    for (final (_, String input, _) in cases) {
      final String once = redactUrlCredentials(input);
      expect(redactUrlCredentials(once), once);
    }
  });
}
