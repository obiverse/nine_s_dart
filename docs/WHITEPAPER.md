# 9S: The Nine Scrolls Protocol

**A Universal Interface for Sovereign Data**

*"Everything flows through Scrolls. No parallel type systems."*

---

## Abstract

9S (Nine Scrolls) is a minimal protocol for data sovereignty. It defines exactly five frozen operations—read, write, list, watch, close—through which all data flows. Like Plan 9's "everything is a file," 9S asserts "everything is a Scroll." Unlike filesystems that store bytes, Scrolls carry meaning: typed data wrapped in semantic metadata.

This paper presents 9S not as software but as a pattern of thought—a way of seeing data that enables composition without coordination, sovereignty without isolation, and simplicity without sacrifice.

---

## 1. The Problem of Data

Modern software drowns in abstractions. Every domain invents its types, every service its schemas, every layer its transformations. Data flows through ORMs, serializers, validators, adapters—each adding complexity, each potential point of failure.

The deeper problem is philosophical: we've confused **use** with **representation**. SICP teaches us that data abstraction separates what we do with data from how it's stored. Yet our systems couple them tightly. Change a database schema and watch the ripples propagate through layers of code.

9S proposes a return to first principles: a single universal envelope for all data, manipulated through five unchanging operations.

---

## 2. The Scroll

A Scroll is a universal data envelope:

```
Scroll {
    key: String        // Path in namespace (e.g., "/wallet/balance")
    type: String?      // Semantic type hint (e.g., "wallet/balance@v1")
    data: Map          // The actual payload
    metadata: Metadata // When, who, what, how
}
```

### 2.1 The Key is the Address

Every Scroll lives at a path. Paths are hierarchical, like filesystems:

```
/wallet/balance
/wallet/transactions/tx_001
/vault/notes/meeting-2024
/identity/keys/signing
```

The path is not arbitrary—it's the Scroll's identity. Two Scrolls at the same path in the same namespace are the same Scroll at different times.

### 2.2 The Type is Optional Meaning

The `type` field carries semantic intent without enforcing schema:

```
type: "wallet/transaction@v1"
type: "vault/note@v1"
type: "identity/keypair@v1"
```

Types are hints, not constraints. A namespace may ignore them. A viewer may interpret them. The data stands alone.

### 2.3 The Data is Just Data

The payload is a map—JSON-like, recursively nested, arbitrarily structured. No schema enforcement at the protocol level. Schema is policy; 9S is mechanism.

### 2.4 The Metadata is Memory

Metadata records provenance:

**Temporal** (when):
- `createdAt`: Birth moment
- `updatedAt`: Last change
- `syncedAt`: Last synchronization
- `expiresAt`: Death moment (optional)

**Lifecycle** (what state):
- `version`: Monotonic counter
- `hash`: Content fingerprint
- `deleted`: Soft-delete flag

**Linguistic** (who did what):
- `subject`: Actor (e.g., "user:alice")
- `verb`: Action (e.g., "signs", "creates", "approves")
- `object`: Target (e.g., "transaction:tx_001")
- `tense`: Time relation (past/present/future)

**Taxonomic** (classification):
- `kingdom`: Broadest category (e.g., "finance")
- `phylum`: Sub-category (e.g., "bitcoin")
- `class_`: Specific type (e.g., "lightning")

This three-level semantic hierarchy—temporal, linguistic, taxonomic—enables rich queries without complex schemas.

---

## 3. The Five Operations

*"Five operations. Frozen. Never a sixth."*

### 3.1 read(path) → Scroll?

Ask: "What exists at this path?"

Returns the Scroll if present, null if absent. Not-found is not an error—it's a valid answer to a valid question.

```
read("/wallet/balance")
→ Scroll { data: { confirmed: 100000, pending: 5000 } }

read("/nonexistent")
→ null
```

### 3.2 write(path, data) → Scroll

Assert: "This data exists at this path."

Creates or updates. Returns the Scroll with computed metadata (version incremented, hash computed, timestamps set).

```
write("/wallet/balance", { confirmed: 105000 })
→ Scroll { version: 2, hash: "abc...", updatedAt: 1234567890 }
```

