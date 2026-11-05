import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/services/install_location_registry.dart';

void main() {
  group('readCurrentUserRegistryString', () {
    const String subKey = r'Software\Git Branch Manager Test';
    final String regExe =
        '${Platform.environment['SystemRoot']}'
        r'\System32\reg.exe';

    void regAdd(String value, String data) {
      final ProcessResult added = Process.runSync(regExe, <String>[
        'add',
        'HKCU\\$subKey',
        '/v',
        value,
        '/d',
        data,
        '/f',
      ]);
      expect(added.exitCode, 0, reason: '${added.stderr}');
    }

    tearDown(() {
      Process.runSync(regExe, <String>['delete', 'HKCU\\$subKey', '/f']);
    });

    // What reg.exe and a pipe could not carry: under CI's code page 1252
    // these characters do not survive, and under the app's UTF-8 ACP a user's
    // CP950 output would not decode.
    test('reads a Chinese value exactly', () {
      const String folder = r'C:\Users\王小明\工作樹 x\';
      regAdd('InstallFolder', folder);
      expect(readCurrentUserRegistryString(subKey, 'InstallFolder'), folder);
    });

    test('answers null when the value is absent', () {
      regAdd('Other', 'x');
      expect(readCurrentUserRegistryString(subKey, 'InstallFolder'), isNull);
    });

    test('answers null when the key is absent', () {
      expect(
        readCurrentUserRegistryString(r'Software\Gbm No Such Key', 'x'),
        isNull,
      );
    });

    test('answers null for an empty value', () {
      regAdd('InstallFolder', '');
      expect(readCurrentUserRegistryString(subKey, 'InstallFolder'), isNull);
    });
  }, skip: Platform.isWindows ? false : 'reads the real Windows registry');

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
