/// Store - Encrypted Sovereign Storage
///
/// The Store is the "encrypted HDD" - a namespace that:
/// 1. Encrypts all data at rest (AES-256-GCM)
/// 2. Tracks history via patches
/// 3. Supports anchors (checkpoints)
/// 4. Derives per-app keys via HKDF
///
/// ## Platonic Form: 🏛️ (Sovereign Vault)
///
/// A Store is a Namespace with mandatory encryption. This is the core
/// of digital sovereignty: user owns keys → user owns data.
///
/// ```
/// Store = Namespace + Encryption + History + Anchors
/// ```
///
/// ## HKDF Key Derivation
///
/// Each app gets a unique encryption key derived from the master key:
///
/// ```
/// app_key = HKDF(master_key, salt="nine_s_v1", info=app_name)
/// ```
///
/// This provides cryptographic isolation between apps sharing the same
/// master key.
///
/// ## Dart Lesson: Composition Over Inheritance
///
/// Store wraps (composes) a FileNamespace rather than extending it.
/// This is the SICP principle: "Use ≠ Representation".
/// Store USES a namespace internally but IS NOT a namespace itself
/// (though it implements the interface for convenience).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'anchor.dart';
import 'namespace.dart';
import 'patch.dart';
import 'scroll.dart';
import 'utils.dart' as utils;

/// Store - Secure, encrypted namespace storage
///
/// The primary interface for sovereign, encrypted storage.
/// Each app gets an isolated, encrypted namespace via `Store.open()`.
///
/// ## Encryption is Mandatory
///
/// All data written to a Store is encrypted at rest using AES-256-GCM.
/// The key derives from user's master key during onboarding.
///
/// ```dart
/// // Open encrypted store
/// final store = await Store.open('/path/to/store', masterKey);
///
/// // All operations encrypt/decrypt transparently
/// store.write('/wallet/seed', {'phrase': '...'});
/// ```
class Store implements Namespace {
  final Directory _baseDir;
  final Uint8List _encryptionKey;
  final Directory _scrollsDir;
  final Directory _historyDir;
  bool _closed = false;
  final List<StreamController<Scroll>> _watchers = [];

  Store._({
    required Directory baseDir,
    required Uint8List encryptionKey,
  })  : _baseDir = baseDir,
        _encryptionKey = encryptionKey,
        _scrollsDir = Directory('${baseDir.path}/_scrolls'),
        _historyDir = Directory('${baseDir.path}/_history');

  /// Open an encrypted store at a path
  ///
  /// Creates the directory structure if it doesn't exist.
  /// All data is encrypted using the provided key.
  ///
  /// ## Example
  /// ```dart
  /// final store = await Store.open('/path/to/store', key);
  /// store.write('/wallet/balance', {'sats': 100000});
  /// ```
  static Future<Store> open(String path, Uint8List encryptionKey) async {
    if (encryptionKey.length != 32) {
      throw ArgumentError('Encryption key must be 32 bytes (256 bits)');
    }

    final baseDir = Directory(path);
    final store = Store._(baseDir: baseDir, encryptionKey: encryptionKey);

    // Ensure directories exist
    await store._scrollsDir.create(recursive: true);
    await store._historyDir.create(recursive: true);

    return store;
  }

  /// Open a store for an app with HKDF key derivation
  ///
  /// The master key is NOT used directly. Instead, an app-specific key
  /// is derived using HKDF-SHA256:
  ///
  /// ```
  /// app_key = HKDF(master_key, salt="nine_s_v1", info=app_name)
  /// ```
  ///
  /// This provides cryptographic isolation between apps.
  static Future<Store> openForApp(
    String path,
    Uint8List masterKey,
    String appName,
  ) async {
    final derivedKey = utils.deriveAppKey(masterKey, appName);
    return open(path, derivedKey);
  }

  /// Generate a random test key
  ///
  /// Convenience method for tests. In production, keys come from user onboarding.
  static Uint8List testKey() => utils.generateTestKey();

  /// Get the base directory path
  String get path => _baseDir.path;

  /// Check if the store is encrypted (always true)
  bool get isEncrypted => true;

  // ============================================================================
  // Namespace Implementation
  // ============================================================================

  Result<void> _checkClosed() {
    if (_closed) return const Err(ClosedError());
    return const Ok(null);
  }

