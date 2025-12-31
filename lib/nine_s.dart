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

// Core - The Five Frozen Operations
export 'src/scroll/scroll.dart';
export 'src/scroll/metadata.dart';
export 'src/namespace/namespace.dart';
export 'src/kernel/kernel.dart';

// Utils
export 'src/utils/utils.dart';

// Async - CSP (Isolates) + Rx (Streams) Primitives
export 'src/async/isolate_pool.dart';
export 'src/async/stream_utils.dart';

// Advanced Features
export 'src/patch/patch.dart';
export 'src/anchor/anchor.dart';
export 'src/sealed/sealed.dart';

// Store - Universal Storage Abstraction
// Store.memory() for RAM, Store.open() for file-backed
// Encrypted by default when key provided (backward compatible)
export 'src/store/store.dart' show Store;

// Backends - Namespace Implementations
export 'src/backends/memory.dart';
export 'src/backends/file.dart';

// Networking - dial/listen for Remote Namespaces
// Call initNetworking() once on startup to register transports
export 'src/net/net.dart';
