# 9S Protocol - Dart Implementation

**Five Frozen Operations. Everything is a Scroll.**

9S is a universal data protocol inspired by Plan 9's "everything is a file" philosophy, SICP's data abstraction principles, and Kant's categorical imperative.

## Quick Start

```dart
import 'package:nine_s/nine_s.dart';

void main() {
  // Create namespace
  final ns = MemoryNamespace();

  // Write data
  final result = ns.write('/wallet/balance', {'confirmed': 100000});
  print('Hash: ${result.value.computeHash()}');

  // Read data
  final read = ns.read('/wallet/balance');
  print('Balance: ${read.value?.data}');

  // Watch for changes
  ns.watch('/wallet/**').value.listen((scroll) {
    print('Changed: ${scroll.key}');
  });

  // Compose with Kernel
  final kernel = Kernel()
    ..mount('/wallet', ns)
    ..mount('/vault', MemoryNamespace());

  kernel.write('/vault/notes/abc', {'title': 'Secret'});
}
```

## The Five Frozen Operations

| Operation | Purpose | Signature |
|-----------|---------|-----------|
| `read` | Get data | `NineResult<Scroll?>` |
| `write` | Put data | `NineResult<Scroll>` |
| `list` | Enumerate | `NineResult<List<String>>` |
| `watch` | Subscribe | `NineResult<Stream<Scroll>>` |
| `close` | Release | `NineResult<void>` |

These operations are **frozen forever**. Extensions come from new Namespace implementations, never new operations.

## Core Concepts

### Scroll
The universal data primitive. Every piece of data is a Scroll with:
- `key` - Path identifier (e.g., `/wallet/balance`)
- `data` - JSON-serializable payload
- `metadata` - Version, timestamp, subject, verb
- `type_` - Schema type (e.g., `wallet/balance@v1`)

### Namespace
Interface for any storage backend. Implementations:
- `MemoryNamespace` - RAM storage
- `FileNamespace` - File-backed persistence
- `Store` - Encrypted storage with history
- `NetworkNamespace` - Remote over TCP/WebSocket

### Kernel
Path-based router that mounts namespaces:
```dart
final kernel = Kernel()
  ..mount('/wallet', walletNamespace)
  ..mount('/vault', vaultNamespace);

kernel.read('/wallet/balance');  // Routes to walletNamespace
```

### Result Type
Explicit error handling without exceptions:
```dart
final result = ns.read('/path');
switch (result) {
  case Ok(:final value): print('Got: $value');
  case Err(:final error): print('Error: $error');
}
```

## Features

### Unified Result Type
```dart
typedef NineResult<T> = Result<T, NineError>;
typedef PatchResult<T> = Result<T, PatchError>;
typedef SealResult<T> = Result<T, SealError>;
```

### RFC 6902 JSON Patch
Git-like diff primitives for Scrolls:
```dart
final patch = createPatch('/doc', oldScroll, newScroll);
final result = applyPatch(scroll, patch);
```

### SealedScroll
Shareable encrypted Scrolls:
```dart
final sealed = sealScroll(scroll, password: 'secret');
final uri = sealed.value.toUri();  // bee://...
```

### Store with History
Encrypted storage with automatic pruning:
```dart
final store = await Store.open('/path/to/vault', key: encryptionKey, history: true);
store.write('/doc', data);
store.anchor('/doc', label: 'v1.0');
store.stateAt('/doc', 5);  // Time travel
```

### Async Primitives

**CSP (Isolates)**
```dart
final pool = await IsolatePool.create(workers: 4);
final result = await pool.compute(expensiveWork, data);
```

**Rx (Streams)**
```dart
stream
  .debounced(Duration(milliseconds: 300))
  .throttled(Duration(seconds: 1))
  .batched(Duration(seconds: 5))
  .distinctBy((a, b) => a.id == b.id)
  .listen(handler);
```

### Networking
```dart
// Server
final server = await listen('tcp://0.0.0.0:9090', namespace);

// Client
final remote = await dial('tcp://server:9090');
final scroll = await remote.read('/path');
```

## Architecture

```
nine_s/
├── lib/
│   ├── nine_s.dart              # Public API
│   └── src/
│       ├── scroll/              # Scroll + Metadata
│       ├── namespace/           # Namespace interface + errors
│       ├── kernel/              # Path router
│       ├── result/              # Result<T,E> type
│       ├── backends/            # Memory, File implementations
│       ├── store/               # Encrypted storage
│       ├── patch/               # RFC 6902 JSON Patch
│       ├── anchor/              # Checkpoint/restore
│       ├── sealed/              # Shareable encryption
│       ├── async/               # IsolatePool, Stream utils
│       ├── net/                 # Networking layer
│       │   ├── transport.dart   # Connection interface
│       │   ├── protocol.dart    # Codec + Framer
│       │   └── transports/      # TCP, Unix, WebSocket, Memory
│       ├── watch/               # Watcher abstraction
│       └── utils/               # Crypto, path utilities
└── test/                        # 139 tests
```

## Philosophy

> "Everything flows through Scrolls. No parallel type systems."

- **Plan 9**: Everything is a file → Everything is a Scroll
- **SICP**: Use ≠ Representation → Interface over implementation
- **Kant**: Categorical imperative → Code as if your pattern were universal law

## Testing

```bash
dart test           # Run all 139 tests
dart analyze        # Zero issues
```

## Documentation

- [WHITEPAPER.md](docs/WHITEPAPER.md) - Full protocol specification and philosophy
- [DIALECTICS.md](docs/DIALECTICS.md) - Design tensions and resolutions
- [PROTOCOL_SPEC.md](docs/PROTOCOL_SPEC.md) - Technical protocol specification

## License

MIT OR Apache-2.0
