// SealedScroll Tests - Shareable Encrypted Content

import 'package:test/test.dart';
import 'package:nine_s/nine_s.dart';

void main() {
  group('SealedScroll', () {
    test('creates with required fields', () {
      const sealed = SealedScroll(
        version: 1,
        ciphertext: 'encrypted-data',
        nonce: 'random-nonce',
        hasPassword: false,
        sealedAt: 1234567890,
      );

      expect(sealed.version, equals(1));
      expect(sealed.ciphertext, equals('encrypted-data'));
      expect(sealed.nonce, equals('random-nonce'));
      expect(sealed.hasPassword, isFalse);
      expect(sealed.requiresPassword, isFalse);
      expect(sealed.salt, isNull);
      expect(sealed.scrollType, isNull);
    });

    test('creates with optional fields', () {
      const sealed = SealedScroll(
        version: 1,
        ciphertext: 'encrypted',
        nonce: 'nonce',
        salt: 'salt-value',
        hasPassword: true,
        sealedAt: 100,
        scrollType: 'vault/note@v1',
      );

      expect(sealed.salt, equals('salt-value'));
      expect(sealed.hasPassword, isTrue);
      expect(sealed.requiresPassword, isTrue);
      expect(sealed.scrollType, equals('vault/note@v1'));
    });

    test('toJson and fromJson roundtrip', () {
      const original = SealedScroll(
        version: 1,
        ciphertext: 'cipher',
        nonce: 'nonce',
        salt: 'salt',
        hasPassword: true,
        sealedAt: 12345,
        scrollType: 'test/type@v1',
      );

      final json = original.toJson();
      final restored = SealedScroll.fromJson(json);

      expect(restored.version, equals(original.version));
      expect(restored.ciphertext, equals(original.ciphertext));
      expect(restored.nonce, equals(original.nonce));
      expect(restored.salt, equals(original.salt));
      expect(restored.hasPassword, equals(original.hasPassword));
      expect(restored.sealedAt, equals(original.sealedAt));
      expect(restored.scrollType, equals(original.scrollType));
    });

    test('toUri generates beescroll:// URI', () {
      const sealed = SealedScroll(
        version: 1,
        ciphertext: 'test',
        nonce: 'nonce',
        hasPassword: false,
        sealedAt: 100,
      );

      final uri = sealed.toUri();
      expect(uri, startsWith('beescroll://v1/'));
    });

    test('fromUri parses beescroll:// URI', () {
      const original = SealedScroll(
        version: 1,
        ciphertext: 'test-cipher',
        nonce: 'test-nonce',
        hasPassword: false,
        sealedAt: 12345,
      );

      final uri = original.toUri();
      final parsed = SealedScroll.fromUri(uri);

      expect(parsed.ciphertext, equals(original.ciphertext));
      expect(parsed.nonce, equals(original.nonce));
      expect(parsed.sealedAt, equals(original.sealedAt));
    });

    test('fromUri parses legacy beenote:// URI', () {
      // Create a beescroll URI and manually change the scheme
      const sealed = SealedScroll(
        version: 1,
        ciphertext: 'test',
        nonce: 'nonce',
        hasPassword: false,
        sealedAt: 100,
      );

      final beescrollUri = sealed.toUri();
      final beenoteUri = beescrollUri.replaceFirst('beescroll://', 'beenote://');

      final parsed = SealedScroll.fromUri(beenoteUri);
      expect(parsed.ciphertext, equals('test'));
    });

    test('fromUri throws on invalid format', () {
      expect(
        () => SealedScroll.fromUri('invalid://data'),
        throwsA(isA<FormatException>()),
      );
    });

    test('toString contains useful info', () {
      const sealed = SealedScroll(
        version: 1,
        ciphertext: 'cipher',
        nonce: 'nonce',
        hasPassword: true,
        sealedAt: 100,
        scrollType: 'vault/note@v1',
      );

      final str = sealed.toString();
      expect(str, contains('version: 1'));
      expect(str, contains('hasPassword: true'));
      expect(str, contains('vault/note@v1'));
    });
  });

  group('sealScroll', () {
    test('seals scroll without password', () {
      final scroll = Scroll.create('/test', {'secret': 'data'});
      final result = sealScroll(scroll);

      expect(result, isA<SealOk<SealedScroll>>());
      final sealed = (result as SealOk<SealedScroll>).value;

      expect(sealed.hasPassword, isFalse);
      expect(sealed.salt, isNull);
      expect(sealed.scrollType, equals(scroll.type_));
    });

    test('seals scroll with password', () {
      final scroll = Scroll.create('/test', {'secret': 'data'});
      final result = sealScroll(scroll, password: 'mypassword');

      expect(result, isA<SealOk<SealedScroll>>());
      final sealed = (result as SealOk<SealedScroll>).value;

      expect(sealed.hasPassword, isTrue);
      expect(sealed.salt, isNotNull);
    });

    test('preserves scroll type', () {
      final scroll = Scroll.typed('/vault/note', {'title': 'Secret'}, 'vault/note@v1');
      final result = sealScroll(scroll);

      expect(result, isA<SealOk<SealedScroll>>());
      final sealed = (result as SealOk<SealedScroll>).value;
      expect(sealed.scrollType, equals('vault/note@v1'));
    });

    test('sets sealedAt timestamp', () {
      final before = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final scroll = Scroll.create('/test', {});
      final result = sealScroll(scroll);
      final after = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      final sealed = (result as SealOk<SealedScroll>).value;
      expect(sealed.sealedAt, greaterThanOrEqualTo(before));
      expect(sealed.sealedAt, lessThanOrEqualTo(after));
    });
  });

  group('unsealScroll', () {
    test('unseals scroll without password', () {
      final original = Scroll.create('/test', {'key': 'value'});
      final sealResult = sealScroll(original);
      final sealed = (sealResult as SealOk<SealedScroll>).value;

      final unsealResult = unsealScroll(sealed);

      expect(unsealResult, isA<SealOk<Scroll>>());
      final recovered = (unsealResult as SealOk<Scroll>).value;

      expect(recovered.key, equals(original.key));
      expect(recovered.data, equals(original.data));
    });

    test('unseals scroll with correct password', () {
      final original = Scroll.create('/test', {'secret': 'data'});
      final sealResult = sealScroll(original, password: 'correct-password');
      final sealed = (sealResult as SealOk<SealedScroll>).value;

      final unsealResult = unsealScroll(sealed, password: 'correct-password');

      expect(unsealResult, isA<SealOk<Scroll>>());
      final recovered = (unsealResult as SealOk<Scroll>).value;
      expect(recovered.data, equals(original.data));
    });

    test('fails with wrong password', () {
      final original = Scroll.create('/test', {'secret': 'data'});
      final sealResult = sealScroll(original, password: 'correct');
      final sealed = (sealResult as SealOk<SealedScroll>).value;

      final unsealResult = unsealScroll(sealed, password: 'wrong');

      expect(unsealResult, isA<SealErr<Scroll>>());
      expect((unsealResult as SealErr<Scroll>).error, isA<DecryptionError>());
    });

    test('fails when password required but not provided', () {
      final original = Scroll.create('/test', {});
      final sealResult = sealScroll(original, password: 'secret');
      final sealed = (sealResult as SealOk<SealedScroll>).value;

      final unsealResult = unsealScroll(sealed); // No password

      expect(unsealResult, isA<SealErr<Scroll>>());
      expect((unsealResult as SealErr<Scroll>).error, isA<DecryptionError>());
    });

    test('preserves scroll metadata through seal/unseal', () {
      final original = Scroll.create('/vault/notes/abc', {'title': 'Test'})
          .withType('vault/note@v1')
          .withSubject('user:local')
          .withVerb('creates');

      final sealResult = sealScroll(original, password: 'test123');
      final sealed = (sealResult as SealOk<SealedScroll>).value;

      final unsealResult = unsealScroll(sealed, password: 'test123');
      final recovered = (unsealResult as SealOk<Scroll>).value;

      expect(recovered.type_, equals(original.type_));
      expect(recovered.metadata.subject, equals(original.metadata.subject));
      expect(recovered.metadata.verb, equals(original.metadata.verb));
    });
  });

  group('URI roundtrip', () {
    test('full seal -> URI -> unseal roundtrip', () {
      final original = Scroll.create('/test', {'message': 'Hello, World!'});

      // Seal
      final sealResult = sealScroll(original, password: 'password123');
      final sealed = (sealResult as SealOk<SealedScroll>).value;

      // Convert to URI
      final uri = sealed.toUri();

      // Parse from URI
      final parsed = SealedScroll.fromUri(uri);

      // Unseal
      final unsealResult = unsealScroll(parsed, password: 'password123');
      final recovered = (unsealResult as SealOk<Scroll>).value;

      expect(recovered.key, equals(original.key));
      expect(recovered.data['message'], equals('Hello, World!'));
    });
  });

  group('SealError types', () {
    test('EncryptionError', () {
      const error = EncryptionError('encryption failed');
      expect(error.message, equals('encryption failed'));
      expect(error.toString(), contains('EncryptionError'));
    });

    test('DecryptionError', () {
      const error = DecryptionError('wrong password');
      expect(error.message, equals('wrong password'));
    });

    test('InvalidFormatError', () {
      const error = InvalidFormatError('bad format');
      expect(error.message, equals('bad format'));
    });

    test('ContentTooLargeError', () {
      const error = ContentTooLargeError('exceeds limit');
      expect(error.message, equals('exceeds limit'));
    });
  });
}