Write is declarative, not imperative. You don't "update field X"—you declare the new state. The namespace handles the transition.

### 3.3 list(prefix) → [String]

Query: "What paths exist under this prefix?"

Returns paths, not Scrolls. Enumeration without data transfer.

```
list("/wallet")
→ ["/wallet/balance", "/wallet/transactions/tx_001", "/wallet/transactions/tx_002"]
```

### 3.4 watch(pattern) → Stream<Scroll>

Subscribe: "Notify me when matching paths change."

Returns a stream that emits Scrolls as they change. Patterns support wildcards:
- `*` matches one segment: `/wallet/*` matches `/wallet/balance` but not `/wallet/tx/001`
- `**` matches any suffix: `/wallet/**` matches everything under `/wallet/`

```
watch("/wallet/**").listen((scroll) {
    print("Changed: ${scroll.key}");
});
```

Watch is the reactive primitive. It transforms storage into a live system.

### 3.5 close() → void

Release: "I'm done with this namespace."

Cancels all watches, releases resources. Idempotent—safe to call multiple times. Subsequent operations fail gracefully.

---

## 4. The Namespace

A Namespace is anything that implements the five operations. The abstraction is deliberately minimal:

```
interface Namespace {
    read(path) → Result<Scroll?>
    write(path, data) → Result<Scroll>
    list(prefix) → Result<[String]>
    watch(pattern) → Result<Stream<Scroll>>
    close() → Result<void>
}
```

### 4.1 Implementations as Extensions

The power of 9S emerges from Namespace implementations:

**MemoryNamespace**: RAM storage. Fast, ephemeral. Perfect for caches and transient state.

**FileNamespace**: Filesystem persistence. Scrolls become JSON files. Survives process restart.

**Store**: Encrypted storage. AES-256-GCM at rest, HKDF key derivation. Sovereignty through cryptography.

**Kernel**: Composition via mount table. Routes paths to namespaces by longest-prefix match.

Each implementation adds capability without adding operations. This is the key insight: **extensions come from new implementations, never from new operations**.

### 4.2 The Kernel: Composition Without Coordination

The Kernel is a mount table that routes operations by path:

```
kernel.mount("/wallet", walletNamespace)
kernel.mount("/vault", vaultNamespace)
kernel.mount("/identity", identityNamespace)

// Now operations route automatically:
kernel.read("/wallet/balance")  // → walletNamespace
kernel.read("/vault/secrets")   // → vaultNamespace
```

This is Plan 9's per-process namespace, realized for data. Each application sees a unified tree, but different branches connect to different backends.

**Longest-prefix routing** handles nesting:
```
mount("/", defaultNamespace)
mount("/wallet", walletNamespace)
mount("/wallet/cold", coldStorageNamespace)

read("/wallet/cold/keys")  // → coldStorageNamespace
read("/wallet/hot/keys")   // → walletNamespace
read("/other/data")        // → defaultNamespace
```

**Segment-boundary security** prevents leaks:
```
mount("/foo", fooNamespace)

read("/foo/bar")     // → fooNamespace (correct)
read("/foobar/baz")  // → NOT fooNamespace (different path)
```

---

## 5. Advanced Patterns

### 5.1 Patch: Git for Scrolls

Scrolls change over time. Patches capture these changes as RFC 6902 JSON Patch operations:

```
Patch {
    key: "/wallet/balance"
    ops: [
        { op: "replace", path: "/confirmed", value: 105000 }
    ]
    parent: "abc123..."  // Hash of previous state
    hash: "def456..."    // Hash of new state
    seq: 2               // Monotonic sequence number
}
```

Patches form a hash chain. Each patch references its parent's hash. Tampering is detectable. History is reconstructible.

### 5.2 Anchor: Immutable Checkpoints

An Anchor freezes a Scroll at a moment in time:

```
Anchor {
    id: "abc123-1234567890-f7e2"
    scroll: Scroll { ... }     // The frozen state
    hash: "..."                // Content fingerprint
    timestamp: 1234567890
    label: "before-migration"  // Human-readable tag
}
```

Anchors enable:
- **Rollback**: Restore to any anchored state
- **Audit**: Prove what existed when
- **Branching**: Fork from a known point

