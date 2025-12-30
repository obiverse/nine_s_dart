/// Utils - Shared Utilities for 9S
///
/// This module contains reusable utilities:
/// - Cryptographic primitives (encryption, key derivation)
/// - Random number generation
/// - Common helpers
///
/// ## Dart Lesson: Utility Libraries
///
/// Dart encourages pure functions in library files.
/// Unlike Java, you don't need a class wrapper for static methods.
/// Top-level functions are first-class citizens.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

// ============================================================================
// Constants
// ============================================================================

/// Nonce size for AES-GCM (12 bytes, standard)
const nonceSize = 12;

/// Salt size for key derivation (16 bytes)
const saltSize = 16;

/// Key size for AES-256 (32 bytes)
const keySize = 32;

/// PBKDF2 iteration count for password derivation
const pbkdf2Iterations = 100000;

// ============================================================================
// Random Number Generation
// ============================================================================

/// Generate cryptographically secure random bytes
///
/// Uses dart:math's Random.secure() which provides OS-level entropy.
Uint8List randomBytes(int length) {
  final random = Random.secure();
  return Uint8List.fromList(
    List<int>.generate(length, (_) => random.nextInt(256)),
  );
}

/// Generate a random nonce for AES-GCM
Uint8List generateNonce() => randomBytes(nonceSize);

/// Generate a random salt for key derivation
Uint8List generateSalt() => randomBytes(saltSize);

/// Generate a random 32-byte key (for testing)
Uint8List generateTestKey() => randomBytes(keySize);

// ============================================================================
// Key Derivation
// ============================================================================

/// Derive a key from a password using PBKDF2-SHA256
///
/// This is suitable for user passwords. Uses 100,000 iterations
/// to slow down brute-force attacks.
Uint8List deriveKeyFromPassword(String password, Uint8List salt) {
  final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
    ..init(Pbkdf2Parameters(salt, pbkdf2Iterations, keySize));

  return pbkdf2.process(Uint8List.fromList(utf8.encode(password)));
}

/// Derive an app-specific key using HKDF-SHA256
///
/// This provides cryptographic isolation between apps sharing
/// the same master key. Each app gets a unique derived key.
///
/// ```dart
/// final walletKey = deriveAppKey(masterKey, 'wallet');
/// final vaultKey = deriveAppKey(masterKey, 'vault');
/// // walletKey != vaultKey (cryptographically independent)
/// ```
Uint8List deriveAppKey(Uint8List masterKey, String appName) {
  // HKDF-SHA256: Extract then Expand

  // Step 1: Extract - create PRK from master key with salt
  final salt = utf8.encode('nine_s_v1');
  final hmacExtract = Hmac(sha256, salt);
  final prk = Uint8List.fromList(hmacExtract.convert(masterKey).bytes);

  // Step 2: Expand - derive output key using app name as info
  final info = utf8.encode(appName);
  final okm = Uint8List(keySize);

  var t = <int>[];
  var offset = 0;
  var counter = 1;

  while (offset < keySize) {
    final hmacExpand = Hmac(sha256, prk);
    final input = [...t, ...info, counter];
    t = hmacExpand.convert(input).bytes;

    final remaining = keySize - offset;
    final copyLen = remaining < t.length ? remaining : t.length;
    okm.setRange(offset, offset + copyLen, t);

    offset += copyLen;
    counter++;
  }

  return okm;
}

/// Default key for non-password protected content
///
/// This provides obfuscation, NOT security. Anyone with the code
/// can derive this key. Use password protection for real security.
Uint8List defaultObfuscationKey() {
  final hash = sha256.convert(utf8.encode('beescroll:no-password'));
  return Uint8List.fromList(hash.bytes);
}

// ============================================================================
// AES-256-GCM Encryption
// ============================================================================

/// Encrypt data using AES-256-GCM
///
/// Returns: nonce (12 bytes) + ciphertext + auth tag
///
/// The nonce is prepended to the ciphertext so the result is
/// self-contained and can be decrypted with just the key.
Uint8List encrypt(Uint8List key, Uint8List plaintext) {
  if (key.length != keySize) {
    throw ArgumentError('Key must be $keySize bytes');
  }

  final nonce = generateNonce();

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

  final ciphertext = cipher.process(plaintext);

  // Prepend nonce to ciphertext
  final result = Uint8List(nonce.length + ciphertext.length);
  result.setAll(0, nonce);
  result.setAll(nonce.length, ciphertext);

  return result;
}

/// Decrypt data using AES-256-GCM
///
/// Input format: nonce (12 bytes) + ciphertext + auth tag
///
/// Returns null if decryption fails (wrong key, corrupted data,
/// or tampered ciphertext).
Uint8List? decrypt(Uint8List key, Uint8List data) {
  if (key.length != keySize) {
    throw ArgumentError('Key must be $keySize bytes');
  }

  if (data.length < nonceSize) {
    return null; // Too short to contain nonce
  }

  try {
    final nonce = data.sublist(0, nonceSize);
    final ciphertext = data.sublist(nonceSize);

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
    return null; // Decryption failed
  }
}

// ============================================================================
// Hashing
// ============================================================================

/// Compute SHA-256 hash of data, return as hex string
String sha256Hex(Uint8List data) {
  return sha256.convert(data).toString();
}

/// Compute SHA-256 hash of a string, return as hex string
String sha256String(String input) {
  return sha256.convert(utf8.encode(input)).toString();
}

// ============================================================================
// Deep Copy / Equality
// ============================================================================

/// Deep copy a JSON-compatible map
Map<String, dynamic> deepCopyMap(Map<String, dynamic> data) {
  return data.map((key, value) {
    if (value is Map<String, dynamic>) {
      return MapEntry(key, deepCopyMap(value));
    } else if (value is List) {
      return MapEntry(key, deepCopyList(value));
    }
    return MapEntry(key, value);
  });
}

/// Deep copy a JSON-compatible list
List<dynamic> deepCopyList(List<dynamic> data) {
  return data.map((value) {
    if (value is Map<String, dynamic>) {
      return deepCopyMap(value);
    } else if (value is List) {
      return deepCopyList(value);
    }
    return value;
  }).toList();
}

/// Deep equality check for JSON-compatible values
bool deepEquals(dynamic a, dynamic b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      if (!deepEquals(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}
