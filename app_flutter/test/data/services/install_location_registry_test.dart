import 'dart:io';

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

  // The key and value are written by the installer and read here, in two
  // languages that share no symbol. A rename on one side only would leave
  // every installed copy reporting "not installed with the installer".
  group('the installer source', () {
    final String wxs = File('windows/installer/Package.wxs').readAsStringSync();
    final String key = kInstallLocationRegistryKey.replaceFirst(r'HKCU\', '');

    test('writes the folder under the key and value this reads', () {
      expect(
        wxs,
        contains(
          '<RegistryKey Root="HKCU" Key="$key" ForceDeleteOnUninstall="yes">',
        ),
      );
      expect(
        wxs,
        contains(
          '<RegistryValue Name="$kInstallLocationRegistryValue" '
          'Type="string" Value="[INSTALLFOLDER]" KeyPath="yes" />',
        ),
      );
    });

    // Read back by the installer itself, so an upgrade started by hand from
    // the .msi lands in the same folder the app reports.
    test('remembers the folder across upgrades', () {
      expect(
        wxs,
        contains(
          '<RegistrySearch Root="HKCU" Key="$key" '
          'Name="$kInstallLocationRegistryValue" Type="raw" />',
        ),
      );
    });

    test('installs per user, never per machine', () {
      expect(wxs, contains('Scope="perUser"'));
      expect(wxs, isNot(contains('perUserOrMachine')));
      expect(wxs, isNot(contains('CustomAction')));
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
