/// FileNamespace - Filesystem-backed 9S Namespace
///
/// Persists scrolls to the filesystem as JSON files.
/// Each scroll at path `/foo/bar` maps to `{root}/_scrolls/foo/bar.json`.
///
/// ## Dart Lesson: dart:io for File Operations
///
/// Dart's `dart:io` library provides synchronous and async file APIs.
/// We use sync methods for simplicity since 9S operations are meant
/// to be fast and local (not networked).
///
/// For async operations, use `file.readAsString()` instead of
/// `file.readAsStringSync()`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../namespace/namespace.dart';
import '../scroll/scroll.dart';
import '../watch/watcher.dart';

/// FileNamespace - Filesystem-backed implementation
///
/// All data stored as JSON files under `{root}/_scrolls/`.
/// Provides persistence across process restarts.
class FileNamespace implements Namespace {
  /// Root directory for this namespace
  final Directory _root;

  /// Directory where scrolls are stored
  final Directory _scrollsDir;

  /// Active watchers (using shared Watcher class)
  final List<Watcher<Scroll>> _watchers = [];

  /// Closed flag
  bool _closed = false;

  /// Create a new filesystem namespace at the given path
  ///
  /// Creates the directory structure if it doesn't exist.
  FileNamespace(String path)
      : _root = Directory(path),
        _scrollsDir = Directory('$path/_scrolls') {
    _scrollsDir.createSync(recursive: true);
  }

  /// Get the root path
  String get path => _root.path;

  /// Check if closed
  NineResult<void> _checkClosed() {
    if (_closed) return const Err(ClosedError());
    return const Ok(null);
  }

  /// Notify all watchers of a change
  ///
  /// Uses the shared notifyWatchers helper which also cleans up dead watchers.
  void _notifyWatchers(Scroll scroll) {
    notifyWatchers(_watchers, scroll.key, scroll);
  }

  /// Convert a scroll path to a filesystem path
  File _scrollFile(String scrollPath) {
    // Remove leading slash
    final relativePath = scrollPath.startsWith('/')
        ? scrollPath.substring(1)
        : scrollPath;
    return File('${_scrollsDir.path}/$relativePath.json');
  }

  /// Convert a filesystem path back to a scroll path
  String _fileToScrollPath(String filePath) {
    final relative = filePath
        .substring(_scrollsDir.path.length)
        .replaceAll('.json', '')
        .replaceAll(Platform.pathSeparator, '/');
    return relative.startsWith('/') ? relative : '/$relative';
  }

  // ============================================================================
  // Namespace Implementation
  // ============================================================================

  @override
  NineResult<Scroll?> read(String path) {
    final closed = _checkClosed();
    if (closed.isErr) return Err(closed.errorOrNull!);

    final validation = validatePath(path);
    if (validation.isErr) return Err(validation.errorOrNull!);

    try {
      final file = _scrollFile(path);
      if (!file.existsSync()) return const Ok(null);

      final content = file.readAsStringSync();
      final json = jsonDecode(content) as Map<String, dynamic>;
      return Ok(Scroll.fromJson(json));
    } catch (e) {
      return Err(InternalError('Failed to read scroll: $e'));
    }
  }

  @override
  NineResult<Scroll> write(String path, Map<String, dynamic> data) {
    final closed = _checkClosed();
    if (closed.isErr) return Err(closed.errorOrNull!);

    final validation = validatePath(path);
    if (validation.isErr) return Err(validation.errorOrNull!);

    try {
      // Get previous version
      final existing = read(path);
      final prevVersion = existing.isOk && existing.value != null
          ? existing.value!.metadata.version
          : 0;

      // Create scroll with rich metadata
      final now = DateTime.now().millisecondsSinceEpoch;
      var scroll = Scroll(
        key: path,
        data: data,
        metadata: Metadata(
          version: prevVersion + 1,
          createdAt: existing.value?.metadata.createdAt ?? now,
          updatedAt: now,
        ),
      );
      scroll = scroll.copyWith(
        metadata: scroll.metadata.copyWith(hash: scroll.computeHash()),
      );

      // Write to file
      final file = _scrollFile(path);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(jsonEncode(scroll.toJson()));

      // Notify watchers
      _notifyWatchers(scroll);

      return Ok(scroll);
    } catch (e) {
      return Err(InternalError('Failed to write scroll: $e'));
    }
  }

