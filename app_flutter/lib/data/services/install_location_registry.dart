import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

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

/// The real [InstallLocationReader].
///
/// Never throws: a registry that cannot be read is treated as "not installed
/// by the installer", which is the answer that offers the least.
String? readInstallLocationFromRegistry() {
  if (!Platform.isWindows) {
    return null;
  }
  return readCurrentUserRegistryString(
    kInstallLocationRegistryKey.replaceFirst(r'HKCU\', ''),
    kInstallLocationRegistryValue,
  );
}

typedef _RegGetValueNative = Int32 Function(
  IntPtr key,
  Pointer<Utf16> subKey,
  Pointer<Utf16> value,
  Uint32 flags,
  Pointer<Uint32> type,
  Pointer<Void> data,
  Pointer<Uint32> byteCount,
);
typedef _RegGetValueDart = int Function(
  int key,
  Pointer<Utf16> subKey,
  Pointer<Utf16> value,
  int flags,
  Pointer<Uint32> type,
  Pointer<Void> data,
  Pointer<Uint32> byteCount,
);

/// `HKEY_CURRENT_USER`: the Win32 constant is `(HKEY)(LONG)0x80000001`, so it
/// is sign-extended to pointer width.
final int _hkeyCurrentUser = 0x80000001.toSigned(32);
const int _rrfRtRegSz = 0x2;
const int _rrfRtRegExpandSz = 0x4;
const int _errorSuccess = 0;

/// A string value under `HKEY_CURRENT_USER`, or null when it is absent, empty
/// or unreadable. Windows only.
///
/// `RegGetValueW` rather than parsing `reg.exe`, because a pipe has no encoding
/// both sides agree on: reg.exe writes in the system's code page, while this
/// process runs with `activeCodePage` UTF-8 (`runner.exe.manifest`), so a Chinese
/// user name would decode wrong and the installed copy would look unmanaged.
/// `advapi32.dll` is a KnownDLL, so it cannot be planted beside the executable.
String? readCurrentUserRegistryString(String subKey, String value) {
  final Pointer<Utf16> subKeyPtr = subKey.toNativeUtf16();
  final Pointer<Utf16> valuePtr = value.toNativeUtf16();
  final Pointer<Uint32> byteCount = malloc<Uint32>();
  Pointer<Uint16> data = nullptr;
  try {
    final _RegGetValueDart regGetValue = DynamicLibrary.open('advapi32.dll')
        .lookupFunction<_RegGetValueNative, _RegGetValueDart>('RegGetValueW');
    const int flags = _rrfRtRegSz | _rrfRtRegExpandSz;
    byteCount.value = 0;
    if (regGetValue(
              _hkeyCurrentUser,
              subKeyPtr,
              valuePtr,
              flags,
              nullptr,
              nullptr,
              byteCount,
            ) !=
            _errorSuccess ||
        byteCount.value == 0) {
      return null;
    }
    data = malloc<Uint16>((byteCount.value ~/ sizeOf<Uint16>()) + 1);
    if (regGetValue(
          _hkeyCurrentUser,
          subKeyPtr,
          valuePtr,
          flags,
          nullptr,
          data.cast<Void>(),
          byteCount,
        ) !=
        _errorSuccess) {
      return null;
    }
    final String text = data.cast<Utf16>().toDartString();
    return text.isEmpty ? null : text;
  } on Object {
    return null;
  } finally {
    malloc.free(subKeyPtr);
    malloc.free(valuePtr);
    malloc.free(byteCount);
    if (data != nullptr) {
      malloc.free(data);
    }
  }
}

/// Whether two Windows paths name the same folder, the way Windows compares
/// them: case-insensitively, either separator, trailing separator ignored.
///
/// The installer writes `INSTALLFOLDER` with its trailing backslash, while
/// `Platform.resolvedExecutable`'s parent has none.
bool sameInstallLocation(String a, String b) => _normalise(a) == _normalise(b);

String _normalise(String path) =>
    path.replaceAll('/', r'\').replaceAll(RegExp(r'\\+$'), '').toLowerCase();
