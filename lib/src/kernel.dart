/// Kernel - Namespace Composition via Mount Table
///
/// "Everything is a file" → "Everything is a Scroll"
///
/// The Kernel is a mount table that composes namespaces into a unified
/// filesystem-like interface. Operations are routed by longest prefix match.
///
/// ## Dart Lesson: Composition Over Inheritance
///
/// The Kernel doesn't extend Namespace - it implements it.
/// Internally, it delegates to mounted namespaces.
/// This is the Gang of Four Composite pattern.
///
/// ## Security
/// - Mount paths are matched on segment boundaries (no cross-namespace leaks)
/// - `/foo` does NOT match `/foobar` (only `/foo` or `/foo/...`)
library;

import 'dart:async';
import 'dart:collection';

import 'namespace.dart';
import 'scroll.dart';

/// Check if a path matches a mount point on segment boundaries
///
/// ## Security
/// This prevents cross-namespace leaks where mounting `/foo` would
/// incorrectly capture `/foobar`.
bool _isPathUnderMount(String path, String mountPath) {
  if (mountPath == '/') return path.startsWith('/');
  if (path == mountPath) return true;

  // Check for segment boundary: path must continue with '/'
  if (path.startsWith(mountPath)) {
    final remainder = path.substring(mountPath.length);
    return remainder.startsWith('/');
  }

  return false;
}

/// Kernel - Namespace composition via mount table
///
/// ## Dart Lesson: SplayTreeMap
///
/// We use SplayTreeMap for the mount table because:
/// 1. Keys are sorted (enables efficient longest-prefix search)
/// 2. Self-balancing (O(log n) operations)
/// 3. Recently accessed items move to root (good for hot paths)
///
/// Compare to HashMap (O(1) but no ordering) and LinkedHashMap (insertion order).
class Kernel implements Namespace {
  /// Mount table: path → namespace
  ///
  /// ## Dart Lesson: late
  ///
  /// `late` means "I promise this will be initialized before first use."
  /// Useful for non-nullable fields that can't be initialized in the constructor.
  /// Here we initialize inline, so it's just documentation that it's set once.
  final SplayTreeMap<String, Namespace> _mounts = SplayTreeMap();

  /// Stream controllers for watch aggregation with GC-aware cleanup
  final List<_KernelWatcher> _watchControllers = [];

  /// Closed flag
  bool _closed = false;

  /// Create a new kernel with empty mount table
  Kernel();

  /// Mount a namespace at a path
  ///
  /// All operations on paths starting with `path` are routed to `ns`.
  /// The namespace sees paths with `path` prefix stripped.
  ///
  /// ## Dart Lesson: Method Chaining Return Type
  ///
  /// Returning `this` enables fluent API:
  /// ```dart
  /// kernel
  ///   ..mount('/wallet', walletNs)
  ///   ..mount('/vault', vaultNs)
  ///   ..mount('/ln', lnNs);
  /// ```
  Kernel mount(String path, Namespace ns) {
    final normalized = normalizeMountPath(path);
    _mounts[normalized] = ns;
    return this;
  }

  /// Unmount a namespace from a path
  ///
  /// Returns the previously mounted namespace, or null if nothing was mounted.
  Namespace? unmount(String path) {
    return _mounts.remove(path);
  }

  /// Find the namespace and translated path for a given path
  ///
  /// Uses longest prefix match with segment boundary checking.
  Result<(Namespace, String)> _resolve(String path) {
    if (_closed) return const Err(ClosedError());

    // Validate path first
    final validation = validatePath(path);
    if (validation.isErr) return Err(validation.errorOrNull!);

    // Find longest matching prefix with segment boundary check
    (String, Namespace)? bestMatch;

    for (final entry in _mounts.entries) {
      final mountPath = entry.key;
      final ns = entry.value;

      if (_isPathUnderMount(path, mountPath)) {
        if (bestMatch == null || mountPath.length > bestMatch.$1.length) {
          bestMatch = (mountPath, ns);
        }
      }
    }

    if (bestMatch == null) {
      return Err(NotFoundError('no namespace mounted for path: $path'));
    }

    final (mountPath, ns) = bestMatch;

    // Strip prefix
    final stripped = switch (mountPath) {
      '/' => path,
      _ when path == mountPath => '/',
      _ => path.substring(mountPath.length),
    };

    return Ok((ns, stripped));
  }

  // ============================================================================
  // Namespace Implementation
  // ============================================================================

