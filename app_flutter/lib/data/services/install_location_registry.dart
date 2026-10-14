import 'dart:io';

/// Where the Windows installer records the folder it installed into.
///
/// Written by `windows/installer/Package.wxs` under HKCU, and read back by
/// both that installer (so an upgrade lands in the same folder) and the app
/// (so it knows whether the copy running is the one Windows Installer
/// manages). The three names must agree byte for byte with the `.wxs`.
const String kInstallLocationRegistryKey = r'HKCU\Software\Git Branch Manager';

/// The value under [kInstallLocationRegistryKey].
const String kInstallLocationRegistryValue = 'InstallFolder';

/// Reads the folder the Windows installer recorded, or null when there is
/// none. Synchronous because `UpdateInstaller.selfInstallBlocker` is, and
/// injected so tests never touch the registry of the machine running them.
typedef InstallLocationReader = String? Function();

/// The real [InstallLocationReader]: `reg query` by absolute path.
///
/// `reg.exe` rather than FFI into `advapi32`, because the answer is one
/// string read once per update check and the process seam is already how
/// this feature talks to the OS. By absolute path for the same reason the
/// updater starts PowerShell that way: a mangled `PATH`, or a `reg.exe`
/// planted in the working directory, must not decide the answer.
///
/// Never throws: a registry that cannot be read is treated as "not
/// installed by the installer", which is the answer that offers the least.
String? readInstallLocationFromRegistry() {
  final String? root = Platform.environment['SystemRoot'];
  if (root == null || root.isEmpty) {
    return null;
  }
  try {
    final ProcessResult result = Process.runSync(
      '$root\\System32\\reg.exe',
      <String>[
        'query',
        kInstallLocationRegistryKey,
        '/v',
        kInstallLocationRegistryValue,
      ],
    );
    if (result.exitCode != 0) {
      return null;
    }
    return parseRegQueryValue(
      '${result.stdout}',
      kInstallLocationRegistryValue,
    );
  } on Object {
    return null;
  }
}

/// Pulls the data of value [name] out of `reg query` output, or null.
///
/// The line is `<4 spaces><name><4 spaces><type><4 spaces><data>`; the data
/// may itself contain spaces, so everything after the type is kept.
String? parseRegQueryValue(String output, String name) {
  final RegExp line = RegExp(
    '^\\s+${RegExp.escape(name)}\\s{2,}REG_(?:EXPAND_)?SZ\\s{2,}(.*)\$',
    caseSensitive: false,
  );
  for (final String raw in output.split(RegExp(r'\r?\n'))) {
    final RegExpMatch? match = line.firstMatch(raw);
    if (match != null) {
      final String value = match.group(1)!.trim();
      return value.isEmpty ? null : value;
    }
  }
  return null;
}

/// Whether two Windows paths name the same folder, the way Windows compares
/// them: case-insensitively, either separator, trailing separator ignored.
///
/// The installer writes `INSTALLFOLDER` with its trailing backslash, while
/// `Platform.resolvedExecutable`'s parent has none.
bool sameInstallLocation(String a, String b) => _normalise(a) == _normalise(b);

String _normalise(String path) =>
    path.replaceAll('/', r'\').replaceAll(RegExp(r'\\+$'), '').toLowerCase();
