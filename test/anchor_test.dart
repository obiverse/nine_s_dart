// Anchor Tests - Immutable Checkpoints for Scrolls

import 'package:test/test.dart';
import 'package:nine_s/nine_s.dart';

void main() {
  group('Anchor', () {
    test('creates with required fields', () {
      const anchor = Anchor(
        id: 'test-id',
        scroll: Scroll(key: '/test', data: {'value': 42}),
        hash: 'abc123',
        timestamp: 1234567890,
      );

      expect(anchor.id, equals('test-id'));
      expect(anchor.hash, equals('abc123'));
      expect(anchor.timestamp, equals(1234567890));
      expect(anchor.label, isNull);
      expect(anchor.description, isNull);
    });

    test('creates with optional fields', () {
      const anchor = Anchor(
        id: 'test-id',
        scroll: Scroll(key: '/test', data: {}),
        hash: 'abc123',
        timestamp: 1234567890,
        label: 'v1.0',
        description: 'First release',
      );

      expect(anchor.label, equals('v1.0'));
      expect(anchor.description, equals('First release'));
    });

    test('toJson and fromJson roundtrip', () {
      final scroll = Scroll.create('/test/path', {'data': 'value'});
      final anchor = Anchor(
        id: 'anchor-123',
        scroll: scroll,
        hash: scroll.computeHash(),
        timestamp: 1234567890,
        label: 'checkpoint-1',
        description: 'Test checkpoint',
      );

      final json = anchor.toJson();
      final restored = Anchor.fromJson(json);

      expect(restored.id, equals(anchor.id));
      expect(restored.hash, equals(anchor.hash));
      expect(restored.timestamp, equals(anchor.timestamp));
      expect(restored.label, equals(anchor.label));
      expect(restored.description, equals(anchor.description));
      expect(restored.scroll.key, equals(anchor.scroll.key));
    });

    test('copyWith modifies only specified fields', () {
      const original = Anchor(
        id: 'test-id',
        scroll: Scroll(key: '/test', data: {}),
        hash: 'abc123',
        timestamp: 1234567890,
        label: 'original',
      );

      final modified = original.copyWith(
        label: 'modified',
        description: 'Added description',
      );

      // Modified fields
      expect(modified.label, equals('modified'));
      expect(modified.description, equals('Added description'));

      // Unchanged fields
      expect(modified.id, equals(original.id));
      expect(modified.hash, equals(original.hash));
      expect(modified.timestamp, equals(original.timestamp));
    });

    test('equality based on id, hash, and timestamp', () {
      const a1 = Anchor(
        id: 'same-id',
        scroll: Scroll(key: '/test', data: {}),
        hash: 'same-hash',
        timestamp: 100,
      );

      const a2 = Anchor(
        id: 'same-id',
        scroll: Scroll(key: '/different', data: {'x': 1}),
        hash: 'same-hash',
        timestamp: 100,
        label: 'different label',
      );

      expect(a1, equals(a2));
      expect(a1.hashCode, equals(a2.hashCode));
    });

    test('inequality with different id', () {
      const a1 = Anchor(
        id: 'id-1',
        scroll: Scroll(key: '/test', data: {}),
        hash: 'same-hash',
        timestamp: 100,
      );

      const a2 = Anchor(
        id: 'id-2',
        scroll: Scroll(key: '/test', data: {}),
        hash: 'same-hash',
        timestamp: 100,
      );

      expect(a1, isNot(equals(a2)));
    });

    test('toString contains useful info', () {
      const anchor = Anchor(
        id: 'test-anchor',
        scroll: Scroll(key: '/test', data: {}),
        hash: 'abcdef1234567890',
        timestamp: 100,
        label: 'v1.0',
      );

      final str = anchor.toString();
      expect(str, contains('test-anchor'));
      expect(str, contains('v1.0'));
      expect(str, contains('abcdef12')); // Hash prefix
    });
  });

  group('createAnchor', () {
    test('generates unique id', () {
      final scroll = Scroll.create('/test', {'value': 1});

      final a1 = createAnchor(scroll);
      final a2 = createAnchor(scroll);

      // Same scroll, but different anchor IDs (different timestamps/suffixes)
      expect(a1.id, isNot(equals(a2.id)));
    });

    test('computes correct hash', () {
      final scroll = Scroll.create('/test', {'value': 42});
      final anchor = createAnchor(scroll);

      expect(anchor.hash, equals(scroll.computeHash()));
    });

    test('includes label when provided', () {
      final scroll = Scroll.create('/test', {});
      final anchor = createAnchor(scroll, label: 'release-1.0');

      expect(anchor.label, equals('release-1.0'));
    });

    test('sets timestamp to current time', () {
      final before = DateTime.now().millisecondsSinceEpoch;
      final scroll = Scroll.create('/test', {});
      final anchor = createAnchor(scroll);
      final after = DateTime.now().millisecondsSinceEpoch;

      expect(anchor.timestamp, greaterThanOrEqualTo(before));
      expect(anchor.timestamp, lessThanOrEqualTo(after));
    });

    test('id format includes hash prefix and timestamp', () {
      final scroll = Scroll.create('/test', {'data': 'value'});
      final anchor = createAnchor(scroll);

      // ID format: {hash_prefix}-{timestamp}-{random_suffix}
      final parts = anchor.id.split('-');
      expect(parts.length, greaterThanOrEqualTo(3));

      // First part is hash prefix (8 chars)
      expect(parts[0].length, equals(8));
      expect(parts[0], equals(scroll.computeHash().substring(0, 8)));
    });
  });

  group('createAnchorWithDescription', () {
    test('includes description', () {
      final scroll = Scroll.create('/test', {});
      final anchor = createAnchorWithDescription(
        scroll,
        label: 'v1.0',
        description: 'Major release with new features',
      );

      expect(anchor.label, equals('v1.0'));
      expect(anchor.description, equals('Major release with new features'));
    });
  });

  group('verifyAnchor', () {
    test('returns true for valid anchor', () {
      final scroll = Scroll.create('/test', {'value': 42});
      final anchor = createAnchor(scroll);

      expect(verifyAnchor(anchor), isTrue);
    });

    test('returns false for tampered scroll', () {
      final scroll = Scroll.create('/test', {'value': 42});
      final anchor = createAnchor(scroll);

      // Create anchor with modified scroll but original hash
      final tamperedAnchor = Anchor(
        id: anchor.id,
        scroll: Scroll.create('/test', {'value': 999}), // Different data
        hash: anchor.hash, // Original hash
        timestamp: anchor.timestamp,
      );

      expect(verifyAnchor(tamperedAnchor), isFalse);
    });
  });

  group('equivalent', () {
    test('returns true for same content hash', () {
      final scroll = Scroll.create('/test', {'value': 42});

      final a1 = createAnchor(scroll, label: 'first');
      final a2 = createAnchor(scroll, label: 'second');

      // Different IDs and labels, but same content
      expect(a1.id, isNot(equals(a2.id)));
      expect(equivalent(a1, a2), isTrue);
    });

    test('returns false for different content', () {
      final s1 = Scroll.create('/test', {'value': 1});
      final s2 = Scroll.create('/test', {'value': 2});

      final a1 = createAnchor(s1);
      final a2 = createAnchor(s2);

      expect(equivalent(a1, a2), isFalse);
    });
  });

  group('extractScroll', () {
    test('returns the scroll from anchor', () {
      final scroll = Scroll.create('/test', {'key': 'value'});
      final anchor = createAnchor(scroll);

      final extracted = extractScroll(anchor);

      expect(extracted.key, equals(scroll.key));
      expect(extracted.data, equals(scroll.data));
    });
  });
}
