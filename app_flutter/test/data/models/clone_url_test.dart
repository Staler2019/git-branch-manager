// DLGS Clone: 「URL 貼上後自動帶出資料夾名，可手改」 -- the folder name git
// itself would pick (`git clone <url>` with no directory).
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/clone_url.dart';

void main() {
  const Map<String, String> cases = <String, String>{
    'https://github.com/org/design-tokens.git': 'design-tokens',
    'https://github.com/org/design-tokens': 'design-tokens',
    'https://github.com/org/design-tokens/': 'design-tokens',
    'https://github.com/org/design-tokens.git/': 'design-tokens',
    'https://alice:pw@host/org/r.git': 'r',
    'ssh://git@host:2222/org/r.git': 'r',
    'git@github.com:Staler2019/git-branch-manager.git': 'git-branch-manager',
    'git@github.com:solo.git': 'solo',
    '/srv/git/bare/.git': 'bare',
    r'C:\repos\thing.git': 'thing',
    '  https://h/o/r.git  ': 'r',
    '': '',
    'https://': '',
  };
  for (final MapEntry<String, String> c in cases.entries) {
    test('"${c.key}" -> "${c.value}"', () {
      expect(cloneFolderNameFromUrl(c.key), c.value);
    });
  }
}
