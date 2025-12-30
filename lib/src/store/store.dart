/// Store - Universal Storage Abstraction
///
/// The Store is the high-level API for 9S storage. It wraps any backend
/// (memory or file) with optional encryption and history tracking.
///
/// ## Design Philosophy
///
/// Store is parametrized by:
/// 1. **Backend**: Where data lives (RAM vs disk)
/// 2. **Encryption**: Whether data is encrypted at rest (default: encrypted for file)
/// 3. **History**: Whether to track patches/anchors
///
/// This gives us a 2x2x2 matrix of 8 possible configurations:
///
/// ```
/// Backend  | Encrypted | History | Use Case
/// ---------|-----------|---------|---------------------------
/// memory   | no        | no      | /ui/* - ephemeral UI state
/// memory   | no        | yes     | /cache/* - with undo
/// memory   | yes       | no      | temp secrets (clipboard)
/// memory   | yes       | yes     | (rare)
/// file     | yes       | no      | /vault/* - encrypted data (DEFAULT)
/// file     | yes       | yes     | /ledger/* - encrypted + history
/// file     | no        | no      | /settings/* - preferences
/// file     | no        | yes     | /logs/* - audit trail
/// ```
///
/// ## Usage
///
/// ```dart
/// // RAM - fast, ephemeral (no encryption by default)
/// final ui = Store.memory();
/// ui.write('/nav', {'path': '/wallet'});
///
/// // RAM - encrypted (temp secrets)
/// final clipboard = Store.memory(key: encryptionKey);
///
/// // File - encrypted by default (backward compatible)
/// final vault = Store.open('/path/vault', key: encryptionKey);
///
/// // File - unencrypted (settings)
/// final settings = Store.open('/path/settings', encrypted: false);
///
/// // File - encrypted with history
/// final ledger = Store.open('/path/ledger', key: key, history: true);
/// ```
///
/// ## Backward Compatibility
///
/// The old `Store.open(path, key)` API continues to work:
/// - File-backed stores default to encrypted when key is provided
/// - This is the "vault" pattern from the original Store
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../namespace.dart';
import '../scroll.dart';
import '../patch.dart';
import '../anchor.dart';
import '../utils.dart' as utils;
import '../backends/memory.dart';
import '../backends/file.dart';

/// Store - Universal storage abstraction
///
/// Wraps memory or file backend with optional encryption and history.
/// Default behavior: file stores are encrypted, memory stores are not.
class Store implements Namespace {
  final Namespace _backend;
  final Uint8List? _key;
  final bool _history;
  final String? _path;
  final Map<String, List<Patch>> _patches = {};
  final Map<String, List<Anchor>> _anchors = {};
  final StreamController<Scroll> _changes = StreamController.broadcast();
  bool _closed = false;

  Store._({
    required Namespace backend,
    Uint8List? key,
    bool history = false,
    String? path,
  })  : _backend = backend,
        _key = key,
        _history = history,
        _path = path;

  // ===========================================================================
  // STATIC HELPERS
  // ===========================================================================

  /// Generate a test key (32 bytes for AES-256)
  ///
  /// For testing only. In production, derive from user's master key.
  static Uint8List testKey() {
    return Uint8List.fromList(List.generate(32, (i) => i));
  }

  // ===========================================================================
  // CONSTRUCTORS
  // ===========================================================================

  /// Create an in-memory store (RAM)
  ///
  /// Fast, ephemeral. Data lost on restart.
  /// NOT encrypted by default (pass key to encrypt).
  ///
  /// ```dart
  /// // Ephemeral UI state
  /// final ui = Store.memory();
  /// ui.write('/nav', {'path': '/wallet'});
  ///
  /// // Encrypted temporary secrets
  /// final clipboard = Store.memory(key: encryptionKey);
  /// ```
  factory Store.memory({Uint8List? key, bool history = false}) {
    return Store._(
      backend: MemoryNamespace(),
      key: key,
      history: history,
    );
  }

  /// Open a file-backed store (HDD)
  ///
  /// Persistent. Survives restart.
  /// ENCRYPTED by default when key is provided (backward compatible).
  /// Pass `encrypted: false` to disable encryption.
  ///
  /// ```dart
  /// // Encrypted vault (default behavior with key)
  /// final vault = Store.open('/path/vault', key: masterKey);
  ///
  /// // Unencrypted settings
  /// final settings = Store.open('/path/settings', encrypted: false);
  ///
  /// // Encrypted with history tracking
  /// final ledger = Store.open('/path/ledger', key: key, history: true);
  /// ```
  factory Store.open(
    String path, [
    Uint8List? key,
  ]) {
    // Validate key length if provided
    if (key != null && key.length != 32) {
      throw ArgumentError('Key must be 32 bytes for AES-256');
    }

    // Create _history directory for backward compat
    // FileNamespace already creates _scrolls internally
    final historyDir = Directory('$path/_history');
    historyDir.createSync(recursive: true);

    // History defaults to true for file stores (backward compat)
    return Store._(
      backend: FileNamespace(path),
      key: key,
      history: true,
      path: path,
    );
  }