  @override
  Result<Scroll?> read(String path) {
    final resolved = _resolve(path);
    if (resolved.isErr) return Err(resolved.errorOrNull!);

    final (ns, stripped) = resolved.value;
    final result = ns.read(stripped);

    // Restore original path if scroll exists
    return result.map((scroll) {
      if (scroll == null) return null;
      return scroll.copyWith(key: path);
    });
  }

  @override
  Result<Scroll> write(String path, Map<String, dynamic> data) {
    final resolved = _resolve(path);
    if (resolved.isErr) return Err(resolved.errorOrNull!);

    final (ns, stripped) = resolved.value;
    final result = ns.write(stripped, data);

    // Restore original path
    return result.map((scroll) => scroll.copyWith(key: path));
  }

  @override
  Result<Scroll> writeScroll(Scroll scroll) {
    final resolved = _resolve(scroll.key);
    if (resolved.isErr) return Err(resolved.errorOrNull!);

    final (ns, stripped) = resolved.value;

    // Create scroll with stripped path for the namespace
    final strippedScroll = scroll.copyWith(key: stripped);
    final result = ns.writeScroll(strippedScroll);

    // Restore original path
    return result.map((s) => s.copyWith(key: scroll.key));
  }

  @override
  Result<List<String>> list(String prefix) {
    final resolved = _resolve(prefix);
    if (resolved.isErr) return Err(resolved.errorOrNull!);

    final (ns, stripped) = resolved.value;
    final result = ns.list(stripped);

    if (result.isErr) return result;

    // Calculate mount prefix
    // If stripped is '/', the mount prefix is the full prefix
    // Otherwise, remove the stripped suffix from prefix
    final String mountPrefix;
    if (stripped == '/') {
      mountPrefix = prefix;
    } else {
      mountPrefix = prefix.substring(0, prefix.length - stripped.length);
    }

    return result.map((paths) {
      return paths.map((p) {
        if (mountPrefix.isEmpty) return p;
        if (p == '/') return mountPrefix;
        return '$mountPrefix$p';
      }).toList();
    });
  }

  @override
  Result<Stream<Scroll>> watch(String pattern) {
    if (_closed) return const Err(ClosedError());

    final resolved = _resolve(pattern);
    if (resolved.isErr) return Err(resolved.errorOrNull!);

    final (ns, stripped) = resolved.value;
    final result = ns.watch(stripped);

    if (result.isErr) return result;

    // Create controller to translate paths back
    ///
    /// ## Dart Lesson: StreamController
    ///
    /// StreamController is the bridge between imperative and reactive code.
    /// `onCancel` is called when the last listener unsubscribes.
    late StreamController<Scroll> controller;
    StreamSubscription<Scroll>? subscription;

    controller = StreamController<Scroll>(
      onListen: () {
        // Subscribe to upstream when first listener attaches
        subscription = result.value.listen(
          (scroll) {
            // Translate path back
            final translatedKey = _translatePathBack(
              scroll.key,
              pattern,
              stripped,
            );
            controller.add(scroll.copyWith(key: translatedKey));
          },
          onError: controller.addError,
          onDone: controller.close,
        );
      },
      onCancel: () {
        subscription?.cancel();
      },
    );

    _watchControllers.add(_KernelWatcher(controller: controller));
    return Ok(controller.stream);
  }

  /// Translate a path from namespace-relative back to absolute
  String _translatePathBack(String scrollKey, String pattern, String stripped) {
    if (stripped == '/') {
      // Root mount - prepend pattern prefix
      final prefix = pattern
          .replaceAll('/**', '')
          .replaceAll('/*', '');
      return '$prefix$scrollKey';
    } else {
      // Calculate mount prefix
      final mountPrefix = pattern.substring(
        0,
        pattern.length - stripped.length,
      );
      if (scrollKey == '/') return mountPrefix;
      return '$mountPrefix$scrollKey';
    }
  }

  @override
  Result<void> close() {
    _closed = true;

    // Close all watch controllers
    for (final watcher in _watchControllers) {
      watcher.controller.close();
    }
    _watchControllers.clear();

    // Close all mounted namespaces
    for (final ns in _mounts.values) {
      ns.close();
    }

    return const Ok(null);
  }
}

/// Internal watcher state with GC-aware cleanup for Kernel
///
/// See MemoryNamespace for detailed explanation of the WeakReference pattern.
class _KernelWatcher {
  final StreamController<Scroll> controller;

  /// Weak reference to the stream returned to user
  final WeakReference<Stream<Scroll>> streamRef;

  _KernelWatcher({required this.controller})
      : streamRef = WeakReference(controller.stream);

  /// Check if this watcher is still alive
  bool get isDead => controller.isClosed || streamRef.target == null;
}
