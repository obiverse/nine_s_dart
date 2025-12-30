# 9S Protocol Specification v1.0

**Formal Specification for Implementers**

---

## 0. Frozen Protocol Declaration

```
┌─────────────────────────────────────────────────────────────────────┐
│                                                                     │
│   THIS PROTOCOL IS FROZEN                                           │
│                                                                     │
│   The five operations are immutable:                                │
│                                                                     │
│       read    write    list    watch    close                       │
│                                                                     │
│   No sixth operation will be added.                                 │
│   No operation will be removed.                                     │
│   No operation signature will change.                               │
│                                                                     │
│   Extensions come from new Namespace implementations,               │
│   never from protocol modifications.                                │
│                                                                     │
│   This specification may receive clarifications but                 │
│   not behavioral changes. Version 1.0 is final.                     │
│                                                                     │
│   Frozen: 2024-12-30                                                │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 1. Overview

This document specifies the 9S (Nine Scrolls) protocol in precise, implementable terms. It is intended for developers creating 9S-compliant namespaces in any language.

### 1.1 Conformance Levels

- **MUST**: Absolute requirement for conformance
- **SHOULD**: Recommended but not required
- **MAY**: Optional behavior

### 1.2 Notation

```
Type         ::= description
Operation    ::= signature → return_type
```

---

## 2. Core Types

### 2.1 Path

```
Path ::= "/" Segment*
Segment ::= ValidChar+
ValidChar ::= [a-zA-Z0-9_.-]
```

**Requirements:**
- MUST start with `/`
- MUST NOT contain `.` or `..` as complete segments
- MUST NOT contain characters outside ValidChar (except `*` in patterns)
- MAY be `/` (root path)

**Examples:**
```
Valid:   /wallet/balance, /vault/notes/2024-01-15, /a
Invalid: wallet/balance, /../secret, /foo bar, /foo//bar
```

### 2.2 Pattern

```
Pattern ::= Path | Path "/*" | Path "/**"
```

**Matching Rules:**
- Exact: `/foo` matches only `/foo`
- Single wildcard: `/foo/*` matches `/foo/bar` but not `/foo/bar/baz`
- Recursive wildcard: `/foo/**` matches `/foo/bar`, `/foo/bar/baz`, etc.

### 2.3 Scroll

```
Scroll {
    key: Path           // REQUIRED
    type: String?       // OPTIONAL, format: "domain/name@version"
    data: Object        // REQUIRED, JSON-compatible map
    metadata: Metadata  // REQUIRED
}
```

**Invariants:**
- `key` MUST be a valid Path
- `data` MUST be a JSON-serializable object (map/dictionary)
- `metadata.version` MUST be ≥ 1 for persisted Scrolls

### 2.4 Metadata

```
Metadata {
    // Temporal (Unix milliseconds, nullable)
    createdAt: Int?
    updatedAt: Int?
    syncedAt: Int?
    expiresAt: Int?

    // Lifecycle
    version: Int        // REQUIRED, ≥ 0
    hash: String?       // SHA-256 hex, computed by namespace
    deleted: Boolean    // Default: false

    // Linguistic (nullable)
    subject: String?    // Actor identifier
    verb: String?       // Action performed
    object: String?     // Target of action
    tense: Tense?       // past | present | future

    // Taxonomic (nullable)
    kingdom: String?    // Broadest category
    phylum: String?     // Sub-category
    class_: String?     // Specific type
}
```

### 2.5 Result

```
Result<T> = Ok(T) | Err(Error)

Error = NotFoundError(message)
      | InvalidPathError(message)
      | InvalidDataError(message)
      | PermissionError(message)
      | ClosedError
      | TimeoutError
      | ConnectionError(message)
      | UnavailableError(message)
      | InternalError(message)
```

---

## 3. Namespace Interface

### 3.1 read

```
read(path: Path) → Result<Scroll?>
```

**Behavior:**
- MUST return `Ok(Scroll)` if a Scroll exists at path
- MUST return `Ok(null)` if no Scroll exists at path
- MUST return `Err(InvalidPathError)` if path is invalid
- MUST return `Err(ClosedError)` if namespace is closed
- MAY return other errors for implementation-specific failures

**Postconditions:**
- Returned Scroll's `key` MUST equal the requested `path`

### 3.2 write

```
write(path: Path, data: Object) → Result<Scroll>
```

**Behavior:**
- MUST create a new Scroll if none exists at path
- MUST update the existing Scroll if one exists at path
- MUST increment `metadata.version` (previous + 1, or 1 if new)
- MUST set `metadata.updatedAt` to current time
- MUST set `metadata.createdAt` to current time if new
- MUST preserve `metadata.createdAt` if updating
- SHOULD compute and set `metadata.hash`
- MUST notify all matching watchers after successful write
- MUST return `Err(InvalidPathError)` if path is invalid
- MUST return `Err(ClosedError)` if namespace is closed

**Postconditions:**
- Returned Scroll's `key` MUST equal the requested `path`
- Returned Scroll's `data` MUST equal the provided `data`
- Returned Scroll's `metadata.version` MUST be > previous version (or 1 if new)

### 3.3 writeScroll

```
writeScroll(scroll: Scroll) → Result<Scroll>
```

**Behavior:**
- Same as `write`, but preserves `scroll.type`
- MUST use `scroll.key` as the path
- MUST use `scroll.data` as the data
- MUST preserve `scroll.type` in the returned Scroll
- MAY use `scroll.metadata` fields as hints (but namespace computes authoritative values)

### 3.4 list

```
list(prefix: Path) → Result<[Path]>
```

**Behavior:**
- MUST return all paths that are "under" the prefix
- MUST use segment-boundary matching (see section 4.1)
- MUST return empty list if no paths match (not an error)
- MUST return `Err(InvalidPathError)` if prefix is invalid
- MUST return `Err(ClosedError)` if namespace is closed

**Examples:**
```
Given paths: [/a, /a/b, /a/b/c, /ab]

list("/")   → [/a, /a/b, /a/b/c, /ab]
list("/a")  → [/a, /a/b, /a/b/c]
list("/ab") → [/ab]
list("/x")  → []
```

### 3.5 watch

```
watch(pattern: Pattern) → Result<Stream<Scroll>>
```

**Behavior:**
- MUST return a stream that emits Scrolls when matching paths change
- MUST match using pattern rules (section 2.2)
- MUST emit the Scroll after successful write operations
- SHOULD support multiple concurrent watchers
- MAY limit the number of concurrent watchers
- MUST return `Err(InvalidPathError)` if pattern is invalid
- MUST return `Err(ClosedError)` if namespace is closed
- MUST close all streams when namespace is closed

**Stream Semantics:**
- Stream SHOULD be lazy (no resources until listened)
- Stream MAY be single-subscription or broadcast
- Implementation SHOULD support GC-friendly cleanup (section 5.3)

### 3.6 close

```
close() → Result<void>
```

**Behavior:**
- MUST close all active watch streams
- MUST release all resources
- MUST cause subsequent operations to return `Err(ClosedError)`
- MUST be idempotent (safe to call multiple times)
- SHOULD return `Ok(void)` even on repeated calls

---

## 4. Path Semantics

### 4.1 Segment Boundary Matching

When checking if `path` is under `prefix`:

```
isUnderPrefix(path, prefix):
    if prefix == "/":
        return path.startsWith("/")
    if path == prefix:
        return true
    if path.startsWith(prefix):
        return path[prefix.length] == "/"
    return false
```

**Critical**: `/wallet/user` MUST NOT match `/wallet/user_archive`

### 4.2 Path Normalization

Mount paths SHOULD be normalized:
- Ensure leading `/`
- Remove trailing `/` (except for root)

```
normalize("/foo/")  → "/foo"
normalize("foo")    → "/foo"
normalize("/")      → "/"
```

---

## 5. Implementation Requirements

### 5.1 Hash Computation

Hash SHOULD be computed as:

```
computeHash(scroll):
    canonical = {
        "key": scroll.key,
        "type": scroll.type,
        "data": scroll.data
    }
    json = canonicalJsonEncode(canonical)
    return sha256Hex(json)
```

**Canonical JSON:**
- Keys sorted alphabetically
- No whitespace
- Null values omitted

### 5.2 Version Semantics

- Version MUST be a non-negative integer
- Version MUST increment by 1 on each write
- Version 0 MAY indicate "unsaved" or "in-memory only"
- Version 1 is the first persisted version

### 5.3 Watcher Cleanup

Implementations SHOULD support GC-friendly cleanup:

```
Watcher {
    controller: StreamController
    streamRef: WeakReference<Stream>

    isDead():
        return controller.isClosed || streamRef.target == null
}
```

On each notify:
1. Check each watcher's `isDead()`
2. Remove dead watchers
3. Close orphaned controllers
4. Notify remaining watchers

### 5.4 Thread Safety

- Implementations SHOULD be thread-safe for concurrent reads
- Implementations MAY require external synchronization for writes
- Watch notifications MAY occur on any thread/isolate

---

## 6. Kernel Specification

The Kernel is a namespace that routes operations to mounted namespaces.

### 6.1 Mount Table

```
Kernel {
    mounts: SortedMap<Path, Namespace>  // Sorted by path length (descending)
}
```

### 6.2 Resolution

```
resolve(path):
    for (mountPath, namespace) in mounts:  // Longest first
        if isUnderMount(path, mountPath):
            strippedPath = stripPrefix(path, mountPath)
            return (namespace, strippedPath)
    return Error("no namespace mounted")

isUnderMount(path, mountPath):
    if mountPath == "/":
        return path.startsWith("/")
    if path == mountPath:
        return true
    if path.startsWith(mountPath):
        return path[mountPath.length] == "/"
    return false
```

### 6.3 Path Translation

On read/write/list:
1. Resolve (namespace, strippedPath)
2. Call namespace.operation(strippedPath)
3. Translate returned paths back to original mount point

```
translateBack(scrollKey, mountPath):
    if mountPath == "/":
        return scrollKey
    if scrollKey == "/":
        return mountPath
    return mountPath + scrollKey
```

---

## 7. Patch Specification

### 7.1 Patch Structure

```
Patch {
    key: Path           // The scroll being patched
    ops: [PatchOp]      // RFC 6902 operations
    parent: String?     // Hash of previous state (null for genesis)
    hash: String        // Hash of new state
    timestamp: Int      // Unix milliseconds
    seq: Int            // Monotonic sequence number
}
```

### 7.2 PatchOp (RFC 6902)

```
PatchOp = AddOp | RemoveOp | ReplaceOp | MoveOp | CopyOp | TestOp

AddOp     { op: "add",     path: JsonPointer, value: Any }
RemoveOp  { op: "remove",  path: JsonPointer }
ReplaceOp { op: "replace", path: JsonPointer, value: Any }
MoveOp    { op: "move",    from: JsonPointer, path: JsonPointer }
CopyOp    { op: "copy",    from: JsonPointer, path: JsonPointer }
TestOp    { op: "test",    path: JsonPointer, value: Any }
```

### 7.3 JSON Pointer (RFC 6901)

```
JsonPointer ::= "/" Segment*
Segment ::= (UnescapedChar | "~0" | "~1")*

Escape: "~" → "~0", "/" → "~1"
Unescape: "~1" → "/", "~0" → "~"
```

### 7.4 Patch Verification

```
verifyPatch(oldScroll, patch):
    if oldScroll == null:
        return patch.parent == null  // Genesis
    else:
        return patch.parent == oldScroll.hash
```

---

## 8. Anchor Specification

### 8.1 Anchor Structure

```
Anchor {
    id: String          // Unique identifier
    scroll: Scroll      // Frozen state
    hash: String        // Content hash at anchor time
    timestamp: Int      // Unix milliseconds
    label: String?      // Human-readable tag
    description: String?// Extended description
}
```

### 8.2 ID Generation

```
generateAnchorId(scroll):
    hash = computeHash(scroll)
    timestamp = now()
    suffix = secureRandom(0, 0xFFFF).toHex(4)
    return "${hash[0:8]}-${timestamp}-${suffix}"
```

MUST use cryptographically secure random for suffix.

### 8.3 Anchor Verification

```
verifyAnchor(anchor):
    return computeHash(anchor.scroll) == anchor.hash
```

---

## 9. SealedScroll Specification

### 9.1 SealedScroll Structure

```
SealedScroll {
    version: Int        // Protocol version (1)
    ciphertext: String  // Base64-encoded encrypted data
    nonce: String       // Base64-encoded nonce
    salt: String?       // Base64-encoded salt (if password-protected)
    hasPassword: Boolean
    sealedAt: Int       // Unix seconds
    scrollType: String? // Preserved from original scroll
}
```

### 9.2 Sealing Algorithm

```
seal(scroll, password?):
    plaintext = jsonEncode(scroll.toJson())
    nonce = secureRandom(12)  // 96 bits for GCM

    if password:
        salt = secureRandom(16)
        key = pbkdf2(password, salt, iterations=100000, keyLength=32)
    else:
        key = secureRandom(32)
        salt = null

    ciphertext = aes256Gcm.encrypt(plaintext, key, nonce)

    return SealedScroll {
        version: 1,
        ciphertext: base64(ciphertext),
        nonce: base64(nonce),
        salt: salt ? base64(salt) : null,
        hasPassword: password != null,
        sealedAt: now() / 1000,
        scrollType: scroll.type
    }
```

### 9.3 Unsealing Algorithm

```
unseal(sealed, password?):
    if sealed.hasPassword && !password:
        return Error("password required")

    if sealed.hasPassword:
        salt = base64Decode(sealed.salt)
        key = pbkdf2(password, salt, iterations=100000, keyLength=32)
    else:
        // Key must be provided out-of-band for passwordless seals
        return Error("no password seal not implemented")

    nonce = base64Decode(sealed.nonce)
    ciphertext = base64Decode(sealed.ciphertext)

    plaintext = aes256Gcm.decrypt(ciphertext, key, nonce)
    if plaintext == null:
        return Error("decryption failed")

    return Scroll.fromJson(jsonDecode(plaintext))
```

### 9.4 URI Encoding

```
toUri(sealed):
    json = jsonEncode(sealed.toJson())
    encoded = base64UrlEncode(json)
    return "beescroll://v1/${encoded}"

fromUri(uri):
    if !uri.startsWith("beescroll://v1/") && !uri.startsWith("beenote://v1/"):
        return Error("invalid URI scheme")
    encoded = uri.split("/")[2]
    json = base64UrlDecode(encoded)
    return SealedScroll.fromJson(jsonDecode(json))
```

---

## 10. Error Handling

### 10.1 Error Hierarchy

```
NineError (abstract)
├── NotFoundError      // Resource not found (use sparingly - prefer null)
├── InvalidPathError   // Path syntax violation
├── InvalidDataError   // Data validation failure
├── PermissionError    // Access denied
├── ClosedError        // Namespace is closed
├── TimeoutError       // Operation timed out
├── ConnectionError    // Network/connection failure
├── UnavailableError   // Service temporarily unavailable
└── InternalError      // Implementation bug or unexpected state
```

### 10.2 Error Guidelines

- `read` returning `null` is NOT an error—it's a valid answer
- `list` returning `[]` is NOT an error—it's a valid answer
- Path validation errors SHOULD be `InvalidPathError`
- Closed namespace errors MUST be `ClosedError`
- Implementation-specific errors SHOULD use `InternalError`

---

## 11. Conformance Testing

A conformant implementation MUST pass these tests:

### 11.1 Basic Operations

```
test("write creates scroll"):
    result = ns.write("/test", {"value": 1})
    assert result.isOk
    assert result.value.key == "/test"
    assert result.value.data == {"value": 1}
    assert result.value.metadata.version == 1

test("read returns written scroll"):
    ns.write("/test", {"value": 1})
    result = ns.read("/test")
    assert result.isOk
    assert result.value.data == {"value": 1}

test("read returns null for missing"):
    result = ns.read("/nonexistent")
    assert result.isOk
    assert result.value == null

test("version increments"):
    ns.write("/test", {"v": 1})
    ns.write("/test", {"v": 2})
    result = ns.read("/test")
    assert result.value.metadata.version == 2
```

### 11.2 Path Validation

```
test("rejects invalid paths"):
    assert ns.read("no-slash").isErr
    assert ns.read("/../etc/passwd").isErr
    assert ns.write("/test/../secret", {}).isErr
```

### 11.3 List Semantics

```
test("list segment boundary"):
    ns.write("/foo", {})
    ns.write("/foobar", {})
    result = ns.list("/foo")
    assert "/foo" in result.value
    assert "/foobar" not in result.value
```

### 11.4 Watch Semantics

```
test("watch receives updates"):
    events = []
    ns.watch("/**").value.listen(events.add)
    ns.write("/test", {"v": 1})
    await delay(50)
    assert events.length == 1
    assert events[0].key == "/test"
```

### 11.5 Close Semantics

```
test("close prevents operations"):
    ns.close()
    assert ns.read("/test").isErr
    assert ns.read("/test").error is ClosedError
```

---

## 12. Version History

| Version | Date | Status | Changes |
|---------|------|--------|---------|
| 1.0 | 2024-12-30 | **FROZEN** | Initial and final specification |

---

## 13. Cryptographic Commitment

The SHA-256 hash of this specification (excluding this section) serves as a cryptographic commitment to its frozen state.

Future documents may reference this hash to verify they are implementing the authentic, unmodified 9S protocol.

---

```
"Five operations. Frozen. Forever."

    read    write    list    watch    close

This specification is sealed. The protocol is complete.
Extensions come from implementations, never from modifications.
```
