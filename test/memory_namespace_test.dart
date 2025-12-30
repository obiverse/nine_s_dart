// MemoryNamespace Tests

import 'dart:async';

import 'package:test/test.dart';
import 'package:nine_s/nine_s.dart';

void main() {
  group('MemoryNamespace', () {
    late MemoryNamespace ns;

    setUp(() {
      ns = MemoryNamespace();
    });

    tearDown(() {
      ns.close();
    });

    test('read returns null for non-existent path', () {
      final result = ns.read('/test');
      expect(result.isOk, isTrue);
      expect(result.value, isNull);
    });

    group('write and read', () {
      test('basic write and read', () {
        final writeResult = ns.write('/test', {'foo': 'bar'});
        expect(writeResult.isOk, isTrue);

        final scroll = writeResult.value;
        expect(scroll.key, equals('/test'));
        expect(scroll.data, equals({'foo': 'bar'}));
        expect(scroll.metadata.version, equals(1));

        final readResult = ns.read('/test');
        expect(readResult.value?.data, equals({'foo': 'bar'}));
      });

      test('version increments on update', () {
        final s1 = ns.write('/test', {'v': 1}).value;
        expect(s1.metadata.version, equals(1));

        final s2 = ns.write('/test', {'v': 2}).value;
        expect(s2.metadata.version, equals(2));

        final s3 = ns.write('/test', {'v': 3}).value;
        expect(s3.metadata.version, equals(3));
      });

      test('hash is computed', () {
        final scroll = ns.write('/test', {'foo': 'bar'}).value;
        expect(scroll.metadata.hash, isNotNull);
        expect(scroll.metadata.hash!.length, equals(64));
      });

      test('timestamps are set', () {
        final scroll = ns.write('/test', {'foo': 'bar'}).value;
        expect(scroll.metadata.createdAt, isNotNull);
        expect(scroll.metadata.updatedAt, isNotNull);
      });
    });

    group('writeScroll', () {
      test('preserves type', () {
        final scroll = Scroll.typed('/test', {'foo': 'bar'}, 'test/type@v1');
        final written = ns.writeScroll(scroll).value;

        expect(written.type_, equals('test/type@v1'));
      });

      test('sets version and timestamps', () {
        final scroll = Scroll.create('/test', {'foo': 'bar'});
        final written = ns.writeScroll(scroll).value;

        expect(written.metadata.version, equals(1));
        expect(written.metadata.createdAt, isNotNull);
        expect(written.metadata.updatedAt, isNotNull);
      });
    });

    group('list', () {
      test('returns paths under prefix', () {
        ns.write('/a', {'v': 1});
        ns.write('/a/b', {'v': 2});
        ns.write('/a/b/c', {'v': 3});
        ns.write('/x', {'v': 4});

        final paths = ns.list('/a').value;
        expect(paths.length, equals(3));
        expect(paths, contains('/a'));
        expect(paths, contains('/a/b'));
        expect(paths, contains('/a/b/c'));
        expect(paths, isNot(contains('/x')));
      });

      test('segment boundary security', () {
        ns.write('/wallet/user', {'v': 1});
        ns.write('/wallet/user/data', {'v': 2});
        ns.write('/wallet/user_archive', {'v': 3});
        ns.write('/wallet/user_archive/old', {'v': 4});

        final paths = ns.list('/wallet/user').value;

        expect(paths, contains('/wallet/user'));
        expect(paths, contains('/wallet/user/data'));
        expect(paths, isNot(contains('/wallet/user_archive')));
        expect(paths, isNot(contains('/wallet/user_archive/old')));
        expect(paths.length, equals(2));
      });

      test('root prefix lists all', () {
        ns.write('/a', {'v': 1});
        ns.write('/b', {'v': 2});
        ns.write('/c', {'v': 3});

        final paths = ns.list('/').value;
        expect(paths.length, equals(3));
      });
    });

    group('watch', () {
      test('receives matching events', () async {
        final stream = ns.watch('/test/**').value;
        final events = <Scroll>[];
        final subscription = stream.listen(events.add);

        ns.write('/test/foo', {'event': 1});
        ns.write('/test/bar', {'event': 2});
        ns.write('/other', {'event': 3}); // Should not match

        // Give stream time to process
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(events.length, equals(2));
        expect(events[0].key, equals('/test/foo'));
        expect(events[1].key, equals('/test/bar'));

        await subscription.cancel();
      });

      test('single wildcard matches direct children only', () async {
        final stream = ns.watch('/test/*').value;
        final events = <Scroll>[];
        final subscription = stream.listen(events.add);

        ns.write('/test/foo', {'v': 1}); // Match
        ns.write('/test/bar', {'v': 2}); // Match
        ns.write('/test/foo/deep', {'v': 3}); // No match

        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(events.length, equals(2));
        await subscription.cancel();
      });

      test('multiple watchers', () async {
        final stream1 = ns.watch('/a/**').value;
        final stream2 = ns.watch('/b/**').value;

        final events1 = <Scroll>[];
        final events2 = <Scroll>[];

        final sub1 = stream1.listen(events1.add);
        final sub2 = stream2.listen(events2.add);

        ns.write('/a/foo', {'v': 1});
        ns.write('/b/bar', {'v': 2});
        ns.write('/a/baz', {'v': 3});

        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(events1.length, equals(2));
        expect(events2.length, equals(1));

        await sub1.cancel();
        await sub2.cancel();
      });
    });

    group('close', () {
      test('prevents further operations', () {
        ns.write('/test', {'foo': 'bar'});
        ns.close();

        final result = ns.read('/test');
        expect(result.isErr, isTrue);
        expect(result.errorOrNull, isA<ClosedError>());
      });

      test('closes watch streams', () async {
        final stream = ns.watch('/test/**').value;
        var done = false;
        stream.listen((_) {}, onDone: () => done = true);

        ns.close();

        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(done, isTrue);
      });
    });

    group('convenience methods', () {
      test('length', () {
        expect(ns.length, equals(0));
        ns.write('/a', {'v': 1});
        expect(ns.length, equals(1));
        ns.write('/b', {'v': 2});
        expect(ns.length, equals(2));
      });

      test('containsKey', () {
        expect(ns.containsKey('/test'), isFalse);
        ns.write('/test', {'v': 1});
        expect(ns.containsKey('/test'), isTrue);
      });

      test('clear', () {
        ns.write('/a', {'v': 1});
        ns.write('/b', {'v': 2});
        expect(ns.length, equals(2));

        ns.clear();
        expect(ns.length, equals(0));
      });
    });

    group('error cases', () {
      test('invalid path', () {
        final result = ns.write('no-leading-slash', {'v': 1});
        expect(result.isErr, isTrue);
        expect(result.errorOrNull, isA<InvalidPathError>());
      });

      test('path traversal rejected', () {
        final result = ns.write('/foo/../bar', {'v': 1});
        expect(result.isErr, isTrue);
        expect(result.errorOrNull, isA<InvalidPathError>());
      });
    });
  });
}
