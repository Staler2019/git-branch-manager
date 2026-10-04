// `dart:ffi`'s `lookupFunction` matches by symbol name only, never by
// signature ([TEST-ffi-matches-symbol-only]). A `_XxxNative` typedef that has
// drifted from its `gbm_capi.h` prototype -- one parameter short, a wrong
// type -- analyzes and unit-tests clean, then corrupts the stack at runtime.
// This test reads both source files and compares them, so the drift is red on
// every PR instead of only on a device-tier run.
//
// Known limits:
// - Two parameters of the same type swapped (`rebaseMerges` <-> `autosquash`
//   in `gbm_rebase_start`) are invisible here: the types still line up. Only a
//   device-tier test that observes the behaviour can see that.
// - The `XxxDart` typedefs are not compared: `lookupFunction<N, D>` already
//   ties D to N at compile time; what it never checks is N against the C side.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every C type `gbm_capi.h` uses, and the FFI native type it must be bound
/// as. A type missing here fails the test rather than being skipped -- add the
/// row deliberately when the header gains one.
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

/// Header functions with no Dart binding, each by decision. Must match the
/// header-minus-bindings set exactly, so wiring one up without removing it
/// here is red too.
const Set<String> _unboundAllowlist = <String>{
  // #139, [DRIFT-cancel-capi-unwired]: capi landed, Dart deliberately unwired.
  'gbm_cancel_operation',
};

class _Signature {
  const _Signature(this.returnType, this.params);

  final String returnType;
  final List<String> params;

  @override
  String toString() => '$returnType(${params.join(', ')})';
}

String _read(String path) {
  final File file = File(path);
  expect(
    file.existsSync(),
    isTrue,
    reason:
        '$path must be readable from the package root so this test compares '
        'the real sources. If the layout moved, fix the path -- do not skip.',
  );
  return file.readAsStringSync();
}

String _collapse(String s) =>
    s.replaceAll(RegExp(r'\s+'), ' ').replaceAll(RegExp(r'\s*\*'), '*').trim();

/// Splits a C parameter list into types, dropping each parameter's name.
List<String> _cParamTypes(String raw) {
  final String list = _collapse(raw);
  if (list.isEmpty || list == 'void') return const <String>[];
  return list.split(',').map((String p) {
    final RegExpMatch m = RegExp(r'^(.*?)\s*\b\w+$').firstMatch(p.trim())!;
    return _collapse(m.group(1)!);
  }).toList();
}

/// Splits a Dart `Function(...)` parameter list into types, dropping names.
List<String> _dartParamTypes(String raw) {
  final String list = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (list.isEmpty) return const <String>[];
  return list
      .split(',')
      .map((String p) => p.trim())
      .where((String p) => p.isNotEmpty)
      .map((String p) => p.replaceFirst(RegExp(r'\s+\w+$'), ''))
      .toList();
}

String _stripLineComments(String s) => s.replaceAll(RegExp(r'//[^\n]*'), '');

Map<String, _Signature> _headerFunctions(String header) {
  final Map<String, _Signature> out = <String, _Signature>{};
  for (final RegExpMatch m in RegExp(
    r'GBM_API\s+([^;]+?)\b(gbm_\w+)\s*\(([^)]*)\)\s*;',
  ).allMatches(header)) {
    out[m.group(2)!] = _Signature(
      _collapse(m.group(1)!),
      _cParamTypes(m.group(3)!),
    );
  }
  return out;
}

_Signature _headerCallback(String header) {
  final RegExpMatch m = RegExp(
    r'typedef\s+(\w+)\s*\(\s*\*\s*GbmEventCallback\s*\)\s*\(([^)]*)\)\s*;',
  ).firstMatch(header)!;
  return _Signature(_collapse(m.group(1)!), _cParamTypes(m.group(2)!));
}

Map<String, _Signature> _dartNativeTypedefs(String bindings) {
  final Map<String, _Signature> out = <String, _Signature>{};
  for (final RegExpMatch m in RegExp(
    r'typedef\s+(_\w+Native|GbmEventCallbackNative)\s*=\s*(.+?)\s+Function\s*\((.*?)\)\s*;',
    dotAll: true,
  ).allMatches(bindings)) {
    out[m.group(1)!] = _Signature(
      m.group(2)!.trim(),
      _dartParamTypes(m.group(3)!),
    );
  }
  return out;
}