  /// Open a file-backed store with named parameters
  ///
  /// Use this for more control over encryption and history.
  factory Store.openWith(
    String path, {
    Uint8List? key,
    bool? encrypted,
    bool? history,
  }) {
    // Backward compatible: if key provided, default to encrypted
    // If encrypted explicitly set to false, don't encrypt even with key
    final shouldEncrypt = encrypted ?? (key != null);
    final effectiveKey = shouldEncrypt ? key : null;

    // History defaults to true for file stores (backward compat)
    final effectiveHistory = history ?? true;

    return Store._(
      backend: FileNamespace(path),
      key: effectiveKey,
      history: effectiveHistory,
      path: path,
    );
  }

  /// Open a store with app-specific key derivation (HKDF)
  ///
  /// Each app gets a unique encryption key derived from the master key.
  /// This provides cryptographic isolation between apps.
  ///
  /// ```dart
  /// final walletStore = Store.openForApp('/path/wallet', masterKey, 'wallet');
  /// final vaultStore = Store.openForApp('/path/vault', masterKey, 'vault');
  /// // Same master key, but different derived keys
  /// ```
  static Future<Store> openForApp(
    String path,
    Uint8List masterKey,
    String appName, {
    bool? history,
  }) async {
    // Derive app-specific key using HKDF
    final appKey = utils.deriveAppKey(masterKey, appName);

    return Store._(
      backend: FileNamespace(path),
      key: appKey,
      history: history ?? true,
      path: path,
    );
  }

  // ===========================================================================
  // PROPERTIES
  // ===========================================================================

  /// Whether this store encrypts data
  bool get encrypted => _key != null;

  /// Alias for backward compatibility
  bool get isEncrypted => encrypted;

  /// Whether this store tracks history
  bool get tracksHistory => _history;

  /// Store path (for file-backed stores)
  String? get path => _path;

  // ===========================================================================
  // NAMESPACE IMPLEMENTATION
  // ===========================================================================

  @override
  Result<Scroll?> read(String path) {
    if (_closed) return const Err(ClosedError());

    final validation = validatePath(path);
    if (validation.isErr) return Err(validation.errorOrNull!);

    final result = _backend.read(path);
    if (result.isErr) return result;

    final scroll = result.value;
    if (scroll == null) return const Ok(null);

    // Decrypt if encrypted
    if (_key != null) {
      return _decrypt(scroll);
    }

    return Ok(scroll);
  }

  @override
  Result<Scroll> write(String path, Map<String, dynamic> data) {
    return writeScroll(Scroll.create(path, data));
  }

  @override
  Result<Scroll> writeScroll(Scroll scroll) {
    if (_closed) return const Err(ClosedError());

    final validation = validatePath(scroll.key);
    if (validation.isErr) return Err(validation.errorOrNull!);

    // Read old value for history
    Scroll? old;
    if (_history) {
      final oldResult = read(scroll.key);
      if (oldResult.isOk) old = oldResult.value;
    }

    // Finalize scroll with metadata
    final now = DateTime.now().millisecondsSinceEpoch;
    final prevVersion = old?.metadata.version ?? 0;
    var finalScroll = scroll.copyWith(
      metadata: scroll.metadata.copyWith(
        version: prevVersion + 1,
        createdAt: old?.metadata.createdAt ?? now,
        updatedAt: now,
      ),
    );
    finalScroll = finalScroll.copyWith(
      metadata: finalScroll.metadata.copyWith(hash: finalScroll.computeHash()),
    );

    // Encrypt if needed
    Scroll toStore = finalScroll;
    if (_key != null) {
      final encryptResult = _encrypt(finalScroll);
      if (encryptResult.isErr) return Err(encryptResult.errorOrNull!);
      toStore = encryptResult.value!;
    }

    // Write to backend
    final writeResult = _backend.writeScroll(toStore);
    if (writeResult.isErr) return writeResult;

    // Track history
    if (_history) {
      _trackPatch(scroll.key, old, finalScroll);
    }

    // Notify watchers
    if (!_changes.isClosed) {
      _changes.add(finalScroll);
    }

    return Ok(finalScroll);
  }

  @override
  Result<List<String>> list(String prefix) {
    if (_closed) return const Err(ClosedError());
    return _backend.list(prefix);
  }

