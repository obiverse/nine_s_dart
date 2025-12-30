/// Scroll - The Universal Data Envelope
///
/// "Everything flows through Scrolls. No parallel type systems."
///
/// A Scroll is the atom of 9S - every piece of data wrapped in semantic context.
/// The key encodes ontology (where), type_ declares schema (what kind),
/// metadata provides semantics (who/when/why), and data holds the payload.
///
/// ## Dart Lesson: Classes and Named Parameters
///
/// Dart classes use `{}` for optional named parameters with defaults.
/// This makes construction self-documenting:
///
/// ```dart
/// final scroll = Scroll(
///   key: '/wallet/balance',
///   data: {'confirmed': 100000},
///   type_: 'wallet/balance@v1',  // Optional, defaults to generic
/// );
/// ```
///
/// Compare to positional: `Scroll('/wallet/balance', {...}, 'wallet/balance@v1')`
/// Named parameters win for readability.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'metadata.dart';

export 'metadata.dart';

/// Well-known scroll types
abstract final class ScrollTypes {
  static const generic = 'scroll/generic@v1';
  static const blob = 'scroll/blob@v1';
  static const ref = 'scroll/ref@v1';
  static const access = 'scroll/access@v1';
  static const notify = 'scroll/notify@v1';
  static const ack = 'scroll/ack@v1';

  // Vault
  static const note = 'vault/note@v1';
  static const sealedNote = 'vault/sealed-note@v1';

  // Wallet
  static const balance = 'wallet/balance@v1';
  static const tx = 'wallet/tx@v1';
  static const utxo = 'wallet/utxo@v1';

  // Lightning
  static const lnStatus = 'ln/status@v1';
  static const lnBalance = 'ln/balance@v1';
  static const lnInvoice = 'ln/invoice@v1';
  static const lnPayment = 'ln/payment@v1';
}

/// Scroll - The universal data envelope in 9S
///
/// ## Dart Lesson: final vs const
///
/// - `final`: Set once at runtime, cannot be reassigned
/// - `const`: Compile-time constant, deeply immutable
///
/// Scroll fields are `final` because their values come at runtime.
/// We use `const` constructors where possible for compile-time optimization.
class Scroll {
  /// Unique address (encoded ontology)
  /// Examples: "/vault/notes/abc123", "/ln/balance", "/wallet/txs/xyz"
  final String key;

  /// Schema hint: "domain/entity@version"
  /// Examples: "vault/note@v1", "ln/balance@v1", "wallet/tx@v1"
  final String type_;

  /// Semantic metadata + timestamps
  final Metadata metadata;

  /// Payload (opaque to Kernel)
  /// The Kernel stores and retrieves this; never interprets it.
  final Map<String, dynamic> data;

  /// Primary constructor with named parameters
  ///
  /// ## Dart Lesson: Initializer Lists
  ///
  /// The colon after `)` introduces the initializer list.
  /// It runs BEFORE the constructor body (if any).
  /// Perfect for setting final fields with defaults.
  const Scroll({
    required this.key,
    required this.data,
    this.type_ = ScrollTypes.generic,
    this.metadata = const Metadata(),
  });

  /// Create from key and data (convenience)
  factory Scroll.create(String key, Map<String, dynamic> data) {
    return Scroll(key: key, data: data);
  }

  /// Create with type (common pattern)
  factory Scroll.typed(String key, Map<String, dynamic> data, String type_) {
    return Scroll(key: key, data: data, type_: type_);
  }

  /// Create empty scroll (just key)
  factory Scroll.empty(String key) {
    return Scroll(key: key, data: const {});
  }

  // ============================================================================
  // Builder Pattern via copyWith
  // ============================================================================

  /// Copy with modifications
  ///
  /// ## Dart Lesson: copyWith Pattern
  ///
  /// Since Scroll is immutable (all fields final), we can't modify it.
  /// Instead, we create a new instance with some fields changed.
  ///
  /// The `??` null-coalescing operator means "if null, use this default".
  /// So `newType ?? type_` means "use newType if provided, else keep current".
  Scroll copyWith({
    String? key,
    String? type_,
    Metadata? metadata,
    Map<String, dynamic>? data,
  }) {
    return Scroll(
      key: key ?? this.key,
      type_: type_ ?? this.type_,
      metadata: metadata ?? this.metadata,
      data: data ?? this.data,
    );
  }

  /// Set the type
  Scroll withType(String type_) => copyWith(type_: type_);

  /// Set the data
  Scroll withData(Map<String, dynamic> data) => copyWith(data: data);

  /// Set metadata
  Scroll withMetadata(Metadata metadata) => copyWith(metadata: metadata);

  // ============================================================================
  // Linguistic Metadata Builders
  // ============================================================================

  /// Set subject (who/what acts)
  Scroll withSubject(String subject) =>
      copyWith(metadata: metadata.copyWith(subject: subject));

  /// Set verb (action taken)
  Scroll withVerb(String verb) =>
      copyWith(metadata: metadata.copyWith(verb: verb));

  /// Set object (target of action)
  Scroll withObject(String object) =>
      copyWith(metadata: metadata.copyWith(object: object));

  /// Set tense
  Scroll withTense(Tense tense) =>
      copyWith(metadata: metadata.copyWith(tense: tense));

