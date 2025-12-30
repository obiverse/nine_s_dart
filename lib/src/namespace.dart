/// Namespace - The Universal Interface
///
/// "Five operations. Frozen. Never a sixth."
/// - Ken Thompson: "Simplicity is the ultimate sophistication."
/// - SICP: "Data abstraction - Use ≠ Representation"
///
/// ## Dart Lesson: Abstract Interface Classes
///
/// Dart 3.0 introduced `interface class` and `abstract interface class`:
///
/// - `abstract class` - Can have implementations, can be extended
/// - `interface class` - Has implementations, can only be implemented (not extended)
/// - `abstract interface class` - No implementations, can only be implemented
///
/// Namespace is `abstract interface class` because:
/// 1. It defines a contract (pure interface)
/// 2. Implementations provide behavior
/// 3. You can't "extend" a namespace - you implement it
///
/// This is the Kantian categorical imperative: "Code as if your pattern
/// were universal law." Every namespace must follow this interface exactly.
library;

import 'scroll.dart';

/// Error types for 9S operations
///
/// ## Dart Lesson: sealed Classes
///
/// `sealed` means this class can only be extended/implemented in this file.
/// This enables exhaustive pattern matching - the compiler knows all subtypes.
///
/// ```dart
/// switch (error) {
///   case NotFoundError(): ...
///   case InvalidPathError(): ...
///   // Compiler warns if cases are missing
/// }
/// ```
sealed class NineError implements Exception {
  final String message;
  const NineError(this.message);

  @override
  String toString() => '$runtimeType: $message';
}

/// Path not found (NOT always an error - read returns null instead)
class NotFoundError extends NineError {
  const NotFoundError(super.message);
}

/// Invalid path syntax
class InvalidPathError extends NineError {
  const InvalidPathError(super.message);
}

/// Invalid data payload
class InvalidDataError extends NineError {
  const InvalidDataError(super.message);
}

/// Permission denied
class PermissionError extends NineError {
  const PermissionError(super.message);
}

/// Namespace is closed
class ClosedError extends NineError {
  const ClosedError() : super('namespace is closed');
}

/// Operation timed out
class TimeoutError extends NineError {
  const TimeoutError() : super('operation timed out');
}

/// Connection failed
class ConnectionError extends NineError {
  const ConnectionError(super.message);
}

/// Service unavailable
class UnavailableError extends NineError {
  const UnavailableError(super.message);
}

/// Internal error
class InternalError extends NineError {
  const InternalError(super.message);
}

/// Result type for namespace operations
///
/// ## Dart Lesson: Result Types vs Exceptions
///
/// Dart uses exceptions for error handling, but Result types are clearer:
///
/// ```dart
/// // Exception style
/// try {
///   final scroll = ns.read('/path');
/// } on NotFoundError catch (e) {
///   // handle
/// }
///
/// // Result style (what we use)
/// final result = ns.read('/path');
/// switch (result) {
///   case Ok(:final value): print(value);
///   case Err(:final error): print(error);
/// }
/// ```
///
/// Result types make errors explicit in the type signature.
sealed class Result<T> {
  const Result();

  /// True if operation succeeded
  bool get isOk => this is Ok<T>;

  /// True if operation failed
  bool get isErr => this is Err<T>;

  /// Get value or throw if error
  T get value {
    return switch (this) {
      Ok(:final value) => value,
      Err(:final error) => throw error,
    };
  }

  /// Get value or null if error
  T? get valueOrNull {
    return switch (this) {
      Ok(:final value) => value,
      Err() => null,
    };
  }

  /// Get error or null if success
  NineError? get errorOrNull {
    return switch (this) {
      Ok() => null,
      Err(:final error) => error,
    };
  }

  /// Map the success value
  Result<U> map<U>(U Function(T) f) {
    return switch (this) {
      Ok(:final value) => Ok(f(value)),
      Err(:final error) => Err(error),
    };
  }

  /// Chain operations that return Result
  Result<U> flatMap<U>(Result<U> Function(T) f) {
    return switch (this) {
      Ok(:final value) => f(value),
      Err(:final error) => Err(error),
    };
  }
}

/// Success case
class Ok<T> extends Result<T> {
  @override
  final T value;
  const Ok(this.value);

  @override
  String toString() => 'Ok($value)';
}

/// Error case
class Err<T> extends Result<T> {
  final NineError error;
  const Err(this.error);

  @override
  String toString() => 'Err($error)';
}

/// Convenience constructors
extension ResultExtensions<T> on T {
  Result<T> get ok => Ok(this);
}

extension NineErrorExtensions on NineError {
  Result<T> err<T>() => Err<T>(this);
}

