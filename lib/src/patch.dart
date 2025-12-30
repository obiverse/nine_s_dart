/// Patch - Git-like Diff Primitives for Scrolls
///
/// Pure functions for computing and applying patches between scroll states.
/// No storage, no policy - just transformations.
///
/// ## RFC 6902 JSON Patch
///
/// Patches follow the RFC 6902 standard:
/// - `add` - Insert value at JSON pointer path
/// - `remove` - Delete value at path
/// - `replace` - Change value at path
/// - `move` - Relocate value from one path to another
/// - `copy` - Duplicate value
/// - `test` - Assert value equals expected (conditional)
///
/// ## CSP Insight (Tony Hoare)
///
/// The `seq` number is derived from the **filesystem state**, not memory.
/// The patches directory IS the monotonic counter. This enables:
/// - Multi-process safety without locks
/// - Crash recovery by reading state
/// - CSP-style message ordering
///
/// ## Dart Lesson: Sealed Union Types
///
/// Dart 3.0's sealed classes enable exhaustive pattern matching.
/// `PatchOp` is a sealed class with fixed subclasses - the compiler
/// knows all cases and warns if you miss one in a switch.
library;

import 'scroll.dart';
import 'utils.dart' show deepEquals, deepCopyMap;

/// A single JSON Patch operation (RFC 6902)
///
/// ## Dart Lesson: Sealed Classes as ADTs
///
/// In functional languages, this would be an Algebraic Data Type.
/// Dart's sealed classes achieve the same thing:
///
/// ```dart
/// switch (op) {
///   case AddOp(:final path, :final value): ...
///   case RemoveOp(:final path): ...
///   // Compiler ensures all cases handled
/// }
/// ```
sealed class PatchOp {
  const PatchOp();

  /// Convert to JSON map
  Map<String, dynamic> toJson();

  /// Parse from JSON
  static PatchOp fromJson(Map<String, dynamic> json) {
    final op = json['op'] as String;
    return switch (op) {
      'add' => AddOp(
          path: json['path'] as String,
          value: json['value'],
        ),
      'remove' => RemoveOp(path: json['path'] as String),
      'replace' => ReplaceOp(
          path: json['path'] as String,
          value: json['value'],
        ),
      'move' => MoveOp(
          from: json['from'] as String,
          path: json['path'] as String,
        ),
      'copy' => CopyOp(
          from: json['from'] as String,
          path: json['path'] as String,
        ),
      'test' => TestOp(
          path: json['path'] as String,
          value: json['value'],
        ),
      _ => throw ArgumentError('Unknown patch op: $op'),
    };
  }
}

/// Add a value at a path
class AddOp extends PatchOp {
  final String path;
  final dynamic value;

  const AddOp({required this.path, required this.value});

  @override
  Map<String, dynamic> toJson() => {'op': 'add', 'path': path, 'value': value};
}

/// Remove a value at a path
class RemoveOp extends PatchOp {
  final String path;

  const RemoveOp({required this.path});

  @override
  Map<String, dynamic> toJson() => {'op': 'remove', 'path': path};
}

/// Replace a value at a path
class ReplaceOp extends PatchOp {
  final String path;
  final dynamic value;

  const ReplaceOp({required this.path, required this.value});

  @override
  Map<String, dynamic> toJson() =>
      {'op': 'replace', 'path': path, 'value': value};
}

/// Move a value from one path to another
class MoveOp extends PatchOp {
  final String from;
  final String path;

  const MoveOp({required this.from, required this.path});

  @override
  Map<String, dynamic> toJson() => {'op': 'move', 'from': from, 'path': path};
}

/// Copy a value from one path to another
class CopyOp extends PatchOp {
  final String from;
  final String path;

  const CopyOp({required this.from, required this.path});

  @override
  Map<String, dynamic> toJson() => {'op': 'copy', 'from': from, 'path': path};
}

/// Test that a value equals expected (conditional patch)
class TestOp extends PatchOp {
  final String path;
  final dynamic value;