  @override
  NineResult<Scroll> writeScroll(Scroll scroll) {
    final closed = _checkClosed();
    if (closed.isErr) return Err(closed.errorOrNull!);

    final validation = validatePath(scroll.key);
    if (validation.isErr) return Err(validation.errorOrNull!);

    try {
      // Get previous version
      final existing = read(scroll.key);
      final prevVersion = existing.isOk && existing.value != null
          ? existing.value!.metadata.version
          : 0;

      // Create new scroll preserving type from input
      final now = DateTime.now().millisecondsSinceEpoch;
      var newScroll = scroll.copyWith(
        metadata: scroll.metadata.copyWith(
          version: prevVersion + 1,
          createdAt: scroll.metadata.createdAt ??
              existing.value?.metadata.createdAt ??
              now,
          updatedAt: now,
        ),
      );
      newScroll = newScroll.copyWith(
        metadata: newScroll.metadata.copyWith(hash: newScroll.computeHash()),
      );

      // Write to file
      final file = _scrollFile(scroll.key);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(jsonEncode(newScroll.toJson()));

      // Notify watchers
      _notifyWatchers(newScroll);

      return Ok(newScroll);
    } catch (e) {
      return Err(InternalError('Failed to write scroll: $e'));
    }
  }

  @override
  NineResult<List<String>> list(String prefix) {
    final closed = _checkClosed();
    if (closed.isErr) return Err(closed.errorOrNull!);

    final validation = validatePath(prefix);
    if (validation.isErr) return Err(validation.errorOrNull!);

    try {
      if (!_scrollsDir.existsSync()) return const Ok([]);

      final paths = <String>[];

      for (final entity in _scrollsDir.listSync(recursive: true)) {
        if (entity is File && entity.path.endsWith('.json')) {
          final scrollPath = _fileToScrollPath(entity.path);
          if (isPathUnderPrefix(scrollPath, prefix)) {
            paths.add(scrollPath);
          }
        }
      }

      return Ok(paths);
    } catch (e) {
      return Err(InternalError('Failed to list scrolls: $e'));
    }
  }

  @override
  NineResult<Stream<Scroll>> watch(String pattern) {
    final closed = _checkClosed();
    if (closed.isErr) return Err(closed.errorOrNull!);

    final validation = validatePath(pattern);
    if (validation.isErr) return Err(validation.errorOrNull!);

    // Check watcher limit (also cleanup dead watchers)
    cleanupDeadWatchers(_watchers);
    if (_watchers.length >= maxWatchers) {
      return const Err(UnavailableError('too many watchers'));
    }

    // Create stream controller
    final controller = StreamController<Scroll>();
    _watchers.add(Watcher(pattern: pattern, controller: controller));

    return Ok(controller.stream);
  }

  @override
  NineResult<void> close() {
    _closed = true;

    // Close all watchers
    for (final watcher in _watchers) {
      watcher.close();
    }
    _watchers.clear();

    return const Ok(null);
  }

  // ============================================================================
  // Convenience Methods (not part of frozen interface)
  // ============================================================================

  /// Delete a scroll at the given path
  ///
  /// Returns `Ok(true)` if deleted, `Ok(false)` if didn't exist.
  /// Note: This is a convenience method, not part of the frozen 5 operations.
  NineResult<bool> delete(String path) {
    final closed = _checkClosed();
    if (closed.isErr) return Err(closed.errorOrNull!);

    final validation = validatePath(path);
    if (validation.isErr) return Err(validation.errorOrNull!);

    try {
      final file = _scrollFile(path);
      if (!file.existsSync()) return const Ok(false);

      file.deleteSync();
      return const Ok(true);
    } catch (e) {
      return Err(InternalError('Failed to delete scroll: $e'));
    }
  }

  /// Check if a path exists
  bool exists(String path) {
    return _scrollFile(path).existsSync();
  }

  /// Get the number of scrolls (total count)
  int get length {
    if (!_scrollsDir.existsSync()) return 0;

    return _scrollsDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .length;
  }

  /// Clear all scrolls (use with caution!)
  void clear() {
    if (_scrollsDir.existsSync()) {
      _scrollsDir.deleteSync(recursive: true);
      _scrollsDir.createSync(recursive: true);
    }
  }
}
