// FileNamespace Tests - Filesystem-backed 9S Namespace

import 'dart:io';

import 'package:test/test.dart';
import 'package:nine_s/nine_s.dart';

void main() {
  late Directory tempDir;
  late FileNamespace ns;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('file_ns_test_');
    ns = FileNamespace(tempDir.path);
  });

  tearDown(() async {
    ns.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('FileNamespace', () {
    group('constructor', () {
      test('creates directory structure', () {
        expect(Directory('${tempDir.path}/_scrolls').existsSync(), isTrue);
      });

      test('path getter returns root path', () {
        expect(ns.path, equals(tempDir.path));
      });
    });

    group('write and read', () {
      test('basic write and read', () {
        final writeResult = ns.write('/test', {'key': 'value'});

        expect(writeResult.isOk, isTrue);
        final written = writeResult.value;
        expect(written.key, equals('/test'));
        expect(written.data['key'], equals('value'));

        final readResult = ns.read('/test');
        expect(readResult.isOk, isTrue);
        expect(readResult.value, isNotNull);
        expect(readResult.value!.data['key'], equals('value'));
      });

      test('read returns null for non-existent path', () {
        final result = ns.read('/nonexistent');

        expect(result.isOk, isTrue);
        expect(result.value, isNull);
      });

      test('stores as JSON file', () {
        ns.write('/test/scroll', {'data': 123});

        final file = File('${tempDir.path}/_scrolls/test/scroll.json');
        expect(file.existsSync(), isTrue);

        final content = file.readAsStringSync();
        expect(content, contains('"data":123'));
      });

      test('version increments on update', () {
        ns.write('/test', {'v': 1});
        final v1 = ns.read('/test').value!;
        expect(v1.metadata.version, equals(1));

        ns.write('/test', {'v': 2});
        final v2 = ns.read('/test').value!;
        expect(v2.metadata.version, equals(2));
      });

      test('computes hash on write', () {
        final result = ns.write('/test', {'value': 42});

        expect(result.value.metadata.hash, isNotNull);
        expect(result.value.metadata.hash!.length, equals(64));
      });

      test('preserves createdAt across updates', () {
        ns.write('/test', {'v': 1});
        final v1 = ns.read('/test').value!;
        final createdAt = v1.metadata.createdAt;

        ns.write('/test', {'v': 2});
        final v2 = ns.read('/test').value!;

        expect(v2.metadata.createdAt, equals(createdAt));
      });
    });

    group('writeScroll', () {
      test('preserves scroll type', () {
        final scroll = Scroll.typed('/test', {'data': 1}, 'custom/type@v1');
        final result = ns.writeScroll(scroll);

        expect(result.isOk, isTrue);
        expect(result.value.type_, equals('custom/type@v1'));

        final read = ns.read('/test').value!;
        expect(read.type_, equals('custom/type@v1'));
      });

      test('sets version and timestamps', () {
        final scroll = Scroll.create('/test', {});
        final result = ns.writeScroll(scroll);

        expect(result.value.metadata.version, equals(1));
        expect(result.value.metadata.createdAt, isNotNull);
        expect(result.value.metadata.updatedAt, isNotNull);
      });
    });

    group('list', () {
      test('returns paths under prefix', () {
        ns.write('/wallet/balance', {});
        ns.write('/wallet/tx/1', {});
        ns.write('/wallet/tx/2', {});
        ns.write('/vault/note', {});

        final result = ns.list('/wallet');

        expect(result.isOk, isTrue);
        final paths = result.value;
        expect(paths, contains('/wallet/balance'));
        expect(paths, contains('/wallet/tx/1'));
        expect(paths, contains('/wallet/tx/2'));
        expect(paths, isNot(contains('/vault/note')));
      });

      test('returns empty list for no matches', () {
        ns.write('/wallet/balance', {});

        final result = ns.list('/vault');

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });

      test('root prefix lists all', () {
        ns.write('/a', {});
        ns.write('/b/c', {});
        ns.write('/d/e/f', {});

        final result = ns.list('/');

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(3));
      });
    });

    group('watch', () {
      test('receives events for matching paths', () async {
        final watchResult = ns.watch('/wallet/**');
        expect(watchResult.isOk, isTrue);

        final events = <Scroll>[];
        final subscription = watchResult.value.listen(events.add);

        ns.write('/wallet/balance', {'sats': 100});
        ns.write('/wallet/tx/1', {});
        ns.write('/vault/note', {}); // Should not match

        await Future.delayed(const Duration(milliseconds: 50));

        expect(events.length, equals(2));
        expect(events.any((s) => s.key == '/wallet/balance'), isTrue);
        expect(events.any((s) => s.key == '/wallet/tx/1'), isTrue);

        await subscription.cancel();
      });

      test('single wildcard matches direct children only', () async {
        final watchResult = ns.watch('/wallet/*');
        expect(watchResult.isOk, isTrue);

        final events = <Scroll>[];
        final subscription = watchResult.value.listen(events.add);

        ns.write('/wallet/balance', {});
        ns.write('/wallet/tx/1', {}); // Should not match (nested)

        await Future.delayed(const Duration(milliseconds: 50));

        expect(events.length, equals(1));
        expect(events[0].key, equals('/wallet/balance'));

        await subscription.cancel();
      });
    });

    group('close', () {
      test('prevents further operations', () {
        ns.close();

        expect(ns.read('/test').isErr, isTrue);
        expect(ns.write('/test', {}).isErr, isTrue);
        expect(ns.list('/').isErr, isTrue);
        expect(ns.watch('/**').isErr, isTrue);
      });

      test('closes watch streams', () async {
        final watchResult = ns.watch('/**');
        final stream = watchResult.value;

        var closed = false;
        stream.listen(null, onDone: () => closed = true);

        ns.close();

        await Future.delayed(const Duration(milliseconds: 50));
        expect(closed, isTrue);
      });
    });

    group('convenience methods', () {
      test('delete removes scroll', () {
        ns.write('/test', {'data': 1});
        expect(ns.exists('/test'), isTrue);

        final result = ns.delete('/test');

        expect(result.isOk, isTrue);
        expect(result.value, isTrue);
        expect(ns.exists('/test'), isFalse);
      });

      test('delete returns false for non-existent', () {
        final result = ns.delete('/nonexistent');

        expect(result.isOk, isTrue);
        expect(result.value, isFalse);
      });

      test('exists checks path', () {
        expect(ns.exists('/test'), isFalse);

        ns.write('/test', {});

        expect(ns.exists('/test'), isTrue);
      });

      test('length returns scroll count', () {
        expect(ns.length, equals(0));

        ns.write('/a', {});
        ns.write('/b', {});
        ns.write('/c/d', {});

        expect(ns.length, equals(3));
      });

      test('clear removes all scrolls', () {
        ns.write('/a', {});
        ns.write('/b', {});
        expect(ns.length, equals(2));

        ns.clear();

        expect(ns.length, equals(0));
      });
    });

    group('path validation', () {
      test('rejects invalid paths', () {
        expect(ns.read('no-leading-slash').isErr, isTrue);
        expect(ns.write('invalid', {}).isErr, isTrue);
      });

      test('rejects path traversal', () {
        expect(ns.read('/../etc/passwd').isErr, isTrue);
        expect(ns.write('/test/../secret', {}).isErr, isTrue);
      });
    });

    group('persistence', () {
      test('data persists across instances', () {
        ns.write('/persistent', {'value': 42});
        ns.close();

        // Create new instance pointing to same directory
        final ns2 = FileNamespace(tempDir.path);
        final result = ns2.read('/persistent');

        expect(result.isOk, isTrue);
        expect(result.value, isNotNull);
        expect(result.value!.data['value'], equals(42));

        ns2.close();
      });
    });
  });
}
