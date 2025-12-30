/// SealedScroll - Shareable Encrypted Content
///
/// Scrolls can be sealed for secure sharing. A sealed scroll is a self-contained
/// encrypted envelope that can be shared via URI and unsealed with the correct password.
///
/// ## Platonic Form: 📜🔐 (Encrypted Envelope)
///
/// A SealedScroll is a scroll that has been:
/// 1. Serialized to JSON
/// 2. Encrypted with AES-256-GCM
/// 3. Encoded as a shareable URI
///
/// The URI format `beescroll://v1/{base64}` is:
/// - Self-contained (everything needed to unseal)
/// - URL-safe (can be shared in links, QR codes)
/// - Versioned (future-proof)
///
/// ## Design Philosophy
///
/// A scroll is to 9S what a file is to Plan 9. Just as files can be encrypted
/// and shared in Unix, scrolls can be sealed and shared in 9S.
///
/// Sealing is a scroll operation, not a domain-specific operation:
/// - `sealScroll(scroll, password?)` → SealedScroll
/// - `unsealScroll(sealed, password?)` → Scroll
/// - `toUri(sealed)` → "beescroll://v1/..."
/// - `fromUri(uri)` → SealedScroll
///
/// ## Security Notes
///
/// - Password-protected scrolls use PBKDF2 with 100,000 iterations
/// - No-password scrolls use a deterministic default key (obfuscation only)
/// - AES-256-GCM provides authenticated encryption
/// - Salt is unique per seal operation (prevents rainbow table attacks)
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

import 'scroll.dart';

/// Maximum content size for sealed scrolls (64 KB)
/// Larger content should be chunked or stored differently
const maxSealedSize = 65536;

/// Format version for sealed scrolls
const _sealedVersion = 1;

/// Salt size for password derivation (16 bytes)
const _saltSize = 16;

/// Nonce size for AES-GCM (12 bytes, standard)
const _nonceSize = 12;

/// Key size for AES-256 (32 bytes)
const _keySize = 32;

/// PBKDF2 iteration count (100,000 for security)
const _pbkdf2Iterations = 100000;

/// Sealed scroll envelope for sharing
///
/// Contains everything needed to unseal the original scroll:
/// - Encrypted scroll JSON
/// - Nonce for AES-GCM
/// - Salt for password derivation (if password-protected)
///
/// ## Dart Lesson: Value Classes
///
/// SealedScroll is a value class - its identity is determined by its
/// contents, not by reference. Two SealedScrolls with the same fields
/// are semantically equal (though `==` is by reference by default).
class SealedScroll {
  /// Format version (currently 1)
  final int version;

  /// Base64-encoded ciphertext (encrypted scroll JSON)
  final String ciphertext;

  /// Base64-encoded nonce
  final String nonce;

  /// Base64-encoded salt (only present if password protected)
  final String? salt;

  /// Whether a password is required to unseal
  final bool hasPassword;

  /// Unix timestamp when sealed (seconds)
  final int sealedAt;

  /// Original scroll type (for display before unsealing)
  final String? scrollType;

  const SealedScroll({
    required this.version,
    required this.ciphertext,
    required this.nonce,
    this.salt,
    required this.hasPassword,
    required this.sealedAt,
    this.scrollType,
  });

  /// Convert to JSON
  Map<String, dynamic> toJson() => {
        'version': version,
        'ciphertext': ciphertext,
        'nonce': nonce,
        if (salt != null) 'salt': salt,
        'has_password': hasPassword,
        'sealed_at': sealedAt,
        if (scrollType != null) 'scroll_type': scrollType,
      };

  /// Parse from JSON
  factory SealedScroll.fromJson(Map<String, dynamic> json) {
    return SealedScroll(
      version: json['version'] as int,
      ciphertext: json['ciphertext'] as String,
      nonce: json['nonce'] as String,
      salt: json['salt'] as String?,
      hasPassword: json['has_password'] as bool,
      sealedAt: json['sealed_at'] as int,
      scrollType: json['scroll_type'] as String?,
    );
  }

  /// Check if this sealed scroll requires a password
  bool get requiresPassword => hasPassword;

  /// Encode as a shareable URI
  ///
  /// Format: `beescroll://v1/{base64url_encoded_json}`
  String toUri() {
    final json = jsonEncode(toJson());
    final encoded = base64Url.encode(utf8.encode(json));
    return 'beescroll://v1/$encoded';
  }