/// Namespace - The 5 frozen operations
///
/// All functionality in 9S emerges from these five operations.
/// Extensions are new Namespace implementations, not new operations.
///
/// "Five operations. Frozen. Never a sixth."
///
/// ## Design Decision: Synchronous Interface
///
/// This interface is deliberately synchronous. This is a conscious choice:
///
/// **Rationale:**
/// 1. Local storage (memory, file, encrypted store) is inherently fast
/// 2. Synchronous code is simpler to reason about
/// 3. No async overhead for hot paths
/// 4. Composition via Kernel is straightforward
///
/// **For Network Backends:**
/// If you need async operations (e.g., networked storage, remote namespaces),
/// create a separate `AsyncNamespace` interface with `Future<Result<T>>` returns.
/// Use adapters to bridge between sync and async worlds:
///
/// ```dart
/// /// Adapter: wrap async namespace for sync consumption (with caching)
/// class CachedAsyncNamespace implements Namespace {
///   final AsyncNamespace _remote;
///   final MemoryNamespace _cache;
///   // Sync reads from cache, async sync in background
/// }
/// ```
///
/// This follows the principle: "Extensions come from new Namespace
/// implementations, never new operations." An async interface is a new
/// implementation pattern, not a new operation.
abstract interface class Namespace {
  /// Read a scroll by path
  ///
  /// Returns `Ok(scroll)` if found, `Ok(null)` if not found.
  /// Returns `Err` on failure (permission, I/O, connection, etc.)
  ///
  /// ## Why null instead of NotFoundError?
  ///
  /// Not-found is a valid result, not an error. You're asking
  /// "what's at this path?" and "nothing" is a valid answer.
  Result<Scroll?> read(String path);

  /// Write data at a path
  ///
  /// Creates or updates the Scroll at path.
  /// Returns the written Scroll with computed metadata (hash, version, time).
  Result<Scroll> write(String path, Map<String, dynamic> data);

  /// Write a full scroll (with type hint)
  ///
  /// The type in scroll is preserved.
  /// Hash, version, and time are computed by the namespace.
  Result<Scroll> writeScroll(Scroll scroll);

  /// List all paths under a prefix
  ///
  /// Returns empty list if no matches (NOT an error).
  Result<List<String>> list(String prefix);

  /// Watch for changes matching a pattern
  ///
  /// Returns a stream that emits Scrolls when matching paths change.
  /// Supports glob patterns: * (single segment), ** (any suffix)
  ///
  /// ## Dart Lesson: Streams
  ///
  /// Streams are Dart's async iteration primitive:
  ///
  /// ```dart
  /// final stream = ns.watch('/wallet/**');
  /// await for (final scroll in stream.value) {
  ///   print('Changed: ${scroll.key}');
  /// }
  /// ```
  ///
  /// Unlike Rust channels, Dart streams are lazy (nothing happens until listen).
  Result<Stream<Scroll>> watch(String pattern);

  /// Close the namespace and release resources
  ///
  /// Cancels all active watches (streams close).
  /// Subsequent operations return `Err(ClosedError())`.
  /// Idempotent - safe to call multiple times.
  Result<void> close();
}

// ============================================================================
// Path Utilities
// ============================================================================

/// Validate path syntax per 9S spec
///
/// ## Security
/// - Rejects path traversal attempts (`..` and `.` segments)
/// - Only allows alphanumeric, underscore, hyphen, and dot (within names)
/// - Glob wildcards (`*`) only allowed at end for watch patterns
///
/// ## Dart Lesson: RegExp
///
/// Dart uses Perl-style regex. The `r''` prefix creates a raw string
/// (no escape processing), which is cleaner for regex patterns.
Result<void> validatePath(String path) {
  if (path.isEmpty) {
    return const Err(InvalidPathError('path cannot be empty'));
  }

  if (!path.startsWith('/')) {
    return const Err(InvalidPathError('path must start with /'));
  }

  // Allow root path
  if (path == '/') return const Ok(null);

  // Check segments
  final segments = path.split('/').skip(1); // Skip empty first segment

  for (final segment in segments) {
    if (segment.isEmpty) continue; // Allow trailing slash

    // SECURITY: Reject path traversal
    if (segment == '.' || segment == '..') {
      return const Err(
        InvalidPathError('path traversal not allowed (. or .. segments)'),
      );
    }

    // Validate characters
    for (final char in segment.codeUnits) {
      final c = String.fromCharCode(char);
      final isValid = _isAlphanumeric(char) ||
          c == '_' ||
          c == '.' ||
          c == '-' ||
          c == '*';
      if (!isValid) {
        return Err(InvalidPathError("invalid character '$c' in path"));
      }
    }
  }

  return const Ok(null);
}

bool _isAlphanumeric(int codeUnit) {
  return (codeUnit >= 48 && codeUnit <= 57) || // 0-9
      (codeUnit >= 65 && codeUnit <= 90) || // A-Z
      (codeUnit >= 97 && codeUnit <= 122); // a-z
}

/// Check if a path matches a pattern (supports * and **)
///
/// ## Pattern Matching Rules
/// - Exact match: `/foo` matches `/foo`
/// - Single wildcard: `/foo/*` matches `/foo/bar` but not `/foo/bar/baz`
/// - Recursive wildcard: `/foo/**` matches `/foo/bar`, `/foo/bar/baz`, etc.
bool pathMatches(String path, String pattern) {
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

/// Check if path is under prefix on segment boundaries
///
/// ## Security
/// This prevents `/wallet/user` from matching `/wallet/user_archive`.
bool isPathUnderPrefix(String path, String prefix) {
  if (prefix == '/') return path.startsWith('/');
  if (path == prefix) return true;

  // Check for segment boundary
  if (path.startsWith(prefix)) {
    final remainder = path.substring(prefix.length);
    return remainder.startsWith('/');
  }

  return false;
}

/// Normalize a mount path
///
/// - Ensures path starts with '/'
/// - Removes trailing slashes (except for root "/")
String normalizeMountPath(String path) {
  var normalized = path;

  // Ensure starts with /
  if (!normalized.startsWith('/')) {
    normalized = '/$normalized';
  }

  // Remove trailing slashes (except for root)
  while (normalized.length > 1 && normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }

  return normalized;
}
