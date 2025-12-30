/// Metadata - Semantic context for every Scroll
///
/// Three levels of meaning:
/// 1. **Timestamps** - When (created, updated, synced, expires)
/// 2. **Linguistic** - Who did what to what (subject-verb-object)
/// 3. **Taxonomic** - What kind (kingdom-phylum-class)
///
/// ## Dart Lesson: const Constructors
///
/// When a class has all final fields and the constructor uses only constant
/// expressions, you can mark it `const`. This enables compile-time evaluation:
///
/// ```dart
/// const metadata = Metadata();           // Compile-time constant
/// final metadata = Metadata(version: 1); // Runtime instance
/// ```
///
/// const objects are canonicalized - there's only one instance in memory.
library;

/// Temporal tense for linguistic model
///
/// ## Dart Lesson: Enums
///
/// Dart enums are type-safe and can have methods/properties.
/// `Tense.past` is guaranteed to be one of three values.
enum Tense {
  past,
  present,
  future;

  /// Convert to JSON string
  String toJson() => name;

  /// Parse from JSON string
  static Tense? fromJson(String? value) {
    if (value == null) return null;
    return Tense.values.where((t) => t.name == value).firstOrNull;
  }
}

/// Well-known kingdoms
abstract final class Kingdoms {
  static const financial = 'financial';
  static const content = 'content';
  static const security = 'security';
  static const system = 'system';
  static const directory = 'directory';
}

/// Well-known verbs
abstract final class Verbs {
  // CRUD-like
  static const creates = 'creates';
  static const reads = 'reads';
  static const updates = 'updates';
  static const deletes = 'deletes';
  static const writes = 'writes';

  // Ownership/transfer
  static const owns = 'owns';
  static const sends = 'sends';
  static const receives = 'receives';

  // Communication
  static const notifies = 'notifies';
  static const emits = 'emits';

  // Control
  static const controls = 'controls';
  static const executes = 'executes';

  // Security/encryption
  static const seals = 'seals';
  static const unseals = 'unseals';

  // Lifecycle
  static const ends = 'ends';
  static const clears = 'clears';
  static const disconnects = 'disconnects';
}

/// Metadata attached to every Scroll
///
/// ## Dart Lesson: Immutable Data Classes
///
/// This pattern is common in Dart:
/// 1. All fields are `final`
/// 2. Constructor is `const` (when possible)
/// 3. Provide `copyWith` for modifications
/// 4. Override `==`, `hashCode`, and `toString`
///
/// This gives you value semantics (equality by content, not reference).
class Metadata {
  // ============================================================================
  // Timestamps (Unix milliseconds)
  // ============================================================================

  /// Creation timestamp (Unix ms)
  final int? createdAt;

  /// Last update timestamp (Unix ms)
  final int? updatedAt;

  /// Last sync timestamp (OIOI layer, Unix ms)
  final int? syncedAt;

  /// TTL for ephemeral scrolls (Unix ms)
  final int? expiresAt;

  // ============================================================================
  // Lifecycle
  // ============================================================================

  /// Soft delete flag
  final bool? deleted;

  /// Version number (increments on each write)
  final int version;

  /// Content hash (SHA-256 hex of key + type + data)
  final String? hash;

  // ============================================================================
  // Linguistic Model (Subject-Verb-Object)
  // ============================================================================

  /// Who/what acts (mobinumber, "wallet:master", "ln:{node}")
  final String? subject;

  /// Action taken ("owns", "sends", "receives", "creates", "updates", "deletes")
  final String? verb;

  /// Target of action (scroll key, amount, pubkey)
  final String? object;

  /// Temporal aspect
  final Tense? tense;

  // ============================================================================
  // Taxonomic Model (Kingdom-Phylum-Class)
  // ============================================================================

  /// Broadest category: "financial", "content", "security", "system", "directory"
  final String? kingdom;

  /// Major division within kingdom
  final String? phylum;

  /// Common characteristics: "transaction", "invoice", "note", "policy"
  final String? class_;

  // ============================================================================
  // Extensions
  // ============================================================================

  /// Domain-specific key-value pairs
  final Map<String, dynamic> extensions;

  // ============================================================================
  // Constructor
  // ============================================================================

  /// Create metadata with optional fields
  ///
  /// ## Dart Lesson: Default Parameter Values
  ///
  /// `this.version = 0` sets the default. If caller doesn't provide it,
  /// version will be 0. This works in const constructors too.
  const Metadata({
    this.createdAt,
    this.updatedAt,
    this.syncedAt,
    this.expiresAt,
    this.deleted,
    this.version = 0,
    this.hash,
    this.subject,
    this.verb,
    this.object,
    this.tense,
    this.kingdom,
    this.phylum,
    this.class_,
    this.extensions = const {},
  });

