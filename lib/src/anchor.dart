/// Anchor - Immutable Checkpoints for Scrolls
///
/// An anchor is a snapshot of a scroll's state at a point in time.
/// Anchors are immutable - once created, they cannot be modified.
///
/// ## Platonic Form: ⚓ (Checkpoint)
///
/// An anchor is the philosophical opposite of a patch:
/// - **Patch** = Δ (Delta) - change over time
/// - **Anchor** = ⚓ (Point) - frozen moment
///
/// Together they enable time travel: patches build history forward,
/// anchors mark significant points for quick retrieval.
///
/// ## Dart Lesson: Immutable Data Classes
///
/// Dart encourages immutability through:
/// 1. `final` fields - cannot be reassigned
/// 2. `const` constructors - compile-time constants
/// 3. `copyWith()` - create modified copies
///
/// Anchors demonstrate pure immutability - no setters, no mutation.
/// To "modify" an anchor, you create a new one.
library;

import 'dart:math';

import 'scroll.dart';

/// An immutable checkpoint of a scroll's state
///
/// Anchors freeze a scroll at a specific point in time.
/// They include the full scroll content and a hash for integrity verification.
///
/// ## Dart Lesson: Named Parameters with Defaults
///
/// ```dart
/// // All parameters are named, making construction clear
/// final anchor = Anchor(
///   id: 'abc-123',
///   scroll: scroll,
///   hash: 'sha256...',
///   timestamp: 1234567890,
///   label: 'v1.0',  // optional
/// );
/// ```
class Anchor {
  /// Unique anchor ID (hash prefix + timestamp + random suffix)
  final String id;

  /// The full scroll state at this point
  final Scroll scroll;

  /// Content hash (SHA-256 hex) for verification
  final String hash;

  /// When the anchor was created (Unix millis)
  final int timestamp;

  /// Optional human-readable label
  final String? label;

  /// Optional description
  final String? description;

  /// Create an anchor
  ///
  /// Prefer using [create] factory for automatic ID and hash generation.
  const Anchor({
    required this.id,
    required this.scroll,
    required this.hash,
    required this.timestamp,
    this.label,
    this.description,
  });

  /// Convert to JSON
  Map<String, dynamic> toJson() => {
        'id': id,
        'scroll': scroll.toJson(),
        'hash': hash,
        'timestamp': timestamp,
        if (label != null) 'label': label,
        if (description != null) 'description': description,
      };

  /// Parse from JSON
  factory Anchor.fromJson(Map<String, dynamic> json) {
    return Anchor(
      id: json['id'] as String,
      scroll: Scroll.fromJson(json['scroll'] as Map<String, dynamic>),
      hash: json['hash'] as String,
      timestamp: json['timestamp'] as int,
      label: json['label'] as String?,
      description: json['description'] as String?,
    );
  }

  /// Copy with modifications
  ///
  /// Note: Since Anchor is immutable, this creates a new instance.
  /// Only label and description can be "modified" - id, hash, etc are immutable.
  Anchor copyWith({
    String? label,
    String? description,
  }) {
    return Anchor(
      id: id,
      scroll: scroll,
      hash: hash,
      timestamp: timestamp,
      label: label ?? this.label,
      description: description ?? this.description,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Anchor &&
        other.id == id &&
        other.hash == hash &&
        other.timestamp == timestamp;
  }

  @override
  int get hashCode => Object.hash(id, hash, timestamp);

  @override
  String toString() => 'Anchor(id: $id, label: $label, hash: ${hash.substring(0, 8)}...)';
}

// ============================================================================
// Pure Functions for Anchor Operations
// ============================================================================

/// Create an anchor from a scroll
///
/// The anchor captures the scroll's current state immutably.
/// An optional label can be provided for human reference.
///
/// ## Dart Lesson: Factory-like Top-level Functions
///
/// Dart allows both factory constructors and top-level functions.
/// Top-level functions are:
/// - More flexible (can return different types)
/// - Clearer about side effects (or lack thereof)
/// - Easier to test in isolation
///
/// ```dart
/// final scroll = Scroll.create('/notes/abc', {'title': 'Important'});
/// final anchor = createAnchor(scroll, label: 'v1.0');
/// ```
Anchor createAnchor(Scroll scroll, {String? label}) {
  final hash = scroll.computeHash();
  final timestamp = DateTime.now().millisecondsSinceEpoch;

  // Add random suffix for uniqueness when creating multiple anchors in same millisecond
  final suffix = Random().nextInt(0xFFFF).toRadixString(16).padLeft(4, '0');
  final id = '${hash.substring(0, 8)}-$timestamp-$suffix';

  return Anchor(
    id: id,
    scroll: scroll,
    hash: hash,
    timestamp: timestamp,
    label: label,
  );
}

/// Create an anchor with a description
Anchor createAnchorWithDescription(
  Scroll scroll, {
  String? label,
  required String description,
}) {
  return createAnchor(scroll, label: label).copyWith(description: description);
}

/// Verify an anchor's integrity
///
/// Returns true if the scroll content matches the stored hash.
///
/// ## Security Note
///
/// This detects tampering with the scroll content after anchoring.
/// If verification fails, the anchor should not be trusted.
bool verifyAnchor(Anchor anchor) {
  return anchor.scroll.computeHash() == anchor.hash;
}

/// Check if two anchors represent the same state
///
/// Two anchors are equivalent if their content hashes match,
/// even if they have different IDs, timestamps, or labels.
///
/// ## Dart Lesson: Semantic vs Identity Equality
///
/// - `anchor1 == anchor2` - identity equality (same ID, hash, timestamp)
/// - `equivalent(anchor1, anchor2)` - semantic equality (same content)
///
/// This distinction is important for deduplication vs history tracking.
bool equivalent(Anchor a, Anchor b) {
  return a.hash == b.hash;
}

/// Extract just the scroll from an anchor
///
/// Useful when restoring from a checkpoint.
/// Returns a copy to maintain immutability guarantee.
Scroll extractScroll(Anchor anchor) {
  // Scroll is immutable, so we can return it directly
  return anchor.scroll;
}
