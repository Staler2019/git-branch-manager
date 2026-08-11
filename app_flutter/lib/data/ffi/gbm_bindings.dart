import 'dart:ffi';

import 'package:ffi/ffi.dart' show Utf8;

import 'native_library.dart';

// Hand-written bindings mirroring src/capi/gbm_capi.h function-for-function.
// The plan calls for ffigen-generated bindings once the FFI surface
// stabilizes; gbm_capi.h is still small and changing during M0/M1, so a
// hand-written binding (kept in the same order as the header, one typedef
// pair per function) is easier to keep in sync by inspection for now. Revisit
// with ffigen once src/capi/*.cpp covers more than history/graph/branches/
// discovery -- see the plan's milestone roadmap.

typedef GbmSessionHandle = Pointer<Void>;
typedef GbmDiscoveryHandle = Pointer<Void>;

/// Matches `enum GbmEventType` in gbm_capi.h.
abstract final class GbmEventType {
  static const int graphUpdated = 0;
  static const int refsUpdated = 1;
  static const int errorOccurred = 2;
  static const int operationFinished = 3;
}

/// `void (*)(GbmSessionHandle, int32_t, const uint8_t*, int32_t, void*)`.
typedef GbmEventCallbackNative =
    Void Function(
      Pointer<Void> session,
      Int32 eventType,
      Pointer<Uint8> payload,
      Int32 payloadLen,
      Pointer<Void> userData,
    );

typedef _FreeEventPayloadNative = Void Function(Pointer<Uint8> payload);
typedef FreeEventPayloadDart = void Function(Pointer<Uint8> payload);

typedef _LastResultJsonLenNative = Int32 Function();
typedef LastResultJsonLenDart = int Function();

typedef _LastResultJsonCopyNative = Void Function(Pointer<Uint8> out, Int32 outLen);
typedef LastResultJsonCopyDart = void Function(Pointer<Uint8> out, int outLen);

typedef _SessionOpenNative =
    Pointer<Void> Function(Pointer<Utf8> workDir, Pointer<Utf8> gitDir, Pointer<Utf8> commonDir);
typedef SessionOpenDart =
    Pointer<Void> Function(Pointer<Utf8> workDir, Pointer<Utf8> gitDir, Pointer<Utf8> commonDir);

typedef _SessionCloseNative = Void Function(Pointer<Void> session);
typedef SessionCloseDart = void Function(Pointer<Void> session);

typedef _RegisterCallbackNative =
    Void Function(Pointer<Void> session, Pointer<NativeFunction<GbmEventCallbackNative>> callback, Pointer<Void> userData);
typedef RegisterCallbackDart =
    void Function(Pointer<Void> session, Pointer<NativeFunction<GbmEventCallbackNative>> callback, Pointer<Void> userData);

typedef _RepoStateJsonNative = Int32 Function(Pointer<Void> session);
typedef RepoStateJsonDart = int Function(Pointer<Void> session);

typedef _HistoryRefreshNative = Void Function(Pointer<Void> session);
typedef HistoryRefreshDart = void Function(Pointer<Void> session);

typedef _RefsJsonNative = Int32 Function(Pointer<Void> session);
typedef RefsJsonDart = int Function(Pointer<Void> session);

typedef _GraphRowsNative = Pointer<Uint8> Function(Pointer<Void> session, Pointer<Int32> rowCount, Pointer<Int32> rowStride);
typedef GraphRowsDart = Pointer<Uint8> Function(Pointer<Void> session, Pointer<Int32> rowCount, Pointer<Int32> rowStride);

typedef _GraphOidsNative = Pointer<Uint8> Function(Pointer<Void> session, Pointer<Int32> oidCount, Pointer<Int32> oidStride);
typedef GraphOidsDart = Pointer<Uint8> Function(Pointer<Void> session, Pointer<Int32> oidCount, Pointer<Int32> oidStride);