### 5.3 SealedScroll: Shareable Secrets

A SealedScroll is an encrypted, shareable envelope:

```
SealedScroll {
    version: 1
    ciphertext: "..."      // Encrypted scroll
    nonce: "..."           // Cryptographic nonce
    salt: "..."            // For password-derived keys
    hasPassword: true      // Requires password to unseal
    sealedAt: 1234567890
    scrollType: "vault/note@v1"  // Preserved for UI hints
}
```

SealedScrolls serialize to URIs for sharing:
```
beescroll://v1/eyJjaXBoZXJ0ZXh0Ijoi...
```

Anyone with the URI (and password, if set) can unseal the Scroll. The content travels through untrusted channels safely.

---

## 6. Design Principles

### 6.1 Synchronous by Default

The Namespace interface is synchronous. This is deliberate:

1. **Local storage is fast**: Memory, filesystem, encrypted store—all complete in microseconds
2. **Simpler mental model**: No async/await pollution for hot paths
3. **Easier composition**: Kernel routing doesn't require promise chaining

For network backends, create an `AsyncNamespace` interface and use caching adapters:

```
class CachedRemoteNamespace implements Namespace {
    final AsyncNamespace remote;
    final MemoryNamespace cache;

    read(path) {
        // Sync read from cache
        // Async refresh in background
    }
}
```

### 6.2 Result Types Over Exceptions

Every operation returns `Result<T>`—either `Ok(value)` or `Err(error)`:

```
switch (namespace.read("/path")) {
    case Ok(:final value): print(value);
    case Err(:final error): print(error);
}
```

Errors are data, not control flow. This makes error handling explicit and composable.

### 6.3 Soft Delete Over Hard Delete

There is no `delete` operation. This is intentional.

To remove a Scroll, write with `metadata.deleted: true`:

```
scroll.markDeleted()  // Sets metadata.deleted = true
namespace.writeScroll(scroll)
```

Benefits:
- **Audit trail**: Deletions are visible in history
- **Recovery**: Undelete by clearing the flag
- **Sync-friendly**: Tombstones propagate; missing data doesn't

Hard delete, if needed, is a namespace-specific convenience method—not a protocol operation.

### 6.4 GC-Friendly Resource Management

Watch streams should clean up automatically when forgotten. Use weak references:

```
class Watcher {
    final StreamController<Scroll> controller;
    final WeakReference<Stream<Scroll>> streamRef;

    bool get isDead =>
        controller.isClosed ||
        streamRef.target == null;  // GC'd
}
```

When user code drops all references to a watch stream, the garbage collector reclaims it. The namespace detects this on next notification and cleans up. No explicit cancel required—"release when forgotten" semantics.

---

## 7. Security Model

### 7.1 Path Validation

All paths are validated before processing:

- Must start with `/`
- No `.` or `..` segments (path traversal blocked)
- Character whitelist: alphanumeric, underscore, hyphen, dot
- Glob wildcards (`*`) only in watch patterns

### 7.2 Segment Boundary Matching

Path matching respects segment boundaries:

```
isPathUnderPrefix("/wallet/user", "/wallet")      // true
isPathUnderPrefix("/wallet/user_archive", "/wallet/user")  // false!
```

This prevents `/wallet/user` from accidentally matching `/wallet/user_archive`.

### 7.3 Encryption at Rest

The Store namespace encrypts all data:

- **Algorithm**: AES-256-GCM
- **Key derivation**: HKDF with app-specific context
- **Per-app isolation**: Same master key yields different encryption keys per app

```
Store.openForApp(path, masterKey, "wallet")  // Wallet-specific key
Store.openForApp(path, masterKey, "vault")   // Different key
```

### 7.4 Shareable Encryption

SealedScrolls use:
- **Random key**: Generated per seal (no password)
- **Password-derived key**: PBKDF2 with random salt (with password)
- **Algorithm**: AES-256-GCM
- **Nonce**: Random, never reused

---

## 8. Philosophical Foundations

### 8.1 Plan 9: Everything is a File

Plan 9 unified Unix's scattered namespaces into a single tree. 9S extends this: everything is a Scroll—not just files, but typed data with semantic metadata.

