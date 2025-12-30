/// 9S Protocol Example - A Tour of Dart Idioms
///
/// This example demonstrates:
/// 1. The 9S protocol (5 frozen operations)
/// 2. Idiomatic Dart patterns
/// 3. Dart's strengths as a language
///
/// Run with: `dart run example/nine_s_example.dart`
library;

import 'dart:async';

import 'package:nine_s/nine_s.dart';

// ============================================================================
// DART LESSON 1: Top-level functions and the main entry point
// ============================================================================

/// Dart programs start at `main()`. It can be sync or async.
/// Top-level functions are first-class citizens - no class wrapper needed.
Future<void> main() async {
  print('═══════════════════════════════════════════════════════════════');
  print('           9S Protocol - A Tour of Dart Idioms');
  print('═══════════════════════════════════════════════════════════════\n');

  await demonstrateScrolls();
  await demonstrateNamespaces();
  await demonstrateKernel();
  await demonstrateWatching();
  await demonstrateResultPattern();

  print('\n═══════════════════════════════════════════════════════════════');
  print('                   Five operations. Frozen.');
  print('═══════════════════════════════════════════════════════════════');
}

// ============================================================================
// DART LESSON 2: Named parameters and const constructors
// ============================================================================

Future<void> demonstrateScrolls() async {
  print('┌─────────────────────────────────────────────────────────────┐');
  print('│ SCROLLS - Universal Data Envelopes                         │');
  print('└─────────────────────────────────────────────────────────────┘\n');

  // DART IDIOM: Named parameters make construction self-documenting
  // Compare: Scroll('/path', {'a': 1}, 'type', metadata)  ← positional (unclear)
  //          Scroll(key: '/path', data: {...})            ← named (clear!)
  const scroll = Scroll(
    key: '/wallet/balance',
    data: {'confirmed': 100000, 'pending': 5000},
    type_: 'wallet/balance@v1',
  );

  print('  Created scroll: ${scroll.key}');
  print('  Type: ${scroll.type_}');
  print('  Data: ${scroll.data}\n');

  // DART IDIOM: Cascade operator (..) for fluent builders
  // Each `..` returns the original object, enabling chaining
  final richScroll = Scroll.create('/vault/notes/abc123', {'title': 'Secret'})
    ..withType('vault/note@v1');

  // Since Scroll is immutable, we use method chaining that returns new instances
  final annotatedScroll = richScroll
      .withSubject('user:local')
      .withVerb(Verbs.creates)
      .withKingdom(Kingdoms.content)
      .withExtension('pinned', true);

  print('  Rich scroll with metadata:');
  print('    Subject: ${annotatedScroll.metadata.subject}');
  print('    Verb: ${annotatedScroll.metadata.verb}');
  print('    Kingdom: ${annotatedScroll.metadata.kingdom}');
  print('    Pinned: ${annotatedScroll.getExtBool('pinned')}\n');
}

// ============================================================================
// DART LESSON 3: Null safety and the Result pattern
// ============================================================================

Future<void> demonstrateNamespaces() async {
  print('┌─────────────────────────────────────────────────────────────┐');
  print('│ NAMESPACES - The Five Frozen Operations                    │');
  print('└─────────────────────────────────────────────────────────────┘\n');

  final ns = MemoryNamespace();

  // OPERATION 1: write(path, data) → Scroll
  print('  1. WRITE');
  final writeResult = ns.write('/wallet/balance', {'confirmed': 100000});
  print('     Result: ${writeResult.isOk ? "✓" : "✗"}');
  print('     Version: ${writeResult.value.metadata.version}');
  print('     Hash: ${writeResult.value.metadata.hash?.substring(0, 16)}...\n');

  // OPERATION 2: read(path) → Scroll?
  print('  2. READ');
  final readResult = ns.read('/wallet/balance');

  // DART IDIOM: Null-aware operators
  // ?. (null-safe access), ?? (null coalescing), ?[] (null-safe indexing)
  final confirmed = readResult.value?.data['confirmed'] ?? 0;
  print('     Confirmed balance: $confirmed sats\n');

  // OPERATION 3: list(prefix) → List<String>
  print('  3. LIST');
  ns.write('/wallet/tx/abc', {'amount': 50000});
  ns.write('/wallet/tx/def', {'amount': 25000});
  final listResult = ns.list('/wallet');
  print('     Paths under /wallet:');
  for (final path in listResult.value) {
    print('       - $path');
  }
  print('');

  // OPERATION 4: watch - demonstrated separately

  // OPERATION 5: close() → void
  print('  5. CLOSE');
  ns.close();
  final afterClose = ns.read('/wallet/balance');
  print('     After close: ${afterClose.isErr ? "Correctly rejected" : "Unexpected"}\n');
}