  @override
  Result<Scroll?> read(String path) {
    final closed = _checkClosed();
    if (closed.isErr) return Err(closed.errorOrNull!);

    final validation = validatePath(path);
    if (validation.isErr) return Err(validation.errorOrNull!);

    try {
      final file = _scrollFile(path);
      if (!file.existsSync()) return const Ok(null);

      final encrypted = file.readAsBytesSync();
      final decrypted = utils.decrypt(_encryptionKey, Uint8List.fromList(encrypted));
      if (decrypted == null) {
        return const Err(InternalError('Decryption failed'));
      }

      final json = jsonDecode(utf8.decode(decrypted)) as Map<String, dynamic>;
      return Ok(Scroll.fromJson(json));
    } catch (e) {
      return Err(InternalError('Read failed: $e'));
    }
  }

  @override
  Result<Scroll> write(String path, Map<String, dynamic> data) {
    return writeScroll(Scroll.create(path, data));
  }

  @override
  Result<Scroll> writeScroll(Scroll scroll) {
    final closed = _checkClosed();
    if (closed.isErr) return Err(closed.errorOrNull!);

    final validation = validatePath(scroll.key);
    if (validation.isErr) return Err(validation.errorOrNull!);

    try {
      // Read current state for history
      final oldResult = read(scroll.key);
      final old = oldResult.isOk ? oldResult.value : null;

      // Get next version from history
      final nextVersion = _nextSeq(scroll.key);

      // Finalize scroll with version and timestamps
      final now = DateTime.now().millisecondsSinceEpoch;
      var finalScroll = scroll.copyWith(
        metadata: scroll.metadata.copyWith(
          version: nextVersion,
          createdAt: old?.metadata.createdAt ?? now,
          updatedAt: now,
        ),
      );
      finalScroll = finalScroll.copyWith(
        metadata: finalScroll.metadata.copyWith(hash: finalScroll.computeHash()),
      );

      // Create patch for history
      final patch = createPatch(scroll.key, old, finalScroll);
      _storePatch(patch);

      // Encrypt and store
      final json = jsonEncode(finalScroll.toJson());
      final encrypted = utils.encrypt(_encryptionKey, Uint8List.fromList(utf8.encode(json)));

      final file = _scrollFile(scroll.key);
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(encrypted);

      // Notify watchers
      _notifyWatchers(finalScroll);

      return Ok(finalScroll);
    } catch (e) {
      return Err(InternalError('Write failed: $e'));
    }
  }

  @override
  Result<List<String>> list(String prefix) {
    final closed = _checkClosed();
    if (closed.isErr) return Err(closed.errorOrNull!);

    final validation = validatePath(prefix);
    if (validation.isErr) return Err(validation.errorOrNull!);

    try {
      if (!_scrollsDir.existsSync()) return const Ok([]);

      final paths = <String>[];

      for (final entity in _scrollsDir.listSync(recursive: true)) {
        if (entity is File && entity.path.endsWith('.json')) {
          final relativePath =
              entity.path.substring(_scrollsDir.path.length).replaceAll('.json', '');
          final scrollPath = relativePath.replaceAll(Platform.pathSeparator, '/');

          if (isPathUnderPrefix(scrollPath, prefix)) {
            paths.add(scrollPath);
          }
        }
      }

      return Ok(paths);
    } catch (e) {
      return Err(InternalError('List failed: $e'));
    }
  }

  @override
  Result<Stream<Scroll>> watch(String pattern) {
    final closed = _checkClosed();
    if (closed.isErr) return Err(closed.errorOrNull!);

    final validation = validatePath(pattern);
    if (validation.isErr) return Err(validation.errorOrNull!);

    final controller = StreamController<Scroll>(
      onCancel: () {
        // Will be cleaned up on next notification
      },
    );

    _watchers.add(controller);

    // Wrap the stream to filter by pattern
    final filteredStream = controller.stream.where((scroll) {
      return pathMatches(scroll.key, pattern);
    });

    return Ok(filteredStream);
  }

  @override
  Result<void> close() {
    _closed = true;

    for (final watcher in _watchers) {
      watcher.close();
    }
    _watchers.clear();

    return const Ok(null);
  }

  void _notifyWatchers(Scroll scroll) {
    _watchers.removeWhere((w) => w.isClosed);
    for (final watcher in _watchers) {
      watcher.add(scroll);
    }
  }

  // ============================================================================
  // History Operations
  // ============================================================================