typedef _GraphParentsNative = Pointer<Uint32> Function(Pointer<Void> session, Pointer<Int32> parentCount);
typedef GraphParentsDart = Pointer<Uint32> Function(Pointer<Void> session, Pointer<Int32> parentCount);

typedef _GraphEdgesNative = Pointer<Uint8> Function(Pointer<Void> session, Pointer<Int32> edgeCount, Pointer<Int32> edgeStride);
typedef GraphEdgesDart = Pointer<Uint8> Function(Pointer<Void> session, Pointer<Int32> edgeCount, Pointer<Int32> edgeStride);

typedef _GraphIntQueryNative = Int32 Function(Pointer<Void> session);
typedef GraphIntQueryDart = int Function(Pointer<Void> session);

typedef _GraphReleaseNative = Void Function(Pointer<Void> session);
typedef GraphReleaseDart = void Function(Pointer<Void> session);

typedef _BranchCheckoutNative =
    Void Function(
      Pointer<Void> session,
      Pointer<Utf8> target,
      Int32 detach,
      Int32 createBranch,
      Pointer<Utf8> newBranchName,
      Int32 force,
      Int32 stashFirst,
      Int32 recurseSubmodules,
    );
typedef BranchCheckoutDart =
    void Function(
      Pointer<Void> session,
      Pointer<Utf8> target,
      int detach,
      int createBranch,
      Pointer<Utf8> newBranchName,
      int force,
      int stashFirst,
      int recurseSubmodules,
    );

typedef _DiscoveryOpenNative = Pointer<Void> Function(Pointer<Utf8> dbPath);
typedef DiscoveryOpenDart = Pointer<Void> Function(Pointer<Utf8> dbPath);

typedef _DiscoveryCloseNative = Void Function(Pointer<Void> discovery);
typedef DiscoveryCloseDart = void Function(Pointer<Void> discovery);

typedef _DiscoveryAddBaseFolderNative =
    Int64 Function(Pointer<Void> discovery, Pointer<Utf8> path, Int32 maxDepth, Int32 followLinks);
typedef DiscoveryAddBaseFolderDart =
    int Function(Pointer<Void> discovery, Pointer<Utf8> path, int maxDepth, int followLinks);

typedef _DiscoveryScanAllNative = Int32 Function(Pointer<Void> discovery);
typedef DiscoveryScanAllDart = int Function(Pointer<Void> discovery);

typedef _DiscoveryListReposJsonNative = Int32 Function(Pointer<Void> discovery);
typedef DiscoveryListReposJsonDart = int Function(Pointer<Void> discovery);


/// Thin, allocation-free wrapper around the `gbm_capi` symbol table. One
/// instance per isolate is enough; construct it once via [GbmBindings.open]
/// and share it through a Riverpod provider.
class GbmBindings {
  /// Resolves the native library (see [openGbmCapiLibrary]) and looks up
  /// every symbol.
  factory GbmBindings.open() => GbmBindings(openGbmCapiLibrary());