  // ============================================================================
  // copyWith
  // ============================================================================

  /// Copy with modifications
  ///
  /// ## Dart Lesson: Handling Optional Fields in copyWith
  ///
  /// The tricky part: how do you distinguish "not provided" from "set to null"?
  ///
  /// Option 1 (used here): Just use `??` and accept you can't set to null
  /// Option 2: Use sentinel values or wrapper types
  ///
  /// For Metadata, nullability is fine - we rarely need to unset fields.
  Metadata copyWith({
    int? createdAt,
    int? updatedAt,
    int? syncedAt,
    int? expiresAt,
    bool? deleted,
    int? version,
    String? hash,
    String? subject,
    String? verb,
    String? object,
    Tense? tense,
    String? kingdom,
    String? phylum,
    String? class_,
    Map<String, dynamic>? extensions,
  }) {
    return Metadata(
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncedAt: syncedAt ?? this.syncedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      deleted: deleted ?? this.deleted,
      version: version ?? this.version,
      hash: hash ?? this.hash,
      subject: subject ?? this.subject,
      verb: verb ?? this.verb,
      object: object ?? this.object,
      tense: tense ?? this.tense,
      kingdom: kingdom ?? this.kingdom,
      phylum: phylum ?? this.phylum,
      class_: class_ ?? this.class_,
      extensions: extensions ?? this.extensions,
    );
  }

  // ============================================================================
  // Serialization
  // ============================================================================

  /// Convert to JSON map
  ///
  /// ## Dart Lesson: Conditional Map Entries
  ///
  /// The `if (field != null) 'key': field` syntax is collection-if.
  /// It only includes the entry if the condition is true.
  /// This keeps JSON compact by omitting null values.
  Map<String, dynamic> toJson() => {
        if (createdAt != null) 'createdAt': createdAt,
        if (updatedAt != null) 'updatedAt': updatedAt,
        if (syncedAt != null) 'syncedAt': syncedAt,
        if (expiresAt != null) 'expiresAt': expiresAt,
        if (deleted != null) 'deleted': deleted,
        'version': version,
        if (hash != null) 'hash': hash,
        if (subject != null) 'subject': subject,
        if (verb != null) 'verb': verb,
        if (object != null) 'object': object,
        if (tense != null) 'tense': tense!.toJson(),
        if (kingdom != null) 'kingdom': kingdom,
        if (phylum != null) 'phylum': phylum,
        if (class_ != null) 'class': class_,
        if (extensions.isNotEmpty) ...extensions,
      };

  /// Create from JSON map
  factory Metadata.fromJson(Map<String, dynamic> json) {
    // Separate known fields from extensions
    final knownKeys = {
      'createdAt',
      'updatedAt',
      'syncedAt',
      'expiresAt',
      'deleted',
      'version',
      'hash',
      'subject',
      'verb',
      'object',
      'tense',
      'kingdom',
      'phylum',
      'class',
    };

    final extensions = <String, dynamic>{};
    for (final entry in json.entries) {
      if (!knownKeys.contains(entry.key)) {
        extensions[entry.key] = entry.value;
      }
    }

    return Metadata(
      createdAt: json['createdAt'] as int?,
      updatedAt: json['updatedAt'] as int?,
      syncedAt: json['syncedAt'] as int?,
      expiresAt: json['expiresAt'] as int?,
      deleted: json['deleted'] as bool?,
      version: json['version'] as int? ?? 0,
      hash: json['hash'] as String?,
      subject: json['subject'] as String?,
      verb: json['verb'] as String?,
      object: json['object'] as String?,
      tense: Tense.fromJson(json['tense'] as String?),
      kingdom: json['kingdom'] as String?,
      phylum: json['phylum'] as String?,
      class_: json['class'] as String?,
      extensions: extensions,
    );
  }

  // ============================================================================
  // Object Overrides
  // ============================================================================

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Metadata) return false;
    return createdAt == other.createdAt &&
        updatedAt == other.updatedAt &&
        syncedAt == other.syncedAt &&
        expiresAt == other.expiresAt &&
        deleted == other.deleted &&
        version == other.version &&
        hash == other.hash &&
        subject == other.subject &&
        verb == other.verb &&
        object == other.object &&
        tense == other.tense &&
        kingdom == other.kingdom &&
        phylum == other.phylum &&
        class_ == other.class_;
  }

  @override
  int get hashCode => Object.hash(
        createdAt,
        updatedAt,
        version,
        hash,
        subject,
        verb,
        object,
        tense,
        kingdom,
        phylum,
        class_,
      );

  @override
  String toString() => 'Metadata(v$version, ${subject ?? "?"} ${verb ?? "?"})';
}