  // ============================================================================
  // Taxonomic Metadata Builders
  // ============================================================================

  /// Set kingdom (broadest category)
  Scroll withKingdom(String kingdom) =>
      copyWith(metadata: metadata.copyWith(kingdom: kingdom));

  /// Set phylum (major division)
  Scroll withPhylum(String phylum) =>
      copyWith(metadata: metadata.copyWith(phylum: phylum));

  /// Set class (common characteristics)
  Scroll withClass(String class_) =>
      copyWith(metadata: metadata.copyWith(class_: class_));

  // ============================================================================
  // Extension Builders
  // ============================================================================

  /// Add a domain-specific extension
  Scroll withExtension(String key, dynamic value) {
    final newExtensions = Map<String, dynamic>.from(metadata.extensions);
    newExtensions[key] = value;
    return copyWith(metadata: metadata.copyWith(extensions: newExtensions));
  }

  // ============================================================================
  // Lifecycle Builders
  // ============================================================================

  /// Set expiration time
  Scroll withExpiresAt(int expiresAt) =>
      copyWith(metadata: metadata.copyWith(expiresAt: expiresAt));

  /// Mark as deleted
  Scroll markDeleted() => copyWith(metadata: metadata.copyWith(deleted: true));

  /// Unmark deletion
  Scroll unmarkDeleted() =>
      copyWith(metadata: metadata.copyWith(deleted: false));

  /// Check if soft-deleted
  bool get isDeleted => metadata.deleted ?? false;

  // ============================================================================
  // Data Field Accessors
  // ============================================================================

  /// Get a string field from data
  ///
  /// ## Dart Lesson: Generics and Type Safety
  ///
  /// The `as String?` cast returns null if the value isn't a String.
  /// This is safe because we're accessing dynamic data.
  String? getString(String field) => data[field] as String?;

  /// Get string with default
  String getStringOr(String field, String defaultValue) =>
      getString(field) ?? defaultValue;

  /// Get an int field
  int? getInt(String field) {
    final value = data[field];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }

  /// Get a bool field
  bool? getBool(String field) => data[field] as bool?;

  /// Get a bool extension
  bool getExtBool(String key) => metadata.extensions[key] as bool? ?? false;

  /// Get a string extension
  String? getExtString(String key) => metadata.extensions[key] as String?;

  // ============================================================================
  // Computed Properties
  // ============================================================================

  /// Compute content hash (SHA-256 of key + type + JSON(data))
  ///
  /// ## Dart Lesson: String Interpolation
  ///
  /// `'$key$type_${jsonEncode(data)}'` embeds variables directly.
  /// Use `$variable` for simple names, `${expression}` for complex expressions.
  String computeHash() {
    final content = '$key$type_${jsonEncode(data)}';
    final bytes = utf8.encode(content);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Finalize with computed hash and timestamps
  ///
  /// Called before writing to namespace.
  Scroll finalize() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return copyWith(
      metadata: metadata.copyWith(
        createdAt: metadata.createdAt ?? now,
        updatedAt: now,
        hash: computeHash(),
      ),
    );
  }

  /// Increment version
  Scroll incrementVersion() =>
      copyWith(metadata: metadata.copyWith(version: metadata.version + 1));

  // ============================================================================
  // Serialization
  // ============================================================================

  /// Convert to JSON map
  ///
  /// ## Dart Lesson: Spread Operator
  ///
  /// `...metadata.toJson()` spreads metadata fields into this map.
  /// It's like Object.assign in JS or ** in Python.
  Map<String, dynamic> toJson() => {
        'key': key,
        'type': type_,
        'metadata': metadata.toJson(),
        'data': data,
      };

  /// Create from JSON map
  ///
  /// ## Dart Lesson: Factory Constructors
  ///
  /// `factory` constructors can return existing instances or different types.
  /// They're not required to create new instances (unlike regular constructors).
  factory Scroll.fromJson(Map<String, dynamic> json) {
    return Scroll(
      key: json['key'] as String,
      type_: json['type'] as String? ?? ScrollTypes.generic,
      metadata: json['metadata'] != null
          ? Metadata.fromJson(json['metadata'] as Map<String, dynamic>)
          : const Metadata(),
      data: json['data'] as Map<String, dynamic>? ?? {},
    );
  }

  // ============================================================================
  // Object Overrides
  // ============================================================================

  /// Equality based on key, type, and data
  ///
  /// ## Dart Lesson: operator ==
  ///
  /// Override `==` and `hashCode` together (they must be consistent).
  /// Use `identical` for reference equality, then check runtime types.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Scroll) return false;
    return key == other.key &&
        type_ == other.type_ &&
        _mapEquals(data, other.data);
  }

  @override
  int get hashCode => Object.hash(key, type_, data.hashCode);

  @override
  String toString() => 'Scroll($key, type: $type_, data: $data)';
}

/// Deep equality for maps (simple implementation)
bool _mapEquals(Map<String, dynamic> a, Map<String, dynamic> b) {
  if (a.length != b.length) return false;
  for (final key in a.keys) {
    if (!b.containsKey(key)) return false;
    final va = a[key];
    final vb = b[key];
    if (va is Map<String, dynamic> && vb is Map<String, dynamic>) {
      if (!_mapEquals(va, vb)) return false;
    } else if (va != vb) {
      return false;
    }
  }
  return true;
}
