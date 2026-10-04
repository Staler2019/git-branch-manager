// Signature parity between `src/capi/gbm_capi.h` and `gbm_bindings.dart`.
//
// `dart:ffi`'s `lookupFunction` matches by symbol name only, never by
// signature ([TEST-ffi-matches-symbol-only]). A capi parameter added, dropped,
// retyped or reordered without the matching `_XxxNative` typedef change
// analyzes, unit-tests and capi-tests clean, then corrupts the stack at
// runtime. This file reads both sources as text -- it cannot import the
// header -- and checks, per binding: the symbol exists in the header, the
// parameter count matches, and the return type and every parameter type map
// one-to-one through `_cToFfi` below.
//
// **Known limit**: two parameters of the same type swapped (for example
// `gbm_rebase_start`'s `rebaseMerges` <-> `autosquash`, both `int32_t`) are
// invisible here -- the types still line up. Only a device-tier test that
// drives the behaviour across `dart:ffi` can see that (#159's option B).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every C type `gbm_capi.h` uses, and the one FFI type it must bind to.
/// A type missing from this table fails the test rather than being skipped:
/// a new type needs a deliberate entry here first.
const Map<String, String> _cToFfi = <String, String>{
  'void': 'Void',
  'int32_t': 'Int32',
  'int64_t': 'Int64',
  'uint64_t': 'Uint64',
  'const char*': 'Pointer<Utf8>',
  'const char* const*': 'Pointer<Pointer<Utf8>>',
  'int32_t*': 'Pointer<Int32>',
  'const int32_t*': 'Pointer<Int32>',
  'uint8_t*': 'Pointer<Uint8>',
  'const uint8_t*': 'Pointer<Uint8>',
  'const uint32_t*': 'Pointer<Uint32>',
  'void*': 'Pointer<Void>',
  'GbmSessionHandle': 'Pointer<Void>',
  'GbmDiscoveryHandle': 'Pointer<Void>',
  'GbmEventCallback': 'Pointer<NativeFunction<GbmEventCallbackNative>>',
};

/// Dart-side aliases `gbm_bindings.dart` declares for `Pointer<Void>`.
const Map<String, String> _dartAliases = <String, String>{
  'GbmSessionHandle': 'Pointer<Void>',
  'GbmDiscoveryHandle': 'Pointer<Void>',
};

/// Declared in the header, deliberately not bound in Dart. Binding one of
/// these means deleting it here too -- the coverage test checks both ways.
const Set<String> _unboundByDecision = <String>{
  // [DRIFT-cancel-capi-unwired], #139: capi landed, Dart deliberately unwired.
  'gbm_cancel_operation',
};

class _Signature {
  const _Signature(this.ret, this.params);
  final String ret;
  final List<String> params;
}

/// Runs at declaration time, outside any test, so it throws instead of
/// calling `expect` (which needs a running test).
String _read(String path) {
  final File file = File(path);
  if (!file.existsSync()) {
    throw StateError(
      '$path must be readable from the package root so this test can '
      'compare against the real source. If the layout moved, fix the path.',
    );
  }
  return file.readAsStringSync();
}

String _stripCComments(String source) => source
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