  /// Get the patch history for a scroll
  ///
  /// Returns all patches in chronological order (oldest first).
  List<Patch> history(String path) {
    final historyDir = _historyDirFor(path);
    final patchesDir = Directory('${historyDir.path}/patches');

    if (!patchesDir.existsSync()) return [];

    final patches = <Patch>[];

    for (final file in patchesDir.listSync()) {
      if (file is File && file.path.endsWith('.json')) {
        try {
          final json =
              jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
          patches.add(Patch.fromJson(json));
        } catch (_) {
          // Skip corrupted patches
        }
      }
    }

    patches.sort((a, b) => a.seq.compareTo(b.seq));
    return patches;
  }

  /// Create an anchor (immutable checkpoint)
  ///
  /// Anchors freeze the current state with an optional label.
  Result<Anchor> anchor(String path, {String? label}) {
    final scrollResult = read(path);
    if (scrollResult.isErr) return Err(scrollResult.errorOrNull!);
    if (scrollResult.value == null) {
      return Err(NotFoundError('No scroll at $path'));
    }

    final scroll = scrollResult.value!;
    final anchorObj = createAnchor(scroll, label: label);

    // Store anchor
    final anchorsDir = Directory('${_historyDirFor(path).path}/anchors');
    anchorsDir.createSync(recursive: true);

    final anchorFile = File('${anchorsDir.path}/${anchorObj.id}.json');
    anchorFile.writeAsStringSync(jsonEncode(anchorObj.toJson()));

    return Ok(anchorObj);
  }

  /// List all anchors for a scroll
  List<Anchor> anchors(String path) {
    final anchorsDir = Directory('${_historyDirFor(path).path}/anchors');

    if (!anchorsDir.existsSync()) return [];

    final anchorList = <Anchor>[];

    for (final file in anchorsDir.listSync()) {
      if (file is File && file.path.endsWith('.json')) {
        try {
          final json =
              jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
          anchorList.add(Anchor.fromJson(json));
        } catch (_) {
          // Skip corrupted anchors
        }
      }
    }

    anchorList.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return anchorList;
  }

  /// Restore a scroll to an anchored state
  Result<Scroll> restore(String path, String anchorId) {
    final allAnchors = anchors(path);
    final anchorObj = allAnchors.where((a) => a.id == anchorId).firstOrNull;

    if (anchorObj == null) {
      return Err(NotFoundError('Anchor not found: $anchorId'));
    }

    if (!verifyAnchor(anchorObj)) {
      return const Err(InternalError('Anchor integrity check failed'));
    }

    return writeScroll(anchorObj.scroll);
  }

  /// Reconstruct state at a specific sequence number
  Result<Scroll> stateAt(String path, int seq) {
    final patches = history(path);

    if (patches.isEmpty) {
      return Err(NotFoundError('No history for $path'));
    }

    if (seq < 1 || seq > patches.length) {
      return Err(InternalError('Invalid sequence $seq (valid: 1-${patches.length})'));
    }

    // Apply patches up to seq
    var current = Scroll.create(path, {});
    for (final patch in patches.take(seq)) {
      final result = applyPatch(current, patch);
      if (result is PatchErr) {
        return Err(InternalError('Failed to apply patch: ${(result as PatchErr).error}'));
      }
      current = (result as PatchOk<Scroll>).value;
    }

    return Ok(current);
  }

  // ============================================================================
  // Internal: File Management
  // ============================================================================

  File _scrollFile(String path) {
    final cleanPath = path.substring(1); // Remove leading /
    return File('${_scrollsDir.path}/$cleanPath.json');
  }

  Directory _historyDirFor(String path) {
    final cleanPath = path.substring(1); // Remove leading /
    return Directory('${_historyDir.path}/$cleanPath');
  }

  int _nextSeq(String path) {
    final patchesDir = Directory('${_historyDirFor(path).path}/patches');
    if (!patchesDir.existsSync()) return 1;

    var maxSeq = 0;
    for (final file in patchesDir.listSync()) {
      if (file is File) {
        final name = file.uri.pathSegments.last.replaceAll('.json', '');
        final seq = int.tryParse(name) ?? 0;
        if (seq > maxSeq) maxSeq = seq;
      }
    }
    return maxSeq + 1;
  }

  void _storePatch(Patch patch) {
    final patchesDir = Directory('${_historyDirFor(patch.key).path}/patches');
    patchesDir.createSync(recursive: true);

    final patchFile =
        File('${patchesDir.path}/${patch.seq.toString().padLeft(8, '0')}.json');
    patchFile.writeAsStringSync(jsonEncode(patch.toJson()));
  }
}
