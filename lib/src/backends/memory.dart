/// MemoryNamespace - In-memory 9S Backend
///
/// Prima materia - the simplest namespace.
/// All data in RAM. No persistence. Perfect for testing and transient state.
///
/// ## Dart Lesson: StreamController for Reactive Systems
///
/// Dart's StreamController is the bridge between imperative writes and
/// reactive subscriptions. When we call `write()`, we notify all watchers
/// via their StreamControllers.
///
/// This is Dart's version of Rust's channels, but with key differences:
/// 1. Streams are lazy (no work until listened)
/// 2. Streams can be broadcast (multiple listeners)
/// 3. Streams integrate with async/await naturally
library;

import 'dart:async';

import '../namespace/namespace.dart';
import '../scroll/scroll.dart';
import '../watch/watcher.dart';

/// MemoryNamespace - In-memory implementation
///
/// ## Dart Lesson: Private Fields
///
/// In Dart, `_fieldName` (leading underscore) makes a field library-private.
/// This is different from class-private - other classes in this file can access it.
/// True encapsulation requires putting classes in separate files.
class MemoryNamespace implements Namespace {
  /// In-memory storage
  ///
  /// ## Dart Lesson: Map Literal Types
  ///
  /// `<String, Scroll>{}` explicitly types the map.
  /// Dart can often infer types, but explicit is clearer for class fields.
  final Map<String, Scroll> _store = {};

  /// Active watchers (using shared Watcher class)
  final List<Watcher<Scroll>> _watchers = [];

  /// Closed flag
  bool _closed = false;

  /// Create a new in-memory namespace
  MemoryNamespace();

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

  // ============================================================================
  // Namespace Implementation
  // ============================================================================

  @override
  NineResult<Scroll?> read(String path) {
    final closed = _checkClosed();
    if (closed.isErr) return Err(closed.errorOrNull!);

    final validation = validatePath(path);
    if (validation.isErr) return Err(validation.errorOrNull!);

    return Ok(_store[path]);
  }

  @override
  NineResult<Scroll> write(String path, Map<String, dynamic> data) {
    final closed = _checkClosed();
    if (closed.isErr) return Err(closed.errorOrNull!);

    final validation = validatePath(path);
    if (validation.isErr) return Err(validation.errorOrNull!);

    // Get previous version
    final prevVersion = _store[path]?.metadata.version ?? 0;

    // Create scroll with rich metadata
    final now = DateTime.now().millisecondsSinceEpoch;
    var scroll = Scroll(
      key: path,
      data: data,
      metadata: Metadata(
        version: prevVersion + 1,
        createdAt: now,
        updatedAt: now,
      ),
    );
    scroll = scroll.copyWith(
      metadata: scroll.metadata.copyWith(hash: scroll.computeHash()),
    );

    // Store it
    _store[path] = scroll;

    // Notify watchers
    _notifyWatchers(scroll);

    return Ok(scroll);
  }

  @override
  NineResult<Scroll> writeScroll(Scroll scroll) {
    final closed = _checkClosed();
    if (closed.isErr) return Err(closed.errorOrNull!);

    final validation = validatePath(scroll.key);
    if (validation.isErr) return Err(validation.errorOrNull!);

    // Get previous version
    final prevVersion = _store[scroll.key]?.metadata.version ?? 0;

    // Create new scroll preserving type from input
    final now = DateTime.now().millisecondsSinceEpoch;
    var newScroll = scroll.copyWith(
      metadata: scroll.metadata.copyWith(
        version: prevVersion + 1,
        createdAt: scroll.metadata.createdAt ?? now,
        updatedAt: now,
      ),
    );
    newScroll = newScroll.copyWith(
      metadata: newScroll.metadata.copyWith(hash: newScroll.computeHash()),
    );

    // Store it
    _store[scroll.key] = newScroll;

    // Notify watchers
    _notifyWatchers(newScroll);

    return Ok(newScroll);
  }

  @override
  NineResult<List<String>> list(String prefix) {
    final closed = _checkClosed();
    if (closed.isErr) return Err(closed.errorOrNull!);

    final validation = validatePath(prefix);
    if (validation.isErr) return Err(validation.errorOrNull!);

    // Filter keys under prefix with segment boundary check
    final paths = _store.keys
        .where((k) => isPathUnderPrefix(k, prefix))
        .toList();

    return Ok(paths);
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
  // Convenience Methods
  // ============================================================================

  /// Get current scroll count
  int get length => _store.length;

  /// Check if path exists
  bool containsKey(String path) => _store.containsKey(path);

  /// Clear all data (but keep watchers)
  void clear() => _store.clear();
}
