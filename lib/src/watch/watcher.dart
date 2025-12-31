/// Watcher - Shared GC-Aware Watch State
///
/// "One Form, many instances."
///
/// This module provides a shared Watcher class used by MemoryNamespace,
/// FileNamespace, and Kernel for GC-aware stream cleanup.
///
/// ## Philosophy
///
/// When a user drops all references to a watch stream, the Dart GC
/// collects it. WeakReference detects this, and on the next write
/// operation, we clean up the orphaned watcher automatically.
///
/// This is "release when forgotten" semantics - no explicit cancel needed.
///
/// ## Dart Lesson: WeakReference for GC Integration
///
/// Dart 2.17+ provides `WeakReference<T>` which holds a reference
/// without preventing garbage collection. When the target is collected,
/// `target` returns null.
///
/// ```dart
/// final weak = WeakReference(someStream);
/// // ... later ...
/// if (weak.target == null) {
///   // Stream was garbage collected
/// }
/// ```
library;

import 'dart:async';

/// Watcher - Shared watch state with GC-aware cleanup
///
/// Generic over T to support both Scroll streams (Namespace)
/// and any other stream type.
class Watcher<T> {
  /// Pattern this watcher is matching
  final String pattern;

  /// Stream controller for this watcher
  final StreamController<T> controller;

  /// Weak reference to the stream - allows GC to collect if user drops it
  final WeakReference<Stream<T>> streamRef;

  /// Create a new watcher for a pattern
  ///
  /// The controller should be created by the caller; this class
  /// manages the lifecycle.
  Watcher({required this.pattern, required this.controller})
      : streamRef = WeakReference(controller.stream);

  /// Check if this watcher is still alive
  ///
  /// A watcher is dead if:
  /// 1. The controller is closed, OR
  /// 2. The stream has been garbage collected (user dropped all references)
  bool get isDead => controller.isClosed || streamRef.target == null;

  /// Check if this watcher is still alive
  bool get isAlive => !isDead;

  /// Close this watcher's controller
  ///
  /// Safe to call multiple times.
  Future<void> close() async {
    if (!controller.isClosed) {
      await controller.close();
    }
  }

  /// Check if pattern matches a given path
  ///
  /// Uses the same matching rules as Namespace.watch:
  /// - Exact match
  /// - Single wildcard: /foo/* matches /foo/bar
  /// - Recursive wildcard: /foo/** matches /foo/bar/baz
  bool matches(String path) {
    // Exact match
    if (path == pattern) return true;

    // Single wildcard: /foo/* matches /foo/bar but not /foo/bar/baz
    if (pattern.endsWith('/*')) {
      final prefix = pattern.substring(0, pattern.length - 1);
      if (path.startsWith(prefix)) {
        final remainder = path.substring(prefix.length);
        return !remainder.contains('/');
      }
      return false;
    }

    // Recursive wildcard: /foo/** matches /foo/bar, /foo/bar/baz, etc.
    if (pattern.endsWith('/**')) {
      final prefix = pattern.substring(0, pattern.length - 2);
      return path.startsWith(prefix);
    }

    return false;
  }

  /// Add a value to the stream if alive
  ///
  /// Returns true if value was added, false if watcher is dead.
  bool add(T value) {
    if (isDead) return false;
    controller.add(value);
    return true;
  }

  /// Add an error to the stream if alive
  bool addError(Object error, [StackTrace? stackTrace]) {
    if (isDead) return false;
    controller.addError(error, stackTrace);
    return true;
  }
}

/// Maximum number of concurrent watchers (per namespace)
const maxWatchers = 1024;

/// Helper to clean up dead watchers from a list
///
/// Returns the number of watchers removed.
int cleanupDeadWatchers<T>(List<Watcher<T>> watchers) {
  final before = watchers.length;
  watchers.removeWhere((w) {
    if (w.isDead) {
      // Ensure controller is closed to release resources
      if (!w.controller.isClosed) {
        w.controller.close();
      }
      return true;
    }
    return false;
  });
  return before - watchers.length;
}

/// Notify all matching watchers of a value
///
/// Automatically cleans up dead watchers.
void notifyWatchers<T>(List<Watcher<T>> watchers, String path, T value) {
  // Remove dead watchers first
  cleanupDeadWatchers(watchers);

  // Notify matching watchers
  for (final watcher in watchers) {
    if (watcher.matches(path)) {
      watcher.add(value);
    }
  }
}