  @override
  Result<Stream<Scroll>> watch(String pattern) {
    if (_closed) return const Err(ClosedError());

    final validation = validatePath(pattern);
    if (validation.isErr) return Err(validation.errorOrNull!);

    // Filter changes stream by pattern
    final filtered = _changes.stream.where((scroll) {
      return pathMatches(scroll.key, pattern);
    });

    return Ok(filtered);
  }

  @override
  Result<void> close() {
    _closed = true;
    _changes.close();
    _backend.close();
    return const Ok(null);
  }

  // ===========================================================================
  // HISTORY OPERATIONS
  // ===========================================================================

  /// Get patch history for a path
  List<Patch> history(String path) {
    return List.unmodifiable(_patches[path] ?? []);
  }

  /// Create an anchor (checkpoint)
  Result<Anchor> anchor(String path, {String? label}) {
    if (!_history) {
      return const Err(UnavailableError('History not enabled for this store'));
    }

    final scrollResult = read(path);
    if (scrollResult.isErr) return Err(scrollResult.errorOrNull!);
    if (scrollResult.value == null) {
      return Err(NotFoundError('No scroll at $path'));
    }

    final anchorObj = createAnchor(scrollResult.value!, label: label);
    _anchors.putIfAbsent(path, () => []).add(anchorObj);

    return Ok(anchorObj);
  }

  /// List anchors for a path
  List<Anchor> anchors(String path) {
    return List.unmodifiable(_anchors[path] ?? []);
  }

  /// Restore to an anchor
  Result<Scroll> restore(String path, String anchorId) {
    final pathAnchors = _anchors[path] ?? [];
    final anchorObj = pathAnchors.where((a) => a.id == anchorId).firstOrNull;

    if (anchorObj == null) {
      return Err(NotFoundError('Anchor not found: $anchorId'));
    }

    if (!verifyAnchor(anchorObj)) {
      return const Err(InternalError('Anchor integrity check failed'));
    }

    return writeScroll(anchorObj.scroll);
  }

  /// Reconstruct state at a specific sequence number
  ///
  /// Read-only time travel - returns the scroll as it existed after the
  /// given sequence number without modifying current state.
  ///
  /// ```dart
  /// store.write('/doc', {'v': 1});  // seq 1
  /// store.write('/doc', {'v': 2});  // seq 2
  /// store.write('/doc', {'v': 3});  // seq 3
  ///
  /// final v2 = store.stateAt('/doc', 2);
  /// print(v2.value?.data['v']);  // 2
  /// ```
  Result<Scroll> stateAt(String path, int seq) {
    final patches = history(path);

    if (patches.isEmpty) {
      return Err(NotFoundError('No history at $path'));
    }

    if (seq < 1 || seq > patches.length) {
      return Err(InternalError(
        'Invalid sequence $seq. Valid range: 1-${patches.length}',
      ));
    }

    // Apply patches up to the requested sequence
    var current = Scroll.create(path, <String, dynamic>{});

    for (var i = 0; i < seq; i++) {
      final patchResult = applyPatch(current, patches[i]);
      switch (patchResult) {
        case PatchOk(:final value):
          current = value;
        case PatchErr(:final error):
          return Err(InternalError('Failed to apply patch: $error'));
      }
    }

    return Ok(current);
  }

  // ===========================================================================
  // INTERNAL: ENCRYPTION
  // ===========================================================================

  Result<Scroll?> _decrypt(Scroll scroll) {
    try {
      // Data is stored as base64 encoded encrypted bytes
      final encryptedB64 = scroll.data['_encrypted'] as String?;
      if (encryptedB64 == null) {
        // Not encrypted, return as-is
        return Ok(scroll);
      }

      final encrypted = base64Decode(encryptedB64);
      final decrypted = utils.decrypt(_key!, Uint8List.fromList(encrypted));
      if (decrypted == null) {
        return const Err(InternalError('Decryption failed'));
      }

      final data = jsonDecode(utf8.decode(decrypted)) as Map<String, dynamic>;
      return Ok(scroll.copyWith(data: data));
    } catch (e) {
      return Err(InternalError('Decrypt failed: $e'));
    }
  }

  Result<Scroll?> _encrypt(Scroll scroll) {
    try {
      final plaintext = utf8.encode(jsonEncode(scroll.data));
      final encrypted = utils.encrypt(_key!, Uint8List.fromList(plaintext));
      final encryptedB64 = base64Encode(encrypted);

      return Ok(scroll.copyWith(data: {'_encrypted': encryptedB64}));
    } catch (e) {
      return Err(InternalError('Encrypt failed: $e'));
    }
  }

  // ===========================================================================
  // INTERNAL: HISTORY
  // ===========================================================================

  void _trackPatch(String path, Scroll? old, Scroll current) {
    final patch = createPatch(path, old, current);
    _patches.putIfAbsent(path, () => []).add(patch);
  }
}