  GbmBindings(DynamicLibrary library)
    : freeEventPayload = library.lookupFunction<_FreeEventPayloadNative, FreeEventPayloadDart>(
        'gbm_free_event_payload',
      ),
      lastResultJsonLen = library.lookupFunction<_LastResultJsonLenNative, LastResultJsonLenDart>(
        'gbm_last_result_json_len',
      ),
      lastResultJsonCopy = library.lookupFunction<_LastResultJsonCopyNative, LastResultJsonCopyDart>(
        'gbm_last_result_json_copy',
      ),
      sessionOpen = library.lookupFunction<_SessionOpenNative, SessionOpenDart>('gbm_session_open'),
      sessionClose = library.lookupFunction<_SessionCloseNative, SessionCloseDart>('gbm_session_close'),
      registerCallback = library.lookupFunction<_RegisterCallbackNative, RegisterCallbackDart>(
        'gbm_register_callback',
      ),
      repoStateJson = library.lookupFunction<_RepoStateJsonNative, RepoStateJsonDart>('gbm_repo_state_json'),
      historyRefresh = library.lookupFunction<_HistoryRefreshNative, HistoryRefreshDart>('gbm_history_refresh'),
      refsJson = library.lookupFunction<_RefsJsonNative, RefsJsonDart>('gbm_refs_json'),
      graphSnapshotRows = library.lookupFunction<_GraphRowsNative, GraphRowsDart>('gbm_graph_snapshot_rows'),
      graphSnapshotOids = library.lookupFunction<_GraphOidsNative, GraphOidsDart>('gbm_graph_snapshot_oids'),
      graphSnapshotParents = library.lookupFunction<_GraphParentsNative, GraphParentsDart>(
        'gbm_graph_snapshot_parents',
      ),
      graphSnapshotEdges = library.lookupFunction<_GraphEdgesNative, GraphEdgesDart>('gbm_graph_snapshot_edges'),
      graphSnapshotLaneCount = library.lookupFunction<_GraphIntQueryNative, GraphIntQueryDart>(
        'gbm_graph_snapshot_lane_count',
      ),
      graphSnapshotComplete = library.lookupFunction<_GraphIntQueryNative, GraphIntQueryDart>(
        'gbm_graph_snapshot_complete',
      ),
      graphSnapshotTruncated = library.lookupFunction<_GraphIntQueryNative, GraphIntQueryDart>(
        'gbm_graph_snapshot_truncated',
      ),
      graphSnapshotRelease = library.lookupFunction<_GraphReleaseNative, GraphReleaseDart>(
        'gbm_graph_snapshot_release',
      ),
      branchCheckout = library.lookupFunction<_BranchCheckoutNative, BranchCheckoutDart>('gbm_branch_checkout'),
      discoveryOpen = library.lookupFunction<_DiscoveryOpenNative, DiscoveryOpenDart>('gbm_discovery_open'),
      discoveryClose = library.lookupFunction<_DiscoveryCloseNative, DiscoveryCloseDart>('gbm_discovery_close'),
      discoveryAddBaseFolder = library
          .lookupFunction<_DiscoveryAddBaseFolderNative, DiscoveryAddBaseFolderDart>('gbm_discovery_add_base_folder'),
      discoveryScanAll = library.lookupFunction<_DiscoveryScanAllNative, DiscoveryScanAllDart>(
        'gbm_discovery_scan_all',
      ),
      discoveryListReposJson = library
          .lookupFunction<_DiscoveryListReposJsonNative, DiscoveryListReposJsonDart>('gbm_discovery_list_repos_json');

  final FreeEventPayloadDart freeEventPayload;
  final LastResultJsonLenDart lastResultJsonLen;
  final LastResultJsonCopyDart lastResultJsonCopy;
  final SessionOpenDart sessionOpen;
  final SessionCloseDart sessionClose;
  final RegisterCallbackDart registerCallback;
  final RepoStateJsonDart repoStateJson;
  final HistoryRefreshDart historyRefresh;
  final RefsJsonDart refsJson;
  final GraphRowsDart graphSnapshotRows;
  final GraphOidsDart graphSnapshotOids;
  final GraphParentsDart graphSnapshotParents;
  final GraphEdgesDart graphSnapshotEdges;
  final GraphIntQueryDart graphSnapshotLaneCount;
  final GraphIntQueryDart graphSnapshotComplete;
  final GraphIntQueryDart graphSnapshotTruncated;
  final GraphReleaseDart graphSnapshotRelease;
  final BranchCheckoutDart branchCheckout;
  final DiscoveryOpenDart discoveryOpen;
  final DiscoveryCloseDart discoveryClose;
  final DiscoveryAddBaseFolderDart discoveryAddBaseFolder;
  final DiscoveryScanAllDart discoveryScanAll;
  final DiscoveryListReposJsonDart discoveryListReposJson;
}