String _collapse(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

/// `const char * const * paths` -> `const char* const*`, by matching the
/// longest known type the parameter starts with and requiring the rest to be
/// nothing or a parameter name.
String _cParamType(String symbol, String param) {
  final String p = _collapse(param).replaceAll(RegExp(r'\s*\*'), '*');
  final List<String> known = _cToFfi.keys.toList()
    ..sort((String a, String b) => b.length.compareTo(a.length));
  for (final String type in known) {
    if (!p.startsWith(type)) continue;
    final String rest = p.substring(type.length);
    if (rest.isEmpty || RegExp(r'^ ?[A-Za-z_]\w*$').hasMatch(rest)) {
      if (!type.endsWith('*') && rest.isNotEmpty && !rest.startsWith(' ')) {
        continue;
      }
      return type;
    }
  }
  fail('$symbol: C parameter `$param` has a type missing from _cToFfi.');
}

String _ffiOf(String symbol, String cType) {
  final String? ffi = _cToFfi[cType];
  if (ffi == null) {
    fail('$symbol: C type `$cType` is missing from _cToFfi.');
  }
  return ffi;
}

/// Splits on commas outside `<...>`, so `Pointer<NativeFunction<X>>` stays
/// one parameter.
List<String> _splitTopLevel(String params) {
  final List<String> out = <String>[];
  final StringBuffer current = StringBuffer();
  int depth = 0;
  for (final String ch in params.split('')) {
    if (ch == '<') depth++;
    if (ch == '>') depth--;
    if (ch == ',' && depth == 0) {
      out.add(current.toString());
      current.clear();
    } else {
      current.write(ch);
    }
  }
  out.add(current.toString());
  return out.map(_collapse).where((String s) => s.isNotEmpty).toList();
}

/// `GBM_API <ret> gbm_xxx(<params>);`, mapped to FFI type names.
Map<String, _Signature> _parseHeader(String header) {
  final RegExp decl = RegExp(
    r'GBM_API\s+([^;#(]*?)\b(gbm_\w+)\s*\(([^)]*)\)\s*;',
  );
  final Map<String, _Signature> out = <String, _Signature>{};
  for (final RegExpMatch m in decl.allMatches(header)) {
    final String symbol = m.group(2)!;
    final String ret = _collapse(m.group(1)!).replaceAll(RegExp(r'\s*\*'), '*');
    final List<String> raw = _splitTopLevel(m.group(3)!);
    final List<String> params = raw.length == 1 && raw.single == 'void'
        ? <String>[]
        : raw
              .map((String p) => _ffiOf(symbol, _cParamType(symbol, p)))
              .toList();
    expect(out.containsKey(symbol), isFalse, reason: '$symbol declared twice');
    out[symbol] = _Signature(_ffiOf(symbol, ret), params);
  }
  return out;
}

/// `Pointer<Uint8> payload` -> `Pointer<Uint8>`; aliases resolved.
String _dartParamType(String param) {
  final String type = _collapse(param).replaceFirst(RegExp(r' \w+$'), '');
  return _dartAliases[type] ?? type;
}

/// `typedef Name = Ret Function(params);` for every native typedef.
Map<String, _Signature> _parseNativeTypedefs(String bindings) {
  final RegExp typedefRe = RegExp(
    r'typedef\s+(\w+)\s*=\s*([^=;]+?)\s+Function\(([^;]*?)\)\s*;',
  );
  final Map<String, _Signature> out = <String, _Signature>{};
  for (final RegExpMatch m in typedefRe.allMatches(bindings)) {
    final String ret = _collapse(m.group(2)!);
    out[m.group(1)!] = _Signature(
      _dartAliases[ret] ?? ret,
      _splitTopLevel(m.group(3)!).map(_dartParamType).toList(),
    );
  }
  return out;
}

/// `lookupFunction<_XxxNative, XxxDart>('gbm_xxx')` -> (symbol, native name),
/// in source order; duplicates are kept so a test can report them.
List<(String, String)> _parseLookups(String bindings) {
  final RegExp lookup = RegExp(
    r"lookupFunction<\s*(\w+)\s*,\s*\w+\s*>\(\s*'(gbm_\w+)'",
  );
  return <(String, String)>[
    for (final RegExpMatch m in lookup.allMatches(bindings))
      (m.group(2)!, m.group(1)!),
  ];
}

void main() {
  final String header = _stripCComments(_read('../src/capi/gbm_capi.h'));
  final String bindings = _read('lib/data/ffi/gbm_bindings.dart');

  // `late`: parsing the header calls `fail` on an unknown type, which only
  // works inside a running test.
  late final Map<String, _Signature> cFunctions = _parseHeader(header);
  final Map<String, _Signature> nativeTypedefs = _parseNativeTypedefs(bindings);
  final List<(String, String)> lookups = _parseLookups(bindings);
  final Set<String> boundSymbols = <String>{
    for (final (String symbol, String _) in lookups) symbol,
  };

  test('the parsers see every declaration and every lookup', () {
    // A parser that silently skips a shape it does not understand would make
    // every per-binding test below pass vacuously for that function.
    final int apiCount =
        RegExp(r'GBM_API\s').allMatches(header).length -
        RegExp(r'#define\s+GBM_API\s').allMatches(header).length;
    expect(cFunctions.length, apiCount);
    expect(lookups.length, 'lookupFunction<'.allMatches(bindings).length);
    expect(boundSymbols.length, lookups.length, reason: 'a symbol bound twice');
  });

  test('every header function is bound, except the recorded exceptions', () {
    final Set<String> unbound = cFunctions.keys.toSet().difference(
      boundSymbols,
    );
    expect(unbound, _unboundByDecision);
  });

  test('GbmEventCallbackNative matches the GbmEventCallback typedef', () {
    final RegExpMatch? m = RegExp(
      r'typedef\s+(\w[\w\s*]*?)\s*\(\s*\*\s*GbmEventCallback\s*\)\s*\(([^)]*)\)\s*;',
    ).firstMatch(header);
    expect(m, isNotNull, reason: 'GbmEventCallback typedef not found');
    const String symbol = 'GbmEventCallback';
    final String ret = _ffiOf(symbol, _collapse(m!.group(1)!));
    final List<String> params = _splitTopLevel(m.group(2)!)
        .map((String p) => _ffiOf(symbol, _cParamType(symbol, p)))
        .toList();
    final _Signature? dart = nativeTypedefs['GbmEventCallbackNative'];
    expect(dart, isNotNull, reason: 'GbmEventCallbackNative not found');
    expect(dart!.ret, ret);
    expect(dart.params, params);
  });

  group('each lookupFunction matches its gbm_capi.h declaration', () {
    for (final (String symbol, String nativeName) in lookups) {
      test(symbol, () {
        final _Signature? c = cFunctions[symbol];
        expect(c, isNotNull, reason: '$symbol is not declared in gbm_capi.h');
        final _Signature? dart = nativeTypedefs[nativeName];
        expect(dart, isNotNull, reason: '$nativeName typedef not found');
        expect(
          dart!.params.length,
          c!.params.length,
          reason: '$symbol: $nativeName parameter count',
        );
        expect(dart.ret, c.ret, reason: '$symbol: $nativeName return type');
        for (int i = 0; i < c.params.length; i++) {
          expect(
            dart.params[i],
            c.params[i],
            reason: '$symbol: $nativeName parameter ${i + 1}',
          );
        }
      });
    }
  });
}
