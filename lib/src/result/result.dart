/// Result - Unified Error Handling
///
/// A single Result type for all 9S operations.
/// Parameterized by both success type T and error type E.
///
/// ## Philosophy
///
/// "One Form, many instances."
///
/// Rather than three separate Result hierarchies (NineResult, PatchResult,
/// SealResult), we have one generic Result that works with any error type.
///
/// ## Dart Lesson: Two Type Parameters
///
/// `Result<T, E>` takes two type parameters:
/// - T: The success value type
/// - E: The error type (defaults to Exception)
///
/// This enables type-safe error handling across different domains
/// while maintaining a unified API.
///
/// ## Usage
///
/// ```dart
/// // With default error type
/// Result<int> divide(int a, int b) {
///   if (b == 0) return Err(Exception('divide by zero'));
///   return Ok(a ~/ b);
/// }
///
/// // With specific error type
/// Result<Scroll, NineError> read(String path) { ... }
/// Result<Scroll, PatchError> apply(Patch p) { ... }
///
/// // Pattern matching
/// switch (result) {
///   case Ok(:final value): print(value);
///   case Err(:final error): print(error);
/// }
/// ```
library;

/// Result type for operations that can fail
///
/// Sealed class enables exhaustive pattern matching.
sealed class Result<T, E extends Object> {
  const Result();

  /// True if operation succeeded
  bool get isOk => this is Ok<T, E>;

  /// True if operation failed
  bool get isErr => this is Err<T, E>;

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
  E? get errorOrNull {
    return switch (this) {
      Ok() => null,
      Err(:final error) => error,
    };
  }

  /// Map the success value
  Result<U, E> map<U>(U Function(T) f) {
    return switch (this) {
      Ok(:final value) => Ok(f(value)),
      Err(:final error) => Err(error),
    };
  }

  /// Map the error value
  Result<T, F> mapErr<F extends Object>(F Function(E) f) {
    return switch (this) {
      Ok(:final value) => Ok(value),
      Err(:final error) => Err(f(error)),
    };
  }

  /// Chain operations that return Result
  Result<U, E> flatMap<U>(Result<U, E> Function(T) f) {
    return switch (this) {
      Ok(:final value) => f(value),
      Err(:final error) => Err(error),
    };
  }

  /// Get value or default
  T getOr(T defaultValue) {
    return switch (this) {
      Ok(:final value) => value,
      Err() => defaultValue,
    };
  }

  /// Get value or compute default
  T getOrElse(T Function() f) {
    return switch (this) {
      Ok(:final value) => value,
      Err() => f(),
    };
  }
}

/// Success case
class Ok<T, E extends Object> extends Result<T, E> {
  @override
  final T value;
  const Ok(this.value);

  @override
  String toString() => 'Ok($value)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Ok<T, E> && other.value == value);

  @override
  int get hashCode => value.hashCode;
}

/// Error case
class Err<T, E extends Object> extends Result<T, E> {
  final E error;
  const Err(this.error);

  @override
  String toString() => 'Err($error)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Err<T, E> && other.error == error);

  @override
  int get hashCode => error.hashCode;
}

/// Convenience extension to create Ok from any value
extension ResultOkExtension<T> on T {
  Result<T, E> ok<E extends Object>() => Ok(this);
}

/// Convenience extension to create Err from any error
extension ResultErrExtension<E extends Object> on E {
  Result<T, E> err<T>() => Err<T, E>(this);
}