  /// Parse a sealed scroll from URI
  ///
  /// Accepts:
  /// - `beescroll://v1/{base64url_encoded_json}`
  /// - Raw JSON
  ///
  /// ## Dart Lesson: Factory Constructors for Parsing
  ///
  /// Factory constructors can return existing instances or parse
  /// from various formats. This is idiomatic for URI/string parsing.
  factory SealedScroll.fromUri(String input) {
    final trimmed = input.trim();

    // Handle beescroll:// URI
    if (trimmed.startsWith('beescroll://v1/')) {
      final encoded = trimmed.substring('beescroll://v1/'.length);
      final jsonBytes = base64Url.decode(encoded);
      final json = utf8.decode(jsonBytes);
      return SealedScroll.fromJson(jsonDecode(json) as Map<String, dynamic>);
    }

    // Handle legacy beenote:// URI for backwards compatibility
    if (trimmed.startsWith('beenote://v1/')) {
      final encoded = trimmed.substring('beenote://v1/'.length);
      final jsonBytes = base64Url.decode(encoded);
      final json = utf8.decode(jsonBytes);
      return SealedScroll.fromJson(jsonDecode(json) as Map<String, dynamic>);
    }

    // Assume raw JSON
    if (trimmed.startsWith('{')) {
      return SealedScroll.fromJson(jsonDecode(trimmed) as Map<String, dynamic>);
    }

    throw const FormatException('Input must be a beescroll:// URI or JSON');
  }

  @override
  String toString() =>
      'SealedScroll(version: $version, hasPassword: $hasPassword, type: $scrollType)';
}

// ============================================================================
// Sealing Errors
// ============================================================================

/// Error during seal/unseal operations
sealed class SealError implements Exception {
  final String message;
  const SealError(this.message);

  @override
  String toString() => '$runtimeType: $message';
}

/// Encryption failed
class EncryptionError extends SealError {
  const EncryptionError(super.message);
}

/// Decryption failed (wrong password or corrupted data)
class DecryptionError extends SealError {
  const DecryptionError(super.message);
}

/// Invalid data format
class InvalidFormatError extends SealError {
  const InvalidFormatError(super.message);
}

/// Content too large
class ContentTooLargeError extends SealError {
  const ContentTooLargeError(super.message);
}

// ============================================================================
// Seal Result Type
// ============================================================================

/// Result type for seal/unseal operations
///
/// ## Dart Lesson: Result Pattern
///
/// Rather than throwing exceptions, we return a Result type.
/// This makes error handling explicit and type-safe.
sealed class SealResult<T> {
  const SealResult();
}

class SealOk<T> extends SealResult<T> {
  final T value;
  const SealOk(this.value);
}

class SealErr<T> extends SealResult<T> {
  final SealError error;
  const SealErr(this.error);
}

// ============================================================================
// Pure Functions for Seal/Unseal
// ============================================================================

/// Seal a scroll for sharing
///
/// Creates an encrypted envelope that can be shared via URI.
/// Optional password provides additional security.
///
/// ## Example
/// ```dart
/// final scroll = Scroll.create('/notes/secret', {'content': 'Hello'});
/// final result = sealScroll(scroll, password: 'password123');
/// if (result is SealOk<SealedScroll>) {
///   final uri = result.value.toUri();
///   print('Share this: $uri');
/// }
/// ```
SealResult<SealedScroll> sealScroll(Scroll scroll, {String? password}) {
  try {
    // Serialize scroll to JSON
    final scrollJson = jsonEncode(scroll.toJson());

    if (scrollJson.length > maxSealedSize) {
      return const SealErr(ContentTooLargeError(
          'Scroll exceeds maximum sealed size of $maxSealedSize bytes'));
    }

    // Generate key and salt
    final Uint8List key;
    final Uint8List? salt;

    if (password != null && password.isNotEmpty) {
      salt = _generateSalt();
      key = _deriveKey(password, salt);
    } else {
      salt = null;
      key = _defaultKey();
    }

    // Generate nonce
    final nonce = _generateNonce();

    // Encrypt
    final plaintext = utf8.encode(scrollJson);
    final ciphertext = _encrypt(key, nonce, Uint8List.fromList(plaintext));

    final sealed = SealedScroll(
      version: _sealedVersion,
      ciphertext: base64.encode(ciphertext),
      nonce: base64.encode(nonce),
      salt: salt != null ? base64.encode(salt) : null,
      hasPassword: password != null && password.isNotEmpty,
      sealedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      scrollType: scroll.type_,
    );

    return SealOk(sealed);
  } catch (e) {
    return SealErr(EncryptionError('Failed to seal: $e'));
  }
}

