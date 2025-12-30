/// Result - Monadic Error Handling
///
/// A Result type that captures either success (Ok) or failure (Err).
/// This eliminates the need for exception handling and makes errors
/// explicit in function signatures.
///
/// ## Platonic Form: Either Monad
///
/// Result is the Dart incarnation of the Either monad from functional programming:
/// - `Ok<T>` ≈ `Right<T>` (success path)
/// - `Err<T>` ≈ `Left<E>` (error path)
///
/// ## Dart Lesson: Sealed Classes for ADTs
///
/// Dart 3.0's sealed classes enable exhaustive pattern matching.
/// The compiler knows all subtypes and warns if you miss a case:
///
/// ```dart
/// switch (result) {
///   case Ok(:final value): print('Success: $value');
///   case Err(:final error): print('Error: $error');
/// }
/// ```
///
/// ## Usage
///
/// ```dart
/// Result<int, String> divide(int a, int b) {
///   if (b == 0) return Err('Division by zero');
///   return Ok(a ~/ b);
/// }
///
/// final result = divide(10, 2);
/// print(result.isOk);     // true
/// print(result.value);    // 5
/// print(result.unwrap()); // 5
/// ```
///
/// ## Why Not Exceptions?
///
/// 1. **Explicit**: Error cases are visible in the type signature
/// 2. **Exhaustive**: Compiler ensures you handle all cases
/// 3. **Composable**: Chain operations with map/flatMap
/// 4. **Predictable**: No hidden control flow jumps
library;

/// Base Result type - either Ok or Err
///
/// ## Dart Lesson: Sealed Classes
///
/// `sealed` means:
/// 1. Cannot be extended outside this library
/// 2. Compiler knows all subtypes
/// 3. Enables exhaustive pattern matching
sealed class Result<T, E> {
  const Result();

  /// Check if this is a success
  bool get isOk;

  /// Check if this is an error
  bool get isErr => !isOk;

  /// Get the success value (null if error)
  T? get value;

  /// Get the error (null if success)
  E? get error;

  /// Get value or throw the error
  ///
  /// ## Dart Lesson: Never Type
  ///
  /// When an error is thrown, control never returns.
  /// Dart's type system understands this through the `Never` type.
  T unwrap() {
    switch (this) {
      case Ok(:final value):
        return value;
      case Err(:final error):
        throw error as Object;
    }
  }

  /// Get value or return default
  T unwrapOr(T defaultValue) {
    return switch (this) {
      Ok(:final value) => value,
      Err() => defaultValue,
    };
  }

  /// Transform the success value
  ///
  /// ## Dart Lesson: Higher-Order Functions
  ///
  /// `map` takes a function and applies it to the value inside Result.
  /// This is the functor pattern - transforming values in context.
  Result<U, E> map<U>(U Function(T) f) {
    return switch (this) {
      Ok(:final value) => Ok(f(value)),
      Err(:final error) => Err(error),
    };
  }

  /// Transform the error
  Result<T, F> mapErr<F>(F Function(E) f) {
    return switch (this) {
      Ok(:final value) => Ok(value),
      Err(:final error) => Err(f(error)),
    };
  }

  /// Chain operations that may fail
  ///
  /// ## Dart Lesson: Monadic Bind
  ///
  /// `flatMap` (also called `andThen` or `>>=`) lets you chain
  /// operations that each return a Result. If any step fails,
  /// the chain short-circuits.
  ///
  /// ```dart
  /// parseNumber(input)
  ///   .flatMap((n) => validateRange(n))
  ///   .flatMap((n) => process(n));
  /// ```
  Result<U, E> flatMap<U>(Result<U, E> Function(T) f) {
    return switch (this) {
      Ok(:final value) => f(value),
      Err(:final error) => Err(error),
    };
  }

  /// Execute a function for its side effects
  Result<T, E> inspect(void Function(T) f) {
    if (this case Ok(:final value)) {
      f(value);
    }
    return this;
  }

  /// Execute a function on error for its side effects
  Result<T, E> inspectErr(void Function(E) f) {
    if (this case Err(:final error)) {
      f(error);
    }
    return this;
  }
}

/// Success case
class Ok<T, E> extends Result<T, E> {
  @override
  final T value;

  const Ok(this.value);

  @override
  bool get isOk => true;

  @override
  E? get error => null;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Ok<T, E> && other.value == value;
  }

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'Ok($value)';
}

/// Error case
class Err<T, E> extends Result<T, E> {
  @override
  final E error;

  const Err(this.error);

  @override
  bool get isOk => false;

  @override
  T? get value => null;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Err<T, E> && other.error == error;
  }

  @override
  int get hashCode => error.hashCode;

  @override
  String toString() => 'Err($error)';
}

// ============================================================================
// Convenience Type Aliases
// ============================================================================

/// Result with a 9S error
typedef NineResult<T> = Result<T, NineError>;

// ============================================================================
// Base Error Type
// ============================================================================

/// Base error type for 9S operations
///
/// All 9S errors derive from this sealed class.
/// Using sealed ensures exhaustive matching.
sealed class NineError implements Exception {
  final String message;
  const NineError(this.message);

  @override
  String toString() => '$runtimeType: $message';
}

/// Path not found
class NotFoundError extends NineError {
  const NotFoundError(super.message);
}

/// Invalid path format
class InvalidPathError extends NineError {
  const InvalidPathError(super.message);
}

/// Namespace is closed
class ClosedError extends NineError {
  const ClosedError([super.message = 'Namespace is closed']);
}

/// Resource temporarily unavailable
class UnavailableError extends NineError {
  const UnavailableError(super.message);
}

/// Internal error
class InternalError extends NineError {
  const InternalError(super.message);
}

/// Permission denied
class PermissionError extends NineError {
  const PermissionError(super.message);
}
