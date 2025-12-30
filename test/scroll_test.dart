// Scroll Tests
//
// ## Dart Lesson: Testing
//
// Dart uses the `test` package. Key concepts:
//
// - `group()` - Organize related tests
// - `test()` - Single test case
// - `expect()` - Assert conditions
// - `setUp()` / `tearDown()` - Before/after each test
// - `setUpAll()` / `tearDownAll()` - Before/after all tests in group
//
// Run tests with: `dart test`
// Run specific file: `dart test test/scroll_test.dart`
// Run with coverage: `dart test --coverage=coverage`

import 'package:test/test.dart';
import 'package:nine_s/nine_s.dart';

void main() {
  group('Scroll', () {
    test('creates with key and data', () {
      const scroll = Scroll(
        key: '/test',
        data: {'foo': 'bar'},
      );

      expect(scroll.key, equals('/test'));
      expect(scroll.data, equals({'foo': 'bar'}));
      expect(scroll.type_, equals(ScrollTypes.generic));
    });

    test('factory constructors work', () {
      // Scroll.create
      final s1 = Scroll.create('/test', {'value': 1});
      expect(s1.key, equals('/test'));

      // Scroll.typed (factory, not const)
      final s2 = Scroll.typed('/test', {'value': 1}, 'custom/type@v1');
      expect(s2.type_, equals('custom/type@v1'));

      // Scroll.empty
      final s3 = Scroll.empty('/test');
      expect(s3.data, isEmpty);
    });

    test('copyWith creates modified copy', () {
      const original = Scroll(key: '/test', data: {'a': 1});

      final modified = original.copyWith(
        key: '/new',
        data: {'b': 2},
      );

      // Original unchanged
      expect(original.key, equals('/test'));
      expect(original.data, equals({'a': 1}));

      // Modified has new values
      expect(modified.key, equals('/new'));
      expect(modified.data, equals({'b': 2}));
    });

    group('builder pattern', () {
      test('linguistic metadata', () {
        final scroll = Scroll.create('/vault/notes/abc', {'title': 'Test'})
            .withSubject('user:local')
            .withVerb(Verbs.creates)
            .withTense(Tense.past)
            .withObject('/vault/notes/abc');

        expect(scroll.metadata.subject, equals('user:local'));
        expect(scroll.metadata.verb, equals('creates'));
        expect(scroll.metadata.tense, equals(Tense.past));
        expect(scroll.metadata.object, equals('/vault/notes/abc'));
      });

      test('taxonomic metadata', () {
        final scroll = Scroll.create('/wallet/tx/123', {'amount': 50000})
            .withKingdom(Kingdoms.financial)
            .withPhylum('bitcoin')
            .withClass('transaction');

        expect(scroll.metadata.kingdom, equals('financial'));
        expect(scroll.metadata.phylum, equals('bitcoin'));
        expect(scroll.metadata.class_, equals('transaction'));
      });

      test('extensions', () {
        final scroll = Scroll.create('/vault/notes/abc', {})
            .withExtension('pinned', true)
            .withExtension('folder', 'work');

        expect(scroll.metadata.extensions['pinned'], isTrue);
        expect(scroll.metadata.extensions['folder'], equals('work'));
      });
    });

    group('data accessors', () {
      test('getString', () {
        final scroll = Scroll.create('/test', {
          'name': 'Alice',
          'count': 42,
        });

        expect(scroll.getString('name'), equals('Alice'));
        expect(scroll.getString('missing'), isNull);
        expect(scroll.getStringOr('missing', 'default'), equals('default'));
      });

      test('getInt', () {
        final scroll = Scroll.create('/test', {
          'count': 42,
          'price': 19.99,
        });

        expect(scroll.getInt('count'), equals(42));
        expect(scroll.getInt('price'), equals(19)); // Truncates double
        expect(scroll.getInt('missing'), isNull);
      });

      test('getBool', () {
        final scroll = Scroll.create('/test', {
          'active': true,
          'disabled': false,
        });

        expect(scroll.getBool('active'), isTrue);
        expect(scroll.getBool('disabled'), isFalse);
        expect(scroll.getBool('missing'), isNull);
      });
    });

    group('lifecycle', () {
      test('markDeleted and isDeleted', () {
        final scroll = Scroll.create('/test', {});
        expect(scroll.isDeleted, isFalse);

        final deleted = scroll.markDeleted();
        expect(deleted.isDeleted, isTrue);

        final restored = deleted.unmarkDeleted();
        expect(restored.isDeleted, isFalse);
      });

      test('finalize sets timestamps and hash', () {
        final scroll = Scroll.create('/test', {'value': 42});
        final finalized = scroll.finalize();

        expect(finalized.metadata.createdAt, isNotNull);
        expect(finalized.metadata.updatedAt, isNotNull);
        expect(finalized.metadata.hash, isNotNull);
        expect(finalized.metadata.hash!.length, equals(64)); // SHA-256 hex
      });

      test('incrementVersion', () {
        final scroll = Scroll.create('/test', {});
        expect(scroll.metadata.version, equals(0));

        final v1 = scroll.incrementVersion();
        expect(v1.metadata.version, equals(1));

        final v2 = v1.incrementVersion();
        expect(v2.metadata.version, equals(2));
      });
    });

    group('serialization', () {
      test('toJson and fromJson roundtrip', () {
        final scroll = Scroll.create('/vault/notes/abc', {'title': 'Test'})
            .withType('vault/note@v1')
            .withSubject('user:local')
            .finalize();

        final json = scroll.toJson();
        final parsed = Scroll.fromJson(json);

        expect(parsed.key, equals(scroll.key));
        expect(parsed.type_, equals(scroll.type_));
        expect(parsed.data, equals(scroll.data));
        expect(parsed.metadata.subject, equals(scroll.metadata.subject));
      });
    });

    group('equality', () {
      test('equal scrolls are equal', () {
        const s1 = Scroll(key: '/test', data: {'a': 1});
        const s2 = Scroll(key: '/test', data: {'a': 1});

        expect(s1, equals(s2));
        expect(s1.hashCode, equals(s2.hashCode));
      });

      test('different keys are not equal', () {
        const s1 = Scroll(key: '/test1', data: {'a': 1});
        const s2 = Scroll(key: '/test2', data: {'a': 1});

        expect(s1, isNot(equals(s2)));
      });

      test('different data are not equal', () {
        const s1 = Scroll(key: '/test', data: {'a': 1});
        const s2 = Scroll(key: '/test', data: {'a': 2});

        expect(s1, isNot(equals(s2)));
      });
    });
  });
}