/// symbol -> `_XxxNative` typedef name, from every `lookupFunction` call.
Map<String, String> _dartLookups(String bindings) {
  final Map<String, String> out = <String, String>{};
  for (final RegExpMatch m in RegExp(
    r"lookupFunction\s*<\s*(_\w+Native)\s*,\s*\w+\s*,?\s*>\s*\(\s*'(gbm_\w+)'",
  ).allMatches(bindings)) {
    out[m.group(2)!] = m.group(1)!;
  }
  return out;
}

/// Type mismatches between a C signature and an FFI one of the same arity;
/// empty if equal. Arity is its own test, so a dropped parameter reddens that
/// one test instead of also cascading into every later position here.
List<String> _compareTypes(String label, _Signature c, _Signature dart) {
  String expectFfi(String cType) =>
      _cToFfi[cType] ?? '<C type "$cType" missing from _cToFfi>';
  final String ret = expectFfi(c.returnType);
  return <String>[
    if (ret != dart.returnType)
      '$label: return expected $ret, Dart has ${dart.returnType}',
    for (int i = 0; i < c.params.length; i++)
      if (expectFfi(c.params[i]) != dart.params[i])
        '$label: param $i expected ${expectFfi(c.params[i])} '
            '(C ${c.params[i]}), Dart has ${dart.params[i]}',
  ];
}

void main() {
  late String header;
  late String bindings;
  late Map<String, _Signature> cFns;
  late Map<String, _Signature> natives;
  late Map<String, String> lookups;

  setUpAll(() {
    header = _stripLineComments(_read('../src/capi/gbm_capi.h'));
    bindings = _stripLineComments(_read('lib/data/ffi/gbm_bindings.dart'));
    cFns = _headerFunctions(header);
    natives = _dartNativeTypedefs(bindings);
    lookups = _dartLookups(bindings);
  });

  test('both sources parse, and every lookup names a known typedef', () {
    expect(cFns, isNotEmpty, reason: 'no GBM_API prototype parsed');
    expect(lookups, isNotEmpty, reason: 'no lookupFunction call parsed');
    expect(
      header.split('GBM_API').length - 1 - 2,
      cFns.length,
      reason: 'every GBM_API prototype (minus the two #define lines) parsed',
    );
    expect(
      RegExp(r'lookupFunction\s*<').allMatches(bindings).length,
      lookups.length,
      reason: 'every lookupFunction call parsed, and no symbol bound twice',
    );
    final List<String> unknown = <String>[
      for (final MapEntry<String, String> e in lookups.entries)
        if (!natives.containsKey(e.value)) '${e.key} -> ${e.value}',
    ];
    expect(unknown, isEmpty, reason: 'lookups whose typedef was not parsed');
  });

  test('every bound symbol is declared in gbm_capi.h', () {
    final List<String> missing = <String>[
      for (final String symbol in lookups.keys)
        if (!cFns.containsKey(symbol)) symbol,
    ];
    expect(missing, isEmpty);
  });

  test('every binding has the same parameter count as its prototype', () {
    final List<String> problems = <String>[
      for (final MapEntry<String, String> e in lookups.entries)
        if (cFns[e.key] != null &&
            natives[e.value] != null &&
            cFns[e.key]!.params.length != natives[e.value]!.params.length)
          '${e.key} (${e.value}): C ${cFns[e.key]}, Dart ${natives[e.value]}',
    ];
    expect(problems, isEmpty);
  });

  test('every binding matches its prototype type by type', () {
    final List<String> problems = <String>[
      for (final MapEntry<String, String> e in lookups.entries)
        if (cFns[e.key] != null &&
            natives[e.value] != null &&
            cFns[e.key]!.params.length == natives[e.value]!.params.length)
          ..._compareTypes(
            '${e.key} (${e.value})',
            cFns[e.key]!,
            natives[e.value]!,
          ),
    ];
    expect(problems, isEmpty);
  });

  test('unbound header functions are exactly the allowlist', () {
    final Set<String> unbound = cFns.keys.toSet().difference(
      lookups.keys.toSet(),
    );
    expect(
      unbound,
      _unboundAllowlist,
      reason:
          'a new GBM_API function needs a binding (or an allowlist entry by '
          'decision); a newly bound one must leave the allowlist',
    );
  });

  test('GbmEventCallbackNative matches GbmEventCallback', () {
    expect(natives.containsKey('GbmEventCallbackNative'), isTrue);
    final _Signature c = _headerCallback(header);
    final _Signature dart = natives['GbmEventCallbackNative']!;
    expect(dart.params.length, c.params.length, reason: 'C $c, Dart $dart');
    expect(_compareTypes('GbmEventCallback', c, dart), isEmpty);
  });
}
