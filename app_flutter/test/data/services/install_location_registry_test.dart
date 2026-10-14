import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/services/install_location_registry.dart';

/// `reg query` output, as measured on Windows 11 (four-space separated,
/// header line naming the key, blank lines either side).
const String _query =
    '\r\n'
    'HKEY_CURRENT_USER\\Software\\Git Branch Manager\r\n'
    '    InstallFolder    REG_SZ    C:\\Users\\jane\\AppData\\Local\\Programs\\Git Branch Manager\\\r\n'
    '\r\n';

void main() {
  group('parseRegQueryValue', () {
    test('reads a REG_SZ value, spaces and all', () {
      expect(
        parseRegQueryValue(_query, kInstallLocationRegistryValue),
        r'C:\Users\jane\AppData\Local\Programs\Git Branch Manager\',
      );
    });

    test('reads a REG_EXPAND_SZ value', () {
      expect(
        parseRegQueryValue(
          '    InstallFolder    REG_EXPAND_SZ    D:\\gbm\r\n',
          kInstallLocationRegistryValue,
        ),
        r'D:\gbm',
      );
    });

    // A value whose *name* merely starts with the one asked for is a
    // different value.
    test('does not take a value with a longer name', () {
      expect(
        parseRegQueryValue(
          '    InstallFolderOld    REG_SZ    D:\\old\r\n',
          kInstallLocationRegistryValue,
        ),
        isNull,
      );
    });

    test('answers null when the value is absent', () {
      expect(parseRegQueryValue('', kInstallLocationRegistryValue), isNull);
    });

    test('answers null for an empty value', () {
      expect(
        parseRegQueryValue(
          '    InstallFolder    REG_SZ    \r\n',
          kInstallLocationRegistryValue,
        ),
        isNull,
      );
    });
  });

  group('sameInstallLocation', () {
    test('ignores case, separator style and a trailing separator', () {
      expect(
        sameInstallLocation(
          r'C:\Users\jane\AppData\Local\Programs\Git Branch Manager\',
          'c:/users/jane/appdata/local/programs/git branch manager',
        ),
        isTrue,
      );
    });

    test('tells a copy elsewhere apart', () {
      expect(
        sameInstallLocation(
          r'C:\Users\jane\AppData\Local\Programs\Git Branch Manager',
          r'C:\Users\jane\Desktop\Git Branch Manager',
        ),
        isFalse,
      );
    });

    test('does not take a parent for the folder itself', () {
      expect(
        sameInstallLocation(r'C:\Programs', r'C:\Programs\Git Branch Manager'),
        isFalse,
      );
    });
  });
}
