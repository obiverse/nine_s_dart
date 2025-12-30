/// 9S Protocol - Five Frozen Operations
///
/// "Everything flows through Scrolls. No parallel type systems."
///
/// ## The Five Operations
///
/// | Operation | Purpose | Returns |
/// |-----------|---------|---------|
/// | `read(path)` | Get data | `Scroll?` |
/// | `write(path, data)` | Put data | `Scroll` |
/// | `list(prefix)` | Enumerate | `List<String>` |
/// | `watch(pattern)` | Subscribe | `Stream<Scroll>` |
/// | `close()` | Release | `void` |
///
/// ## Quick Start
///
/// ```dart
/// import 'package:nine_s/nine_s.dart';
///
/// void main() {
///   // Create an in-memory namespace
///   final ns = MemoryNamespace();
///
///   // Write a scroll
///   final result = ns.write('/wallet/balance', {'confirmed': 100000});
///   final scroll = result.value;
///   print('Version: ${scroll.metadata.version}');
///
///   // Read it back
///   final read = ns.read('/wallet/balance');
///   print('Balance: ${read.value?.data}');
///
///   // Watch for changes
///   ns.watch('/wallet/**').value.listen((scroll) {
///     print('Changed: ${scroll.key}');
///   });
///
///   // Compose namespaces with Kernel
///   final kernel = Kernel()
///     ..mount('/wallet', ns)
///     ..mount('/vault', MemoryNamespace());
///
///   // Now /wallet/balance routes to ns, /vault/* routes elsewhere
///   kernel.write('/vault/notes/abc', {'title': 'Secret'});
/// }
/// ```
///
/// ## Philosophy
///
/// 9S is inspired by:
/// - **Plan 9** - "Everything is a file"
/// - **SICP** - "Data abstraction: Use ≠ Representation"
/// - **Kant** - "Code as if your pattern were universal law"
///
/// Extensions come from new Namespace implementations, never new operations.
/// The five operations are frozen forever.
library nine_s;

// Core
export 'src/scroll.dart';
export 'src/metadata.dart';
export 'src/namespace.dart';
export 'src/kernel.dart';

// Utils
export 'src/utils.dart';

// Advanced Features
export 'src/patch.dart';
export 'src/anchor.dart';
export 'src/sealed.dart';

// Store - Universal Storage Abstraction
// Store.memory() for RAM, Store.open() for file-backed
// Encrypted by default when key provided (backward compatible)
export 'src/store/store.dart' show Store;

// Backends
export 'src/backends/memory.dart';
export 'src/backends/file.dart';