  const TestOp({required this.path, required this.value});

  @override
  Map<String, dynamic> toJson() => {'op': 'test', 'path': path, 'value': value};
}

/// A patch representing a change to a Scroll
///
/// Patches are the unit of change in the git-like storage layer.
/// They record what changed, when, and form a hash chain for integrity.
class Patch {
  /// The scroll path being patched
  final String key;

  /// JSON Patch operations (RFC 6902)
  final List<PatchOp> ops;

  /// Hash of the state before this patch (null for create/genesis)
  final String? parent;

  /// Hash of the state after this patch
  final String hash;

  /// When the patch was created (Unix millis)
  final int timestamp;

  /// Patch sequence number (for ordering)
  final int seq;

  const Patch({
    required this.key,
    required this.ops,
    this.parent,
    required this.hash,
    required this.timestamp,
    required this.seq,
  });

  /// Convert to JSON
  Map<String, dynamic> toJson() => {
        'key': key,
        'ops': ops.map((op) => op.toJson()).toList(),
        if (parent != null) 'parent': parent,
        'hash': hash,
        'timestamp': timestamp,
        'seq': seq,
      };

  /// Parse from JSON
  factory Patch.fromJson(Map<String, dynamic> json) {
    final opsList = json['ops'] as List;
    return Patch(
      key: json['key'] as String,
      ops: opsList
          .map((op) => PatchOp.fromJson(op as Map<String, dynamic>))
          .toList(),
      parent: json['parent'] as String?,
      hash: json['hash'] as String,
      timestamp: json['timestamp'] as int,
      seq: json['seq'] as int,
    );
  }

  /// Copy with modifications
  Patch copyWith({
    String? key,
    List<PatchOp>? ops,
    String? parent,
    String? hash,
    int? timestamp,
    int? seq,
  }) {
    return Patch(
      key: key ?? this.key,
      ops: ops ?? this.ops,
      parent: parent ?? this.parent,
      hash: hash ?? this.hash,
      timestamp: timestamp ?? this.timestamp,
      seq: seq ?? this.seq,
    );
  }
}

/// Patch errors
sealed class PatchError {
  final String message;
  const PatchError(this.message);

  @override
  String toString() => '$runtimeType: $message';
}

/// Path not found when applying operation
class PathNotFoundError extends PatchError {
  const PathNotFoundError(super.message);
}

/// Type mismatch during operation
class TypeMismatchError extends PatchError {
  const TypeMismatchError(super.message);
}

/// Test operation failed
class TestFailedError extends PatchError {
  const TestFailedError(super.message);
}

/// Invalid JSON pointer
class InvalidPointerError extends PatchError {
  const InvalidPointerError(super.message);
}

/// Result type for patch operations
sealed class PatchResult<T> {
  const PatchResult();
}

class PatchOk<T> extends PatchResult<T> {
  final T value;
  const PatchOk(this.value);
}

class PatchErr<T> extends PatchResult<T> {
  final PatchError error;
  const PatchErr(this.error);
}

// ============================================================================
// Pure Diff Functions
// ============================================================================

/// Compute a patch from old state to new state
///
/// If `old` is null, this is a create operation (genesis).
/// The patch records all operations needed to transform old → new.
Patch createPatch(String key, Scroll? old, Scroll current) {
  final parent = old?.computeHash();
  final ops = _computeOps(old?.data, current.data);
  final seq = old != null ? old.metadata.version + 1 : 1;

  return Patch(
    key: key,
    ops: ops,
    parent: parent,
    hash: current.computeHash(),
    timestamp: DateTime.now().millisecondsSinceEpoch,
    seq: seq,
  );
}

