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
///
/// ## Dart Lesson: Finalizer for GC-Aware Cleanup
///
/// Dart 2.17+ provides `Finalizer` and `WeakReference` for GC integration:
///
/// - `Finalizer<T>` - Runs a callback when an object is garbage collected
/// - `WeakReference<T>` - Holds a reference without preventing GC
///
/// This enables "release when forgotten" semantics - if user code drops all
/// references to a watch stream, the watcher cleans itself up automatically.
library;

import 'dart:async';

import '../namespace.dart';
import '../scroll.dart';

/// Maximum number of concurrent watchers
const _maxWatchers = 1024;

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

  /// Active watchers
  final List<_Watcher> _watchers = [];

  /// Closed flag
  bool _closed = false;

  /// Create a new in-memory namespace
  MemoryNamespace();

  /// Check if closed
  Result<void> _checkClosed() {
    if (_closed) return const Err(ClosedError());
    return const Ok(null);
  }

  /// Notify all watchers of a change
  ///
  /// ## Dart Lesson: Synchronous vs Async Notification
  ///
  /// We use synchronous notification (StreamController.add is sync).
  /// The watchers' handlers run in microtasks, so writes don't block.
  ///
  /// This is different from Rust's try_send which returns immediately.
  /// In Dart, the event is queued and processed in the next microtask.
  ///
  /// ## GC-Aware Cleanup
  ///
  /// We check `isDead` which includes WeakReference check. If user code
  /// has dropped all references to the stream, GC will collect it and
  /// we clean up automatically - no explicit cancel needed.
  void _notifyWatchers(Scroll scroll) {
    // Remove dead watchers (closed OR garbage collected)
    _watchers.removeWhere((w) {
      if (w.isDead) {
        // Ensure controller is closed to release resources
        if (!w.controller.isClosed) {
          w.controller.close();
        }
        return true;
      }
      return false;
    });

    // Notify matching watchers
    for (final watcher in _watchers) {
      if (pathMatches(scroll.key, watcher.pattern)) {
        watcher.controller.add(scroll);
      }
    }
  }

  // ============================================================================
  // Namespace Implementation
  // ============================================================================

  @override
  Result<Scroll?> read(String path) {
    final closed = _checkClosed();
    if (closed.isErr) return Err(closed.errorOrNull!);

    final validation = validatePath(path);
    if (validation.isErr) return Err(validation.errorOrNull!);

    return Ok(_store[path]);
  }

  @override
  Result<Scroll> write(String path, Map<String, dynamic> data) {
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
  Result<Scroll> writeScroll(Scroll scroll) {
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
  Result<List<String>> list(String prefix) {
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
  Result<Stream<Scroll>> watch(String pattern) {
    final closed = _checkClosed();
    if (closed.isErr) return Err(closed.errorOrNull!);

    final validation = validatePath(pattern);
    if (validation.isErr) return Err(validation.errorOrNull!);

    // Check watcher limit (also cleanup dead watchers)
    _watchers.removeWhere((w) => w.isDead);
    if (_watchers.length >= _maxWatchers) {
      return const Err(UnavailableError('too many watchers'));
    }

    // Create stream controller
    ///
    /// ## Dart Lesson: Broadcast Streams
    ///
    /// `StreamController.broadcast()` allows multiple listeners.
    /// Regular controllers only allow one listener.
    ///
    /// For 9S, we use regular controllers (one watcher = one stream).
    /// If you needed multiple listeners on the same pattern, use broadcast.
    final controller = StreamController<Scroll>(
      onCancel: () {
        // Controller will be removed on next write via removeWhere
      },
    );

    _watchers.add(_Watcher(pattern: pattern, controller: controller));

    return Ok(controller.stream);
  }

  @override
  Result<void> close() {
    _closed = true;

    // Close all watchers
    for (final watcher in _watchers) {
      watcher.controller.close();
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

/// Internal watcher state with GC-aware cleanup
///
/// ## Dart Lesson: WeakReference for GC Integration
///
/// We hold a WeakReference to the Stream. When user code drops all references
/// to the stream, it becomes eligible for GC. On the next `_notifyWatchers`
/// call, we detect `target == null` and clean up.
///
/// This is more efficient than checking `controller.isClosed` because:
/// 1. User doesn't need to explicitly cancel/close
/// 2. GC handles cleanup automatically when stream is forgotten
/// 3. No memory leaks from abandoned watchers
class _Watcher {
  final String pattern;
  final StreamController<Scroll> controller;

  /// Weak reference to the stream - allows GC to collect if user drops it
  final WeakReference<Stream<Scroll>> streamRef;

  _Watcher({required this.pattern, required this.controller})
      : streamRef = WeakReference(controller.stream);

  /// Check if this watcher is still alive
  ///
  /// A watcher is dead if:
  /// 1. The controller is closed, OR
  /// 2. The stream has been garbage collected (user dropped all references)
  bool get isDead => controller.isClosed || streamRef.target == null;
}
