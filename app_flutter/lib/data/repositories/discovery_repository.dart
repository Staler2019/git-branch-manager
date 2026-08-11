import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../ffi/gbm_bindings.dart';
import '../ffi/json_codec.dart';
import '../models/base_folder_record.dart';
import '../models/git_error.dart';
import '../models/repo_record.dart';
import 'gbm_bindings_provider.dart';

class DiscoveryState {
  const DiscoveryState({
    this.isOpen = false,
    this.repos = const <RepoRecord>[],
    this.baseFolders = const <BaseFolderRecord>[],
    this.isScanning = false,
    this.lastError,
  });

  final bool isOpen;
  final List<RepoRecord> repos;
  final List<BaseFolderRecord> baseFolders;
  final bool isScanning;
  final GitError? lastError;

  DiscoveryState copyWith({
    bool? isOpen,
    List<RepoRecord>? repos,
    List<BaseFolderRecord>? baseFolders,
    bool? isScanning,
    GitError? lastError,
    bool clearError = false,
  }) {
    return DiscoveryState(
      isOpen: isOpen ?? this.isOpen,
      repos: repos ?? this.repos,
      baseFolders: baseFolders ?? this.baseFolders,
      isScanning: isScanning ?? this.isScanning,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }
}

/// Owns the repo-index database (`gbm_discovery_*`, backed by
/// `RepoIndexDb`/SQLite -- see src/core/cache/RepoIndexDb.h) for the whole
/// app: one discovery handle, opened once at startup and reused across every
/// base-folder scan.
///
/// `gbm_discovery_scan_all()` blocks the calling thread (see its doc comment
/// in gbm_capi.h); this controller calls it directly on the UI isolate for
/// now, which is a known M1 simplification -- fine for scanning one modest
/// folder in a dev/demo setting, but a base folder with many thousands of
/// subdirectories would visibly stall the UI. Moving the call to a
/// background isolate needs the native handle's address threaded across the
/// isolate boundary (`Pointer.address` / `Pointer.fromAddress`), which is
/// deferred to a later milestone rather than risked here.
class DiscoveryController extends StateNotifier<DiscoveryState> {
  DiscoveryController(this._bindings) : super(const DiscoveryState()) {
    unawaited(_open());
  }

  final GbmBindings _bindings;
  Pointer<Void> _discovery = nullptr;

  Future<void> _open() async {
    final Directory supportDir = await getApplicationSupportDirectory();
    final String dbPath = '${supportDir.path}${Platform.pathSeparator}discovery.sqlite3';
    final Pointer<Utf8> pathPtr = dbPath.toNativeUtf8();
    try {
      _discovery = _bindings.discoveryOpen(pathPtr);
    } finally {
      malloc.free(pathPtr);
    }

    if (_discovery == nullptr) {
      state = state.copyWith(lastError: _decodeLastError());
      return;
    }
    state = state.copyWith(isOpen: true);
    _listRepos();
    _listBaseFolders();
  }

  void _listRepos() {
    if (_bindings.discoveryListReposJson(_discovery) == 0) {
      final String json = readLastResultJson(_bindings);
      final List<dynamic> decoded = json.isEmpty ? const <dynamic>[] : jsonDecode(json) as List<dynamic>;
      state = state.copyWith(repos: RepoRecord.listFromJson(decoded));
    }
  }

  void _listBaseFolders() {
    if (_bindings.discoveryBaseFoldersJson(_discovery) == 0) {
      final String json = readLastResultJson(_bindings);
      final List<dynamic> decoded = json.isEmpty ? const <dynamic>[] : jsonDecode(json) as List<dynamic>;
      state = state.copyWith(baseFolders: BaseFolderRecord.listFromJson(decoded));
    }
  }

  GitError? _decodeLastError() {
    final String json = readLastResultJson(_bindings);
    return json.isEmpty ? null : GitError.fromJson(jsonDecode(json) as Map<String, dynamic>);
  }

  /// Registers `path` as a base folder and scans it immediately. See the
  /// class doc comment for the synchronous-scan caveat.
  void addBaseFolderAndScan(String path) {
    if (_discovery == nullptr) return;
    state = state.copyWith(isScanning: true, clearError: true);

    final Pointer<Utf8> pathPtr = path.toNativeUtf8();
    final int folderId;
    try {
      folderId = _bindings.discoveryAddBaseFolder(_discovery, pathPtr, 3, 0);
    } finally {
      malloc.free(pathPtr);
    }
    if (folderId < 0) {
      state = state.copyWith(isScanning: false, lastError: _decodeLastError());
      return;
    }

    rescan();
  }

  void rescan() {
    if (_discovery == nullptr) return;
    state = state.copyWith(isScanning: true, clearError: true);
    final int result = _bindings.discoveryScanAll(_discovery);
    if (result != 0) {
      state = state.copyWith(isScanning: false, lastError: _decodeLastError());
      return;
    }
    _listRepos();
    _listBaseFolders();
    state = state.copyWith(isScanning: false);
  }

  /// Enables/disables a base folder without removing it. See
  /// gbm_discovery_set_base_folder_enabled()'s doc comment in gbm_capi.h.
  void setBaseFolderEnabled(int baseFolderId, bool enabled) {
    if (_discovery == nullptr) return;
    final int result = _bindings.discoverySetBaseFolderEnabled(_discovery, baseFolderId, enabled ? 1 : 0);
    if (result != 0) {
      state = state.copyWith(lastError: _decodeLastError());
      return;
    }
    _listBaseFolders();
  }

  /// Unregisters a base folder. Its already-discovered repositories stay in
  /// the list (see gbm_discovery_remove_base_folder()'s doc comment).
  void removeBaseFolder(int baseFolderId) {
    if (_discovery == nullptr) return;
    final int result = _bindings.discoveryRemoveBaseFolder(_discovery, baseFolderId);
    if (result != 0) {
      state = state.copyWith(lastError: _decodeLastError());
      return;
    }
    _listBaseFolders();
  }

  @override
  void dispose() {
    if (_discovery != nullptr) {
      _bindings.discoveryClose(_discovery);
      _discovery = nullptr;
    }
    super.dispose();
  }
}

final StateNotifierProvider<DiscoveryController, DiscoveryState> discoveryProvider =
    StateNotifierProvider<DiscoveryController, DiscoveryState>((ref) {
      return DiscoveryController(ref.watch(gbmBindingsProvider));
    });
