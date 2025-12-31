// Patch Tests - RFC 6902 JSON Patch Implementation
//
// Tests for the git-like diff primitives for Scrolls.

import 'package:test/test.dart';
import 'package:nine_s/nine_s.dart';

void main() {
  group('PatchOp', () {
    test('AddOp serializes correctly', () {
      const op = AddOp(path: '/foo/bar', value: 42);
      final json = op.toJson();

      expect(json['op'], equals('add'));
      expect(json['path'], equals('/foo/bar'));
      expect(json['value'], equals(42));
    });

    test('RemoveOp serializes correctly', () {
      const op = RemoveOp(path: '/foo/bar');
      final json = op.toJson();

      expect(json['op'], equals('remove'));
      expect(json['path'], equals('/foo/bar'));
    });

    test('ReplaceOp serializes correctly', () {
      const op = ReplaceOp(path: '/foo', value: {'new': 'value'});
      final json = op.toJson();

      expect(json['op'], equals('replace'));
      expect(json['path'], equals('/foo'));
      expect(json['value'], equals({'new': 'value'}));
    });

    test('MoveOp serializes correctly', () {
      const op = MoveOp(from: '/old', path: '/new');
      final json = op.toJson();

      expect(json['op'], equals('move'));
      expect(json['from'], equals('/old'));
      expect(json['path'], equals('/new'));
    });

    test('CopyOp serializes correctly', () {
      const op = CopyOp(from: '/source', path: '/dest');
      final json = op.toJson();

      expect(json['op'], equals('copy'));
      expect(json['from'], equals('/source'));
      expect(json['path'], equals('/dest'));
    });

    test('TestOp serializes correctly', () {
      const op = TestOp(path: '/check', value: 'expected');
      final json = op.toJson();

      expect(json['op'], equals('test'));
      expect(json['path'], equals('/check'));
      expect(json['value'], equals('expected'));
    });

    test('fromJson parses all operation types', () {
      expect(
        PatchOp.fromJson({'op': 'add', 'path': '/a', 'value': 1}),
        isA<AddOp>(),
      );
      expect(
        PatchOp.fromJson({'op': 'remove', 'path': '/a'}),
        isA<RemoveOp>(),
      );
      expect(
        PatchOp.fromJson({'op': 'replace', 'path': '/a', 'value': 2}),
        isA<ReplaceOp>(),
      );
      expect(
        PatchOp.fromJson({'op': 'move', 'from': '/a', 'path': '/b'}),
        isA<MoveOp>(),
      );
      expect(
        PatchOp.fromJson({'op': 'copy', 'from': '/a', 'path': '/b'}),
        isA<CopyOp>(),
      );
      expect(
        PatchOp.fromJson({'op': 'test', 'path': '/a', 'value': 'x'}),
        isA<TestOp>(),
      );
    });

    test('fromJson throws on unknown op', () {
      expect(
        () => PatchOp.fromJson({'op': 'invalid', 'path': '/a'}),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('Patch', () {
    test('serializes and deserializes correctly', () {
      const patch = Patch(
        key: '/test/scroll',
        ops: [
          AddOp(path: '/name', value: 'test'),
          ReplaceOp(path: '/count', value: 42),
        ],
        parent: 'abc123',
        hash: 'def456',
        timestamp: 1234567890,
        seq: 5,
      );

      final json = patch.toJson();
      final restored = Patch.fromJson(json);

      expect(restored.key, equals(patch.key));
      expect(restored.ops.length, equals(2));
      expect(restored.parent, equals(patch.parent));
      expect(restored.hash, equals(patch.hash));
      expect(restored.timestamp, equals(patch.timestamp));
      expect(restored.seq, equals(patch.seq));
    });

    test('copyWith creates modified copy', () {
      const original = Patch(
        key: '/test',
        ops: [],
        hash: 'abc',
        timestamp: 100,
        seq: 1,
      );

      final modified = original.copyWith(seq: 2, hash: 'def');

      expect(modified.seq, equals(2));
      expect(modified.hash, equals('def'));
      expect(modified.key, equals(original.key));
    });
  });

  group('createPatch', () {
    test('creates genesis patch when old is null', () {
      final scroll = Scroll.create('/test', {'value': 42});
      final patch = createPatch('/test', null, scroll);

      expect(patch.key, equals('/test'));
      expect(patch.parent, isNull);
      expect(patch.seq, equals(1));
      expect(patch.ops.length, equals(1));
      expect(patch.ops.first, isA<ReplaceOp>());
    });

    test('creates update patch with diff', () {
      final old = Scroll.create('/test', {'a': 1, 'b': 2});
      final current = Scroll.create('/test', {'a': 1, 'b': 3, 'c': 4});

      final patch = createPatch('/test', old, current);

      expect(patch.parent, equals(old.computeHash()));
      expect(patch.hash, equals(current.computeHash()));

      // Should have replace for b and add for c
      final ops = patch.ops;
      expect(ops.any((op) => op is ReplaceOp && (op).path == '/b'), isTrue);
      expect(ops.any((op) => op is AddOp && (op).path == '/c'), isTrue);
    });

    test('creates remove ops for deleted keys', () {
      final old = Scroll.create('/test', {'a': 1, 'b': 2});
      final current = Scroll.create('/test', {'a': 1});

      final patch = createPatch('/test', old, current);

      expect(patch.ops.any((op) => op is RemoveOp && (op).path == '/b'), isTrue);
    });
  });

  group('applyPatch', () {
    test('applies add operation', () {
      final scroll = Scroll.create('/test', {'existing': 1});
      const patch = Patch(
        key: '/test',
        ops: [AddOp(path: '/new', value: 42)],
        hash: 'abc',
        timestamp: 100,
        seq: 1,
      );

      final result = applyPatch(scroll, patch);

      expect(result.isOk, isTrue);
      final applied = result.value;
      expect(applied.data['new'], equals(42));
      expect(applied.data['existing'], equals(1));
    });

    test('applies remove operation', () {
      final scroll = Scroll.create('/test', {'a': 1, 'b': 2});
      const patch = Patch(
        key: '/test',
        ops: [RemoveOp(path: '/b')],
        hash: 'abc',
        timestamp: 100,
        seq: 1,
      );

      final result = applyPatch(scroll, patch);

      expect(result.isOk, isTrue);
      final applied = result.value;
      expect(applied.data.containsKey('b'), isFalse);
      expect(applied.data['a'], equals(1));
    });

    test('applies replace operation', () {
      final scroll = Scroll.create('/test', {'value': 'old'});
      const patch = Patch(
        key: '/test',
        ops: [ReplaceOp(path: '/value', value: 'new')],
        hash: 'abc',
        timestamp: 100,
        seq: 1,
      );

      final result = applyPatch(scroll, patch);

      expect(result.isOk, isTrue);
      final applied = result.value;
      expect(applied.data['value'], equals('new'));
    });

    test('test operation fails on mismatch', () {
      final scroll = Scroll.create('/test', {'value': 'actual'});
      const patch = Patch(
        key: '/test',
        ops: [TestOp(path: '/value', value: 'expected')],
        hash: 'abc',
        timestamp: 100,
        seq: 1,
      );

      final result = applyPatch(scroll, patch);

      expect(result.isErr, isTrue);
      expect(result.errorOrNull, isA<TestFailedError>());
    });

    test('test operation succeeds on match', () {
      final scroll = Scroll.create('/test', {'value': 'expected'});
      const patch = Patch(
        key: '/test',
        ops: [TestOp(path: '/value', value: 'expected')],
        hash: 'abc',
        timestamp: 100,
        seq: 1,
      );

      final result = applyPatch(scroll, patch);

      expect(result.isOk, isTrue);
    });

    test('applies nested path operations', () {
      final scroll = Scroll.create('/test', {
        'nested': {'a': 1, 'b': 2}
      });
      const patch = Patch(
        key: '/test',
        ops: [
          ReplaceOp(path: '/nested/a', value: 100),
          AddOp(path: '/nested/c', value: 3),
        ],
        hash: 'abc',
        timestamp: 100,
        seq: 1,
      );

      final result = applyPatch(scroll, patch);

      expect(result.isOk, isTrue);
      final applied = result.value;
      final nested = applied.data['nested'] as Map<String, dynamic>;
      expect(nested['a'], equals(100));
      expect(nested['b'], equals(2));
      expect(nested['c'], equals(3));
    });
  });

  group('verifyPatch', () {
    test('verifies genesis patch', () {
      final scroll = Scroll.create('/test', {'value': 1});
      final patch = Patch(
        key: '/test',
        ops: const [],
        parent: null,
        hash: scroll.computeHash(),
        timestamp: 100,
        seq: 1,
      );

      expect(verifyPatch(null, patch), isTrue);
    });

    test('verifies update patch with matching parent', () {
      final old = Scroll.create('/test', {'value': 1});
      final patch = Patch(
        key: '/test',
        ops: const [],
        parent: old.computeHash(),
        hash: 'new-hash',
        timestamp: 100,
        seq: 2,
      );

      expect(verifyPatch(old, patch), isTrue);
    });

    test('rejects patch with wrong parent', () {
      final old = Scroll.create('/test', {'value': 1});
      const patch = Patch(
        key: '/test',
        ops: [],
        parent: 'wrong-hash',
        hash: 'new-hash',
        timestamp: 100,
        seq: 2,
      );

      expect(verifyPatch(old, patch), isFalse);
    });
  });

  group('PatchError types', () {
    test('PathNotFoundError', () {
      const error = PathNotFoundError('/missing/path');
      expect(error.message, equals('/missing/path'));
      expect(error.toString(), contains('PathNotFoundError'));
    });

    test('TypeMismatchError', () {
      const error = TypeMismatchError('expected object');
      expect(error.message, equals('expected object'));
    });

    test('TestFailedError', () {
      const error = TestFailedError('value mismatch');
      expect(error.message, equals('value mismatch'));
    });

    test('InvalidPointerError', () {
      const error = InvalidPointerError('bad pointer');
      expect(error.message, equals('bad pointer'));
    });
  });
}
