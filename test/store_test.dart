// Store Tests - Encrypted Sovereign Storage

import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:nine_s/nine_s.dart';

void main() {
  late Directory tempDir;
  late Store store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('store_test_');
    final key = Store.testKey();
    store = await Store.open(tempDir.path, key);
  });

  tearDown(() async {
    store.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Store', () {
    group('open', () {
      test('creates store with valid key', () async {
        final key = Store.testKey();
        final s = await Store.open('${tempDir.path}/new', key);

        expect(s.isEncrypted, isTrue);
        expect(s.path, equals('${tempDir.path}/new'));

        s.close();
      });

      test('throws on invalid key length', () async {
        expect(
          () => Store.open('${tempDir.path}/bad', Uint8List(16)),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('creates directory structure', () async {
        final key = Store.testKey();
        final path = '${tempDir.path}/structured';
        final s = await Store.open(path, key);

        expect(Directory('$path/_scrolls').existsSync(), isTrue);
        expect(Directory('$path/_history').existsSync(), isTrue);

        s.close();
      });
    });

    group('openForApp', () {
      test('derives unique key per app', () async {
        final masterKey = Store.testKey();

        final walletStore = await Store.openForApp(
          '${tempDir.path}/wallet',
          masterKey,
          'wallet',
        );

        final vaultStore = await Store.openForApp(
          '${tempDir.path}/vault',
          masterKey,
          'vault',
        );

        // Write same data to both
        walletStore.write('/test', {'value': 42});
        vaultStore.write('/test', {'value': 42});

        // Files should be encrypted with different keys
        final walletFile = File('${tempDir.path}/wallet/_scrolls/test.json');
        final vaultFile = File('${tempDir.path}/vault/_scrolls/test.json');

        expect(walletFile.readAsBytesSync(), isNot(equals(vaultFile.readAsBytesSync())));

        walletStore.close();
        vaultStore.close();
      });
    });

    group('read and write', () {
      test('basic write and read', () {
        final writeResult = store.write('/test/scroll', {'key': 'value'});

        expect(writeResult.isOk, isTrue);
        final written = writeResult.value;
        expect(written.key, equals('/test/scroll'));
        expect(written.data['key'], equals('value'));

        final readResult = store.read('/test/scroll');
        expect(readResult.isOk, isTrue);
        expect(readResult.value, isNotNull);
        expect(readResult.value!.data['key'], equals('value'));
      });

      test('read returns null for non-existent path', () {
        final result = store.read('/nonexistent');

        expect(result.isOk, isTrue);
        expect(result.value, isNull);
      });

      test('data is encrypted at rest', () {
        store.write('/secret', {'password': 'super-secret-123'});

        // Read the raw file
        final file = File('${tempDir.path}/_scrolls/secret.json');
        final rawBytes = file.readAsBytesSync();

        // Should not contain plaintext
        final rawString = String.fromCharCodes(rawBytes);
        expect(rawString.contains('super-secret-123'), isFalse);
        expect(rawString.contains('password'), isFalse);
      });

      test('version increments on update', () {
        store.write('/test', {'v': 1});
        final v1 = store.read('/test').value!;
        expect(v1.metadata.version, equals(1));

        store.write('/test', {'v': 2});
        final v2 = store.read('/test').value!;
        expect(v2.metadata.version, equals(2));

        store.write('/test', {'v': 3});
        final v3 = store.read('/test').value!;
        expect(v3.metadata.version, equals(3));
      });

      test('preserves createdAt across updates', () {
        store.write('/test', {'v': 1});
        final v1 = store.read('/test').value!;
        final createdAt = v1.metadata.createdAt;

        // Wait a tiny bit
        Future.delayed(Duration(milliseconds: 10));

        store.write('/test', {'v': 2});
        final v2 = store.read('/test').value!;

        expect(v2.metadata.createdAt, equals(createdAt));
        expect(v2.metadata.updatedAt, greaterThanOrEqualTo(createdAt!));
      });
    });

    group('writeScroll', () {
      test('preserves scroll type', () {
        final scroll = Scroll.typed('/vault/note', {'title': 'Test'}, 'vault/note@v1');
        final result = store.writeScroll(scroll);

        expect(result.isOk, isTrue);
        expect(result.value.type_, equals('vault/note@v1'));

        final read = store.read('/vault/note').value!;
        expect(read.type_, equals('vault/note@v1'));
      });
    });

    group('list', () {
      test('lists paths under prefix', () {
        store.write('/wallet/balance', {'sats': 100});
        store.write('/wallet/tx/1', {'amount': 50});
        store.write('/wallet/tx/2', {'amount': 25});
        store.write('/vault/note', {'title': 'Secret'});

        final result = store.list('/wallet');

        expect(result.isOk, isTrue);
        final paths = result.value;
        expect(paths, contains('/wallet/balance'));
        expect(paths, contains('/wallet/tx/1'));
        expect(paths, contains('/wallet/tx/2'));
        expect(paths, isNot(contains('/vault/note')));
      });

      test('returns empty list for no matches', () {
        store.write('/wallet/balance', {});

        final result = store.list('/vault');

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });
    });

    group('watch', () {
      test('receives events for matching paths', () async {
        final watchResult = store.watch('/wallet/**');
        expect(watchResult.isOk, isTrue);

        final events = <Scroll>[];
        final subscription = watchResult.value.listen(events.add);

        store.write('/wallet/balance', {'sats': 100});
        store.write('/wallet/tx/1', {'amount': 50});
        store.write('/vault/note', {'title': 'Ignored'});

        // Allow events to propagate
        await Future.delayed(Duration(milliseconds: 50));

        expect(events.length, equals(2));
        expect(events.any((s) => s.key == '/wallet/balance'), isTrue);
        expect(events.any((s) => s.key == '/wallet/tx/1'), isTrue);

        await subscription.cancel();
      });
    });

    group('history', () {
      test('records patches for each write', () {
        store.write('/test', {'v': 1});
        store.write('/test', {'v': 2});
        store.write('/test', {'v': 3});

        final patches = store.history('/test');

        expect(patches.length, equals(3));
        expect(patches[0].seq, equals(1));
        expect(patches[1].seq, equals(2));
        expect(patches[2].seq, equals(3));
      });

      test('returns empty list for no history', () {
        final patches = store.history('/nonexistent');
        expect(patches, isEmpty);
      });
    });

    group('anchor', () {
      test('creates checkpoint', () {
        store.write('/test', {'state': 'important'});

        final result = store.anchor('/test', label: 'checkpoint-1');

        expect(result.isOk, isTrue);
        final anchor = result.value;
        expect(anchor.label, equals('checkpoint-1'));
        expect(anchor.scroll.data['state'], equals('important'));
      });

      test('fails for non-existent scroll', () {
        final result = store.anchor('/nonexistent');

        expect(result.isErr, isTrue);
        expect(result.errorOrNull, isA<NotFoundError>());
      });
    });

    group('anchors', () {
      test('lists all anchors', () {
        store.write('/test', {'v': 1});
        store.anchor('/test', label: 'v1');

        store.write('/test', {'v': 2});
        store.anchor('/test', label: 'v2');

        final anchors = store.anchors('/test');

        expect(anchors.length, equals(2));
        expect(anchors[0].label, equals('v1'));
        expect(anchors[1].label, equals('v2'));
      });
    });

    group('restore', () {
      test('restores to anchored state', () {
        store.write('/test', {'state': 'original'});
        store.anchor('/test', label: 'original');

        store.write('/test', {'state': 'modified'});
        expect(store.read('/test').value!.data['state'], equals('modified'));

        final anchors = store.anchors('/test');
        final result = store.restore('/test', anchors[0].id);

        expect(result.isOk, isTrue);
        expect(store.read('/test').value!.data['state'], equals('original'));
      });

      test('fails for non-existent anchor', () {
        store.write('/test', {});

        final result = store.restore('/test', 'fake-anchor-id');

        expect(result.isErr, isTrue);
        expect(result.errorOrNull, isA<NotFoundError>());
      });
    });

    group('stateAt', () {
      test('reconstructs state at sequence', () {
        store.write('/test', {'count': 1});
        store.write('/test', {'count': 2});
        store.write('/test', {'count': 3});

        final atSeq1 = store.stateAt('/test', 1);
        final atSeq2 = store.stateAt('/test', 2);
        final atSeq3 = store.stateAt('/test', 3);

        expect(atSeq1.isOk, isTrue);
        expect(atSeq2.isOk, isTrue);
        expect(atSeq3.isOk, isTrue);
      });

      test('fails for invalid sequence', () {
        store.write('/test', {});

        final result = store.stateAt('/test', 999);

        expect(result.isErr, isTrue);
      });
    });

    group('close', () {
      test('prevents further operations', () async {
        final key = Store.testKey();
        final s = await Store.open('${tempDir.path}/close-test', key);

        s.close();

        expect(s.read('/test').isErr, isTrue);
        expect(s.write('/test', {}).isErr, isTrue);
        expect(s.list('/').isErr, isTrue);
        expect(s.watch('/**').isErr, isTrue);
      });
    });

    group('path validation', () {
      test('rejects invalid paths', () {
        expect(store.read('no-leading-slash').isErr, isTrue);
        expect(store.write('invalid', {}).isErr, isTrue);
      });

      test('rejects path traversal', () {
        expect(store.read('/../etc/passwd').isErr, isTrue);
        expect(store.write('/test/../secret', {}).isErr, isTrue);
      });
    });
  });
}