// ============================================================================
// DART LESSON 4: Records and pattern matching (Dart 3.0+)
// ============================================================================

Future<void> demonstrateKernel() async {
  print('┌─────────────────────────────────────────────────────────────┐');
  print('│ KERNEL - Namespace Composition                             │');
  print('└─────────────────────────────────────────────────────────────┘\n');

  // DART IDIOM: Cascade operator for configuration
  final kernel = Kernel()
    ..mount('/wallet', MemoryNamespace())
    ..mount('/vault', MemoryNamespace())
    ..mount('/ln', MemoryNamespace());

  print('  Mounted: /wallet, /vault, /ln\n');

  // Write to different namespaces through the kernel
  kernel.write('/wallet/balance', {'confirmed': 100000});
  kernel.write('/vault/notes/secret', {'title': 'My Secret'});
  kernel.write('/ln/balance', {'msats': 50000000});

  // DART IDIOM: Pattern matching with switch expressions
  // Dart 3.0 introduced powerful pattern matching
  final paths = ['/wallet/balance', '/vault/notes/secret', '/ln/balance'];

  print('  Reading through kernel:');
  for (final path in paths) {
    final result = kernel.read(path);

    // Switch expression (not statement!) returns a value
    final status = switch (result) {
      Ok(value: final scroll?) => '✓ ${scroll.data}',
      Ok(value: null) => '○ not found',
      Err(:final error) => '✗ $error',
    };
    print('    $path → $status');
  }

  kernel.close();
  print('');
}

// ============================================================================
// DART LESSON 5: Streams and async/await
// ============================================================================

Future<void> demonstrateWatching() async {
  print('┌─────────────────────────────────────────────────────────────┐');
  print('│ WATCHING - Reactive Streams                                │');
  print('└─────────────────────────────────────────────────────────────┘\n');

  final ns = MemoryNamespace();

  // OPERATION 4: watch(pattern) → Stream<Scroll>
  print('  4. WATCH\n');

  // DART IDIOM: Streams are lazy - nothing happens until you listen
  final watchResult = ns.watch('/wallet/**');
  final stream = watchResult.value;

  // Collect events
  final events = <Scroll>[];
  final subscription = stream.listen(events.add);

  // Writes trigger watch events
  print('  Writing /wallet/balance...');
  ns.write('/wallet/balance', {'confirmed': 100000});

  print('  Writing /wallet/tx/abc...');
  ns.write('/wallet/tx/abc', {'amount': 50000});

  print('  Writing /other/path... (should not trigger)');
  ns.write('/other/path', {'ignored': true});

  // DART IDIOM: Microtask scheduling
  // Stream events are delivered in microtasks, so we need to wait
  await Future<void>.delayed(const Duration(milliseconds: 10));

  print('\n  Received ${events.length} events:');
  for (final scroll in events) {
    print('    - ${scroll.key}: ${scroll.data}');
  }

  await subscription.cancel();
  ns.close();
  print('');
}

// ============================================================================
// DART LESSON 6: Sealed classes and exhaustive matching
// ============================================================================

Future<void> demonstrateResultPattern() async {
  print('┌─────────────────────────────────────────────────────────────┐');
  print('│ RESULT PATTERN - Error Handling Without Exceptions         │');
  print('└─────────────────────────────────────────────────────────────┘\n');

  final ns = MemoryNamespace();

  // DART IDIOM: sealed classes enable exhaustive pattern matching
  // The compiler knows all subtypes, so it warns if you miss a case

  void handleResult(Result<Scroll?> result) {
    // Exhaustive switch - compiler ensures all cases are handled
    switch (result) {
      case Ok(:final value):
        if (value != null) {
          print('    ✓ Found: ${value.key}');
        } else {
          print('    ○ Not found (but operation succeeded)');
        }
      case Err(error: ClosedError()):
        print('    ✗ Namespace is closed');
      case Err(error: InvalidPathError(:final message)):
        print('    ✗ Invalid path: $message');
      case Err(:final error):
        print('    ✗ Other error: $error');
    }
  }

  // Test various cases
  print('  Reading existing path:');
  ns.write('/test', {'value': 42});
  handleResult(ns.read('/test'));

  print('  Reading non-existent path:');
  handleResult(ns.read('/missing'));

  print('  Reading invalid path:');
  handleResult(ns.read('no-leading-slash'));

  print('  Reading after close:');
  ns.close();
  handleResult(ns.read('/test'));

  print('');
}
