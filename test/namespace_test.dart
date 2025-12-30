// Namespace and Path Utilities Tests

import 'package:test/test.dart';
import 'package:nine_s/nine_s.dart';

void main() {
  group('validatePath', () {
    test('valid paths', () {
      expect(validatePath('/').isOk, isTrue);
      expect(validatePath('/test').isOk, isTrue);
      expect(validatePath('/foo/bar').isOk, isTrue);
      expect(validatePath('/foo/bar/baz').isOk, isTrue);
      expect(validatePath('/foo_bar').isOk, isTrue);
      expect(validatePath('/foo-bar').isOk, isTrue);
      expect(validatePath('/foo.bar').isOk, isTrue);
    });

    test('invalid paths', () {
      expect(validatePath('').isErr, isTrue);
      expect(validatePath('foo').isErr, isTrue);
      expect(validatePath('foo/bar').isErr, isTrue);
    });

    group('path traversal security', () {
      test('rejects .. segments', () {
        expect(validatePath('/..').isErr, isTrue);
        expect(validatePath('/../etc').isErr, isTrue);
        expect(validatePath('/foo/..').isErr, isTrue);
        expect(validatePath('/foo/../bar').isErr, isTrue);
        expect(validatePath('/foo/../../etc/passwd').isErr, isTrue);
      });

      test('rejects . segments', () {
        expect(validatePath('/.').isErr, isTrue);
        expect(validatePath('/./foo').isErr, isTrue);
        expect(validatePath('/foo/.').isErr, isTrue);
        expect(validatePath('/foo/./bar').isErr, isTrue);
      });

      test('allows dots in names', () {
        expect(validatePath('/foo.bar').isOk, isTrue);
        expect(validatePath('/foo.bar.baz').isOk, isTrue);
        expect(validatePath('/.hidden').isOk, isTrue);
        expect(validatePath('/foo/.hidden').isOk, isTrue);
      });
    });
  });

  group('pathMatches', () {
    test('exact match', () {
      expect(pathMatches('/foo', '/foo'), isTrue);
      expect(pathMatches('/foo', '/bar'), isFalse);
    });

    test('single wildcard', () {
      expect(pathMatches('/foo/bar', '/foo/*'), isTrue);
      expect(pathMatches('/foo/bar/baz', '/foo/*'), isFalse);
      expect(pathMatches('/foo', '/foo/*'), isFalse);
    });

    test('recursive wildcard', () {
      expect(pathMatches('/foo/bar', '/foo/**'), isTrue);
      expect(pathMatches('/foo/bar/baz', '/foo/**'), isTrue);
      expect(pathMatches('/foo/bar/baz/qux', '/foo/**'), isTrue);
      expect(pathMatches('/bar/foo', '/foo/**'), isFalse);
    });
  });

  group('isPathUnderPrefix', () {
    test('exact match', () {
      expect(isPathUnderPrefix('/foo', '/foo'), isTrue);
    });

    test('child paths', () {
      expect(isPathUnderPrefix('/foo/bar', '/foo'), isTrue);
      expect(isPathUnderPrefix('/foo/bar/baz', '/foo'), isTrue);
    });

    test('root prefix', () {
      expect(isPathUnderPrefix('/anything', '/'), isTrue);
    });

    test('segment boundary security', () {
      // CRITICAL: /foo should NOT match /foobar
      expect(isPathUnderPrefix('/foobar', '/foo'), isFalse);
      expect(isPathUnderPrefix('/foobar/baz', '/foo'), isFalse);

      // But /foo/bar should still match /foo
      expect(isPathUnderPrefix('/foo/bar', '/foo'), isTrue);
    });

    test('different paths', () {
      expect(isPathUnderPrefix('/bar', '/foo'), isFalse);
    });
  });

  group('normalizeMountPath', () {
    test('adds leading slash', () {
      expect(normalizeMountPath('foo'), equals('/foo'));
    });

    test('removes trailing slashes', () {
      expect(normalizeMountPath('/foo/'), equals('/foo'));
      expect(normalizeMountPath('/foo//'), equals('/foo'));
    });

    test('preserves root', () {
      expect(normalizeMountPath('/'), equals('/'));
    });

    test('already normalized', () {
      expect(normalizeMountPath('/foo'), equals('/foo'));
    });
  });

  group('Result', () {
    test('Ok properties', () {
      const result = Ok(42);
      expect(result.isOk, isTrue);
      expect(result.isErr, isFalse);
      expect(result.value, equals(42));
      expect(result.valueOrNull, equals(42));
      expect(result.errorOrNull, isNull);
    });

    test('Err properties', () {
      const result = Err<int>(NotFoundError('test'));
      expect(result.isOk, isFalse);
      expect(result.isErr, isTrue);
      expect(result.valueOrNull, isNull);
      expect(result.errorOrNull, isA<NotFoundError>());
    });

    test('value throws on Err', () {
      const result = Err<int>(NotFoundError('test'));
      expect(() => result.value, throwsA(isA<NotFoundError>()));
    });

    test('map transforms Ok', () {
      const result = Ok(21);
      final doubled = result.map((x) => x * 2);
      expect(doubled.value, equals(42));
    });

    test('map preserves Err', () {
      const result = Err<int>(NotFoundError('test'));
      final doubled = result.map((x) => x * 2);
      expect(doubled.isErr, isTrue);
    });

    test('flatMap chains', () {
      Result<int> parse(String s) {
        final n = int.tryParse(s);
        return n != null ? Ok(n) : const Err(InvalidDataError('not a number'));
      }

      final result = const Ok('42').flatMap(parse);
      expect(result.value, equals(42));

      final failed = const Ok('abc').flatMap(parse);
      expect(failed.isErr, isTrue);
    });
  });
}
