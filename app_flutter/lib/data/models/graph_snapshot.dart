import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart' show malloc;

import '../ffi/gbm_bindings.dart';

/// Row-index sentinel for "parent lies outside the walk" -- mirrors
/// `gbm::kRowBoundary` (src/core/graph/GraphSnapshot.h).
const int kRowBoundary = 0xFFFFFFFF;

/// One decoded `gbm::RowMeta` (src/core/graph/GraphSnapshot.h) -- the exact
/// 16-byte layout `gbm_graph_snapshot_rows()` exposes, read field-by-field
/// rather than reinterpreted as a struct since Dart has no packed-struct FFI
/// view for this without `Struct` boilerplate the fixed row stride already
/// makes unnecessary.
class GraphRow {
  const GraphRow({
    required this.parentOffset,
    required this.edgeOffset,
    required this.commitTime,
    required this.lane,
    required this.color,
    required this.flags,
  });

  final int parentOffset;
  final int edgeOffset;
  final int commitTime;
  final int lane;
  final int color;
  final int flags;

  /// Saturates at 7 ("7 or more") -- see RowMeta::parentCount()'s doc
  /// comment. Fine for the M1 graph render; an exact count for octopus
  /// merges needs the parentOffset-gap trick GraphSnapshot::parentCountOf()
  /// uses, not yet exposed over FFI.
  int get parentCount => flags & 0x07;
  bool get isMerge => (flags & 0x08) != 0;
  bool get hasRefs => (flags & 0x10) != 0;
  bool get isHead => (flags & 0x20) != 0;
  bool get isBoundary => (flags & 0x40) != 0;
  bool get isOverflow => (flags & 0x80) != 0;
}

/// A fully-decoded snapshot of the commit graph, copied out of the native
/// buffers into plain Dart collections. Not zero-copy (see the plan's note
/// on this being a deliberate M1 simplification, revisited if profiling
/// shows it matters) -- safe to hold onto after the native pin is released.
class GraphSnapshotView {
  const GraphSnapshotView({
    required this.rows,
    required this.oidsHex,
    required this.parentPool,
    required this.laneCount,
    required this.complete,
    required this.truncated,
  });

  static const GraphSnapshotView empty = GraphSnapshotView(
    rows: <GraphRow>[],
    oidsHex: <String>[],
    parentPool: <int>[],
    laneCount: 0,
    complete: false,
    truncated: false,
  );

  final List<GraphRow> rows;
  final List<String> oidsHex;
  final List<int> parentPool;
  final int laneCount;
  final bool complete;
  final bool truncated;

  /// Parent commit hashes of `rows[rowIndex]`, in row order. A parent
  /// outside the walk ([kRowBoundary]) is omitted.
  List<String> parentsOf(int rowIndex) {
    final GraphRow row = rows[rowIndex];
    return <String>[
      for (int i = 0; i < row.parentCount; i++)
        if (parentPool[row.parentOffset + i] != kRowBoundary) oidsHex[parentPool[row.parentOffset + i]],
    ];
  }
}

/// Reads the current graph snapshot for `session` through [bindings],
/// copying it into a [GraphSnapshotView] and releasing the native pin
/// before returning. Returns [GraphSnapshotView.empty] if no snapshot has
/// been published yet (i.e. before the first `gbm_history_refresh()`
/// completes).
GraphSnapshotView readGraphSnapshot(GbmBindings bindings, Pointer<Void> session) {
  final Pointer<Int32> countOut = malloc<Int32>();
  final Pointer<Int32> strideOut = malloc<Int32>();
  try {
    final Pointer<Uint8> rowsPtr = bindings.graphSnapshotRows(session, countOut, strideOut);
    final int rowCount = countOut.value;
    if (rowsPtr == nullptr || rowCount == 0) {
      bindings.graphSnapshotRelease(session);
      return GraphSnapshotView.empty;
    }
    final int rowStride = strideOut.value;
    final ByteData rowData = ByteData.sublistView(rowsPtr.asTypedList(rowCount * rowStride));
    final List<GraphRow> rows = List<GraphRow>.generate(rowCount, (int i) {
      final int base = i * rowStride;
      return GraphRow(
        parentOffset: rowData.getUint32(base, Endian.little),
        edgeOffset: rowData.getUint32(base + 4, Endian.little),
        commitTime: rowData.getUint32(base + 8, Endian.little),
        lane: rowData.getUint16(base + 12, Endian.little),
        color: rowData.getUint8(base + 14),
        flags: rowData.getUint8(base + 15),
      );
    }, growable: false);

    final List<String> oidsHex = _readOids(bindings, session, rowCount);
    final List<int> parentPool = _readParents(bindings, session);

    final int laneCount = bindings.graphSnapshotLaneCount(session);
    final bool complete = bindings.graphSnapshotComplete(session) != 0;
    final bool truncated = bindings.graphSnapshotTruncated(session) != 0;

    bindings.graphSnapshotRelease(session);

    return GraphSnapshotView(
      rows: rows,
      oidsHex: oidsHex,
      parentPool: parentPool,
      laneCount: laneCount,
      complete: complete,
      truncated: truncated,
    );
  } finally {
    malloc.free(countOut);
    malloc.free(strideOut);
  }
}

List<String> _readOids(GbmBindings bindings, Pointer<Void> session, int expectedCount) {
  final Pointer<Int32> countOut = malloc<Int32>();
  final Pointer<Int32> strideOut = malloc<Int32>();
  try {
    final Pointer<Uint8> oidsPtr = bindings.graphSnapshotOids(session, countOut, strideOut);
    final int count = countOut.value;
    if (oidsPtr == nullptr || count == 0) {
      return List<String>.filled(expectedCount, '');
    }
    final int stride = strideOut.value;
    final Uint8List bytes = oidsPtr.asTypedList(count * stride);
    return List<String>.generate(count, (int i) {
      final int base = i * stride;
      final int length = bytes[base + 32]; // ObjectId's trailing length_ byte.
      final StringBuffer hex = StringBuffer();
      for (int b = 0; b < length; b++) {
        hex.write(bytes[base + b].toRadixString(16).padLeft(2, '0'));
      }
      return hex.toString();
    }, growable: false);
  } finally {
    malloc.free(countOut);
    malloc.free(strideOut);
  }
}

List<int> _readParents(GbmBindings bindings, Pointer<Void> session) {
  final Pointer<Int32> countOut = malloc<Int32>();
  try {
    final Pointer<Uint32> parentsPtr = bindings.graphSnapshotParents(session, countOut);
    final int count = countOut.value;
    if (parentsPtr == nullptr || count == 0) {
      return const <int>[];
    }
    return Uint32List.fromList(parentsPtr.asTypedList(count));
  } finally {
    malloc.free(countOut);
  }
}