### 8.2 SICP: Use ≠ Representation

Data abstraction separates interface from implementation. The five operations are the interface. Namespaces are implementations. You can swap memory for disk for network without changing code that uses the namespace.

### 8.3 Kant: Universal Law

The categorical imperative: "Act only according to that maxim whereby you can at the same time will that it should become a universal law."

In code: write patterns that work if everyone follows them. The five operations are such a pattern—minimal, complete, composable. If every system used them, interoperability would be free.

### 8.4 Tao: The Way that Can Be Named

The Tao Te Ching opens: "The way that can be named is not the eternal way."

9S names five operations, then falls silent. The protocol doesn't prescribe what data means, how to validate it, when to sync it. These are policies for implementations to decide. The protocol provides mechanism.

### 8.5 Dialectics: Thesis → Antithesis → Synthesis

Every design tension resolves through synthesis:

| Thesis | Antithesis | Synthesis |
|--------|------------|-----------|
| Type safety | Schema freedom | Optional type hints |
| Strong consistency | Availability | Result types, explicit errors |
| Eager cleanup | Lazy cleanup | GC-aware weak references |
| Delete operation | No delete | Soft delete via metadata |
| Sync API | Async API | Sync default, async adapters |

---

## 9. Running 9S in Your Mind

To internalize 9S, visualize:

**The Tree**: A unified namespace tree where every path leads to a Scroll or nothing. The tree is infinite in potential, finite in actuality.

**The Flow**: Data flows through five gates—read, write, list, watch, close. No other gates exist. No other gates are needed.

**The Envelope**: Every piece of data wrapped in a Scroll, carrying its identity (key), intent (type), content (data), and history (metadata).

**The Mount**: Different namespaces handling different subtrees. The Kernel routing by prefix. Local and remote, memory and disk, encrypted and plain—all unified under one interface.

**The Stream**: Watchers as living queries, receiving Scrolls as they change. The system breathing, reactive, alive.

---

## 10. Conclusion

9S is not about the code. It's about the pattern.

Five operations. One envelope. Infinite composition.

The protocol is frozen—not because change is impossible, but because change is unnecessary. The five operations are complete. They form a basis, in the mathematical sense: any data operation can be expressed as a combination of read, write, list, watch, and close.

Extensions come from new namespace implementations:
- Want encryption? Implement a namespace.
- Want networking? Implement a namespace.
- Want caching? Implement a namespace.
- Want routing? Implement a namespace (the Kernel).

The protocol remains unchanged. The interface remains stable. The implementations evolve.

This is sovereignty through simplicity. Your data, your namespaces, your composition. No central authority. No breaking changes. No complexity tax.

Five operations. Frozen. Forever.

---

## Appendix A: Quick Reference

### Operations

| Operation | Signature | Returns |
|-----------|-----------|---------|
| read | `read(path)` | `Scroll?` |
| write | `write(path, data)` | `Scroll` |
| list | `list(prefix)` | `[String]` |
| watch | `watch(pattern)` | `Stream<Scroll>` |
| close | `close()` | `void` |

### Scroll Structure

```
Scroll {
    key: String
    type: String?
    data: Map<String, dynamic>
    metadata: Metadata
}
```

### Metadata Fields

| Category | Fields |
|----------|--------|
| Temporal | createdAt, updatedAt, syncedAt, expiresAt |
| Lifecycle | version, hash, deleted |
| Linguistic | subject, verb, object, tense |
| Taxonomic | kingdom, phylum, class_ |

### Path Patterns

| Pattern | Matches |
|---------|---------|
| `/foo` | Exactly `/foo` |
| `/foo/*` | `/foo/bar` but not `/foo/bar/baz` |
| `/foo/**` | `/foo/bar`, `/foo/bar/baz`, etc. |

---

## Appendix B: Implementations

| Name | Storage | Persistence | Encryption |
|------|---------|-------------|------------|
| MemoryNamespace | RAM | No | No |
| FileNamespace | Filesystem | Yes | No |
| Store | Filesystem | Yes | Yes (AES-256-GCM) |
| Kernel | Composition | Depends on mounted namespaces | Depends |

---

*9S: Nine Scrolls. Five Operations. Infinite Possibility.*