/// Apply a patch to a scroll, producing new state
///
/// Returns error if any operation fails.
PatchResult<Scroll> applyPatch(Scroll scroll, Patch patch) {
  var newData = Map<String, dynamic>.from(scroll.data);

  for (final op in patch.ops) {
    final result = _applyOp(newData, op);
    if (result is PatchErr) {
      return PatchErr((result as PatchErr).error);
    }
    newData = (result as PatchOk<Map<String, dynamic>>).value;
  }

  final result = Scroll(
    key: scroll.key,
    type_: scroll.type_,
    data: newData,
    metadata: scroll.metadata.copyWith(version: patch.seq),
  );

  return PatchOk(result);
}

/// Verify a patch's hash chain
///
/// Checks that the parent hash matches the old state.
bool verifyPatch(Scroll? old, Patch patch) {
  final oldHash = old?.computeHash();

  // For genesis patch, parent should be null
  if (old == null && patch.parent == null) return true;

  // For update patch, parent should match old hash
  if (old != null && patch.parent == oldHash) return true;

  return false;
}

// ============================================================================
// Internal: JSON Diff Algorithm
// ============================================================================

/// Compute JSON patch operations from old to new value
List<PatchOp> _computeOps(Map<String, dynamic>? old, Map<String, dynamic> current) {
  if (old == null) {
    // Create: entire new value is a "replace" at root
    return [ReplaceOp(path: '', value: current)];
  }

  return _computeDiff('', old, current);
}

/// Recursive diff between two JSON values
List<PatchOp> _computeDiff(
  String path,
  dynamic old,
  dynamic current,
) {
  final ops = <PatchOp>[];

  // Both objects: diff keys
  if (old is Map<String, dynamic> && current is Map<String, dynamic>) {
    // Removed keys
    for (final key in old.keys) {
      if (!current.containsKey(key)) {
        ops.add(RemoveOp(path: _jsonPointer(path, key)));
      }
    }

    // Added or changed keys
    for (final entry in current.entries) {
      final key = entry.key;
      final newVal = entry.value;
      final keyPath = _jsonPointer(path, key);

      if (!old.containsKey(key)) {
        ops.add(AddOp(path: keyPath, value: newVal));
      } else if (!deepEquals(old[key], newVal)) {
        // Recurse for nested changes
        ops.addAll(_computeDiff(keyPath, old[key], newVal));
      }
    }
  }
  // Both arrays: simplified diff (replace if different)
  else if (old is List && current is List) {
    if (!deepEquals(old, current)) {
      ops.add(ReplaceOp(path: path, value: current));
    }
  }
  // Different types or primitives: replace
  else if (!deepEquals(old, current)) {
    ops.add(ReplaceOp(path: path, value: current));
  }

  return ops;
}

/// Build JSON pointer path (RFC 6901)
String _jsonPointer(String base, String key) {
  // Escape ~ and / in key
  final escaped = key.replaceAll('~', '~0').replaceAll('/', '~1');
  return '$base/$escaped';
}

/// Apply a single patch operation to a value
PatchResult<Map<String, dynamic>> _applyOp(Map<String, dynamic> data, PatchOp op) {
  try {
    switch (op) {
      case AddOp(:final path, :final value):
        return PatchOk(_setAtPointer(data, path, value, mustExist: false));
      case RemoveOp(:final path):
        return PatchOk(_removeAtPointer(data, path).$1);
      case ReplaceOp(:final path, :final value):
        return PatchOk(_setAtPointer(data, path, value, mustExist: true));
      case MoveOp(:final from, :final path):
        final (newData, removed) = _removeAtPointer(data, from);
        return PatchOk(_setAtPointer(newData, path, removed, mustExist: false));
      case CopyOp(:final from, :final path):
        final value = _getAtPointer(data, from);
        return PatchOk(_setAtPointer(data, path, value, mustExist: false));
      case TestOp(:final path, :final value):
        final actual = _getAtPointer(data, path);
        if (!deepEquals(actual, value)) {
          return PatchErr(TestFailedError('expected $value, got $actual'));
        }
        return PatchOk(data);
    }
  } on PatchError catch (e) {
    return PatchErr(e);
  }
}