/// Unseal a scroll, recovering the original content
///
/// ## Example
/// ```dart
/// final sealed = SealedScroll.fromUri(uri);
/// final result = unsealScroll(sealed, password: 'password123');
/// if (result is SealOk<Scroll>) {
///   print('Recovered: ${result.value.data}');
/// }
/// ```
SealResult<Scroll> unsealScroll(SealedScroll sealed, {String? password}) {
  try {
    if (sealed.version != _sealedVersion) {
      return SealErr(
          InvalidFormatError('Unsupported sealed version: ${sealed.version}'));
    }

    // Derive key
    final Uint8List key;

    if (sealed.hasPassword) {
      if (password == null || password.isEmpty) {
        return const SealErr(
            DecryptionError('Password required but not provided'));
      }

      if (sealed.salt == null) {
        return const SealErr(
            InvalidFormatError('Password-protected scroll missing salt'));
      }

      final salt = base64.decode(sealed.salt!);
      key = _deriveKey(password, Uint8List.fromList(salt));
    } else {
      key = _defaultKey();
    }

    // Decrypt
    final ciphertext = base64.decode(sealed.ciphertext);
    final nonce = base64.decode(sealed.nonce);

    final plaintext = _decrypt(
      key,
      Uint8List.fromList(nonce),
      Uint8List.fromList(ciphertext),
    );

    if (plaintext == null) {
      return const SealErr(
          DecryptionError('Decryption failed - wrong password or corrupted data'));
    }

    // Parse scroll
    final scrollJson = utf8.decode(plaintext);
    final scroll =
        Scroll.fromJson(jsonDecode(scrollJson) as Map<String, dynamic>);

    return SealOk(scroll);
  } catch (e) {
    if (e is SealError) {
      return SealErr(e);
    }
    return SealErr(DecryptionError('Failed to unseal: $e'));
  }
}

// ============================================================================
// Internal: Cryptographic Primitives
// ============================================================================

/// Default key for scrolls without password (deterministic obfuscation)
/// This is NOT secure - it just makes the blob opaque to casual observation
Uint8List _defaultKey() {
  // SHA256("beescroll:no-password") - deterministic default
  final hash = sha256.convert(utf8.encode('beescroll:no-password'));
  return Uint8List.fromList(hash.bytes);
}

/// Generate random salt for password derivation
Uint8List _generateSalt() {
  final random = Random.secure();
  return Uint8List.fromList(
      List<int>.generate(_saltSize, (_) => random.nextInt(256)));
}

/// Generate random nonce for AES-GCM
Uint8List _generateNonce() {
  final random = Random.secure();
  return Uint8List.fromList(
      List<int>.generate(_nonceSize, (_) => random.nextInt(256)));
}

/// Derive key from password using PBKDF2
Uint8List _deriveKey(String password, Uint8List salt) {
  final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
    ..init(Pbkdf2Parameters(salt, _pbkdf2Iterations, _keySize));

  return pbkdf2.process(Uint8List.fromList(utf8.encode(password)));
}

/// Encrypt using AES-256-GCM
Uint8List _encrypt(Uint8List key, Uint8List nonce, Uint8List plaintext) {
  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      true, // encrypt
      AEADParameters(
        KeyParameter(key),
        128, // tag length in bits
        nonce,
        Uint8List(0), // no additional authenticated data
      ),
    );

  return cipher.process(plaintext);
}

/// Decrypt using AES-256-GCM
/// Returns null if decryption fails (wrong key or corrupted data)
Uint8List? _decrypt(Uint8List key, Uint8List nonce, Uint8List ciphertext) {
  try {
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false, // decrypt
        AEADParameters(
          KeyParameter(key),
          128, // tag length in bits
          nonce,
          Uint8List(0), // no additional authenticated data
        ),
      );

    return cipher.process(ciphertext);
  } catch (_) {
    return null;
  }
}
