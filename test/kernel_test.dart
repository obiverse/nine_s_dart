// Kernel Tests

import 'dart:async';

import 'package:test/test.dart';
import 'package:nine_s/nine_s.dart';

void main() {
  group('Kernel', () {
    late Kernel kernel;
    late MemoryNamespace walletNs;
    late MemoryNamespace vaultNs;

    setUp(() {
      kernel = Kernel();
      walletNs = MemoryNamespace();
      vaultNs = MemoryNamespace();

      kernel
        ..mount('/wallet', walletNs)
        ..mount('/vault', vaultNs);
    });

    tearDown(() {
      kernel.close();
    });

    test('routes to correct namespace', () {
      kernel.write('/wallet/balance', {'confirmed': 100000});
      kernel.write('/vault/notes/abc', {'title': 'Secret'});

      // Check data is in correct namespace
      expect(walletNs.containsKey('/balance'), isTrue);
      expect(vaultNs.containsKey('/notes/abc'), isTrue);

      // Cross-check: vault shouldn't have wallet data
      expect(vaultNs.containsKey('/balance'), isFalse);
      expect(walletNs.containsKey('/notes/abc'), isFalse);
    });

    test('read restores full path', () {
      kernel.write('/wallet/balance', {'confirmed': 100000});
      final result = kernel.read('/wallet/balance');

      expect(result.isOk, isTrue);
      expect(result.value?.key, equals('/wallet/balance'));
      expect(result.value?.data['confirmed'], equals(100000));
    });

    test('write restores full path', () {
      final result = kernel.write('/wallet/balance', {'confirmed': 100000});

      expect(result.isOk, isTrue);
      expect(result.value.key, equals('/wallet/balance'));
    });

    group('longest prefix match', () {
      test('deeper mounts take precedence', () {
        final txNs = MemoryNamespace();
        kernel.mount('/wallet/transactions', txNs);

        kernel.write('/wallet/balance', {'confirmed': 100000});
        kernel.write('/wallet/transactions/abc', {'amount': 50000});

        // /wallet/balance goes to walletNs
        expect(walletNs.containsKey('/balance'), isTrue);

        // /wallet/transactions/abc goes to txNs
        expect(txNs.containsKey('/abc'), isTrue);
        expect(walletNs.containsKey('/transactions/abc'), isFalse);
      });
    });

    group('segment boundary security', () {
      test('mount /foo does not capture /foobar', () {
        final fooNs = MemoryNamespace();
        final foobarNs = MemoryNamespace();

        kernel.mount('/foo', fooNs);
        kernel.mount('/foobar', foobarNs);

        kernel.write('/foo/data', {'v': 1});
        kernel.write('/foobar/data', {'v': 2});

        expect(fooNs.containsKey('/data'), isTrue);
        expect(foobarNs.containsKey('/data'), isTrue);

        // Verify isolation
        expect(fooNs.read('/data').value?.data['v'], equals(1));
        expect(foobarNs.read('/data').value?.data['v'], equals(2));
      });
    });

    group('list', () {
      test('restores paths with mount prefix', () {
        kernel.write('/wallet/a', {'v': 1});
        kernel.write('/wallet/b', {'v': 2});
        kernel.write('/vault/c', {'v': 3});

        final walletPaths = kernel.list('/wallet').value;
        expect(walletPaths, contains('/wallet/a'));
        expect(walletPaths, contains('/wallet/b'));
        expect(walletPaths, isNot(contains('/vault/c')));
      });
    });

    group('writeScroll', () {
      test('preserves type and restores path', () {
        final scroll = Scroll.typed(
          '/wallet/balance',
          {'confirmed': 100000},
          'wallet/balance@v1',
        );

        final result = kernel.writeScroll(scroll);

        expect(result.isOk, isTrue);
        expect(result.value.key, equals('/wallet/balance'));
        expect(result.value.type_, equals('wallet/balance@v1'));
      });
    });

    group('watch', () {
      test('receives events with full paths', () async {
        final stream = kernel.watch('/wallet/**').value;
        final events = <Scroll>[];
        final subscription = stream.listen(events.add);

        kernel.write('/wallet/balance', {'confirmed': 100000});
        kernel.write('/wallet/tx/abc', {'amount': 50000});

        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(events.length, equals(2));
        expect(events[0].key, equals('/wallet/balance'));
        expect(events[1].key, equals('/wallet/tx/abc'));

        await subscription.cancel();
      });
    });

    group('unmount', () {
      test('removes namespace', () {
        kernel.write('/wallet/balance', {'confirmed': 100000});
        expect(kernel.read('/wallet/balance').isOk, isTrue);

        final removed = kernel.unmount('/wallet');
        expect(removed, equals(walletNs));

        final result = kernel.read('/wallet/balance');
        expect(result.isErr, isTrue);
        expect(result.errorOrNull, isA<NotFoundError>());
      });
    });

    group('error cases', () {
      test('no namespace mounted', () {
        final result = kernel.read('/unknown/path');
        expect(result.isErr, isTrue);
        expect(result.errorOrNull, isA<NotFoundError>());
      });

      test('after close', () {
        kernel.close();
        final result = kernel.read('/wallet/balance');
        expect(result.isErr, isTrue);
        expect(result.errorOrNull, isA<ClosedError>());
      });
    });

    group('root mount', () {
      test('root namespace catches all', () {
        final rootNs = MemoryNamespace();
        final k = Kernel()..mount('/', rootNs);

        k.write('/anything', {'v': 1});
        k.write('/nested/path', {'v': 2});

        expect(rootNs.containsKey('/anything'), isTrue);
        expect(rootNs.containsKey('/nested/path'), isTrue);

        k.close();
      });

      test('specific mounts override root', () {
        final rootNs = MemoryNamespace();
        final specificNs = MemoryNamespace();

        final k = Kernel()
          ..mount('/', rootNs)
          ..mount('/specific', specificNs);

        k.write('/other', {'v': 1}); // Goes to root
        k.write('/specific/data', {'v': 2}); // Goes to specific

        expect(rootNs.containsKey('/other'), isTrue);
        expect(specificNs.containsKey('/data'), isTrue);
        expect(rootNs.containsKey('/specific/data'), isFalse);

        k.close();
      });
    });
  });
}