/// Get value at JSON pointer path
dynamic _getAtPointer(Map<String, dynamic> data, String pointer) {
  if (pointer.isEmpty) return data;

  final parts = _parsePointer(pointer);
  dynamic current = data;

  for (final part in parts) {
    if (current is Map<String, dynamic>) {
      if (!current.containsKey(part)) {
        throw PathNotFoundError(pointer);
      }
      current = current[part];
    } else if (current is List) {
      final idx = int.tryParse(part);
      if (idx == null || idx < 0 || idx >= current.length) {
        throw PathNotFoundError(pointer);
      }
      current = current[idx];
    } else {
      throw TypeMismatchError(pointer);
    }
  }

  return current;
}

/// Set value at JSON pointer path
Map<String, dynamic> _setAtPointer(
  Map<String, dynamic> data,
  String pointer,
  dynamic value, {
  required bool mustExist,
}) {
  if (pointer.isEmpty) {
    if (value is Map<String, dynamic>) return value;
    throw const TypeMismatchError('Cannot replace root with non-object');
  }

  // Deep copy the data
  final newData = deepCopyMap(data);
  final parts = _parsePointer(pointer);
  final last = parts.removeLast();

  dynamic current = newData;

  for (final part in parts) {
    if (current is Map<String, dynamic>) {
      current.putIfAbsent(part, () => <String, dynamic>{});
      current = current[part];
    } else if (current is List) {
      final idx = int.tryParse(part);
      if (idx == null || idx < 0 || idx >= current.length) {
        throw PathNotFoundError(pointer);
      }
      current = current[idx];
    } else {
      throw TypeMismatchError(pointer);
    }
  }

  if (current is Map<String, dynamic>) {
    if (mustExist && !current.containsKey(last)) {
      throw PathNotFoundError(pointer);
    }
    current[last] = value;
  } else if (current is List) {
    if (last == '-') {
      current.add(value);
    } else {
      final idx = int.tryParse(last);
      if (idx == null || idx < 0 || idx >= current.length) {
        throw PathNotFoundError(pointer);
      }
      current[idx] = value;
    }
  } else {
    throw TypeMismatchError(pointer);
  }

  return newData;
}

/// Remove value at JSON pointer path, returning new data and removed value
(Map<String, dynamic>, dynamic) _removeAtPointer(
  Map<String, dynamic> data,
  String pointer,
) {
  if (pointer.isEmpty) {
    throw const InvalidPointerError('cannot remove root');
  }

  final newData = deepCopyMap(data);
  final parts = _parsePointer(pointer);
  final last = parts.removeLast();

  dynamic current = newData;

  for (final part in parts) {
    if (current is Map<String, dynamic>) {
      if (!current.containsKey(part)) {
        throw PathNotFoundError(pointer);
      }
      current = current[part];
    } else if (current is List) {
      final idx = int.tryParse(part);
      if (idx == null || idx < 0 || idx >= current.length) {
        throw PathNotFoundError(pointer);
      }
      current = current[idx];
    } else {
      throw TypeMismatchError(pointer);
    }
  }

  dynamic removed;
  if (current is Map<String, dynamic>) {
    if (!current.containsKey(last)) {
      throw PathNotFoundError(pointer);
    }
    removed = current.remove(last);
  } else if (current is List) {
    final idx = int.tryParse(last);
    if (idx == null || idx < 0 || idx >= current.length) {
      throw PathNotFoundError(pointer);
    }
    removed = current.removeAt(idx);
  } else {
    throw TypeMismatchError(pointer);
  }

  return (newData, removed);
}

/// Parse JSON pointer into path segments
List<String> _parsePointer(String pointer) {
  if (!pointer.startsWith('/')) {
    throw InvalidPointerError(pointer);
  }

  return pointer
      .substring(1)
      .split('/')
      .map((s) => s.replaceAll('~1', '/').replaceAll('~0', '~'))
      .toList();
}
