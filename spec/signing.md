# Open Agent ID — Signing Specification

Version: 0.2.0 (V2)

## Key Algorithm

- **Algorithm**: Ed25519
- **Key size**: 256-bit (32 bytes)
- **Signature size**: 64 bytes
- **Signature encoding**: Base64url, no padding

## Signing Domains

V2 uses domain-separated signing to prevent cross-context replay attacks.

| Domain | Prefix | Purpose |
|--------|--------|---------|
| HTTP | `oaid-http/v1` | Signing HTTP requests |
| Message | `oaid-msg/v1` | Signing agent-to-agent messages |

## HTTP Signing

### Canonical Payload Format

```
oaid-http/v1\n{METHOD}\n{CANONICAL_URL}\n{BODY_HASH}\n{TIMESTAMP}\n{NONCE}
```

| Field | Description |
|-------|-------------|
| Domain | `oaid-http/v1` (fixed) |
| `METHOD` | HTTP method, uppercase (`GET`, `POST`, etc.) |
| `CANONICAL_URL` | Canonical URL (see rules below) |
| `BODY_HASH` | SHA-256 hex digest of request body, lowercase, 64 chars |
| `TIMESTAMP` | Unix timestamp in seconds |
| `NONCE` | 16 bytes, hex-encoded (32 chars) |

### Canonical URL Rules

1. Format: `scheme + "://" + host + path + query`
2. Host MUST be lowercase
3. Query parameters MUST be sorted lexicographically by key
4. If there are no query parameters, omit the `?` entirely
5. Fragment (`#...`) MUST be stripped

### Example

```
oaid-http/v1\nPOST\nhttps://api.example.com/v1/tasks\n0dfd9a0e52fe94a5e6311a6ef4643304c65636ae7fc316a0334e91c9665370af\n1708123456\nb4f2c3d5e6a7f8091a2b3c4d5e6f7a8b
```

### HTTP Headers

Signed requests MUST include these headers:

```
X-Agent-DID: did:oaid:base:0x7f4e3d2c1b0a9f8e7d6c5b4a3f2e1d0c9b8a7f6e
X-Agent-Timestamp: 1708123456
X-Agent-Nonce: b4f2c3d5e6a7f8091a2b3c4d5e6f7a8b
X-Agent-Signature: <base64url_signature>
```

### HTTP Verification

1. Extract DID from `X-Agent-DID` header
2. Resolve public key (cache, registry, or on-chain)
3. Reconstruct canonical payload from request
4. Verify Ed25519 signature against public key
5. Check timestamp is within +-300 seconds (5 min) of current time
6. Check nonce has not been seen before (replay protection)

### Replay Protection

- Verifiers MUST reject requests outside the +-300s timestamp window
- Verifiers MUST maintain a nonce dedup cache with TTL >= 600s (window x 2)
- A request is rejected if the (DID, nonce) pair has been seen within the TTL

## Message Signing

### Canonical Payload Format

```
oaid-msg/v1\n{TYPE}\n{ID}\n{FROM}\n{SORTED_TO}\n{REF}\n{TIMESTAMP}\n{EXPIRES_AT}\n{BODY_HASH}
```

| Field | Description |
|-------|-------------|
| Domain | `oaid-msg/v1` (fixed) |
| `TYPE` | Message type (e.g., `chat`, `task`, `event`) |
| `ID` | UUID v7 of the message |
| `FROM` | Sender DID |
| `SORTED_TO` | Comma-separated recipient DIDs, sorted lexicographically |
| `REF` | Reference message ID (empty string if none) |
| `TIMESTAMP` | Unix timestamp in seconds |
| `EXPIRES_AT` | Expiry Unix timestamp in seconds |
| `BODY_HASH` | SHA-256 hex digest of message body, lowercase, 64 chars |

### Example

```
oaid-msg/v1\nchat\n0192d4e5-6f78-7a9b-bcde-f01234567890\ndid:oaid:base:0x7f4e3d2c1b0a9f8e7d6c5b4a3f2e1d0c9b8a7f6e\ndid:oaid:base:0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n\n1708123456\n1708127056\n20b2dda940d741d9780897200aaef2ef356ab32b38c7de0d94306fb5a66b4a8e
```

### Message Replay Protection

- Messages use UUID v7 as a unique identifier (no separate nonce needed)
- Verifiers MUST maintain an ID dedup cache with TTL >= 600s
- A message is rejected if the same ID has been seen within the TTL

## Canonical JSON

When computing `BODY_HASH` over JSON payloads, the canonical form is:

1. Keys sorted lexicographically (recursive)
2. No whitespace (no spaces, no newlines)
3. UTF-8 encoded
4. Numbers use shortest representation (`1` not `1.0`, `1.5` not `1.50`)

## Body Hash

- `BODY_HASH` = lowercase hex SHA-256 (always 64 characters)
- Empty body: `BODY_HASH` = `SHA256("")` = `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`

## Key Encoding

- **Public key**: Base64url, no padding (43 characters for 32 bytes)
- **Private key**: Base64url, no padding (86 characters for 64 bytes, includes public key suffix)
- **Multibase** (for DID Document): `z` prefix + Base58btc encoded
