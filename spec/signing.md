# Open Agent ID — Signing Specification

Version: 0.1.0

## Key Algorithm

- **Algorithm**: Ed25519
- **Key size**: 256-bit (32 bytes)
- **Signature size**: 64 bytes
- **Encoding**: Base64 URL-safe, no padding

## Request Signing

### Canonical Payload Format

To sign a request, construct a canonical string:

```
{method}\n{url}\n{body_hash}\n{timestamp}\n{nonce}
```

| Field | Description |
|-------|-------------|
| `method` | HTTP method, uppercase (GET, POST, etc.) |
| `url` | Full request URL including query params |
| `body_hash` | SHA-256 hex digest of request body (empty string → hash of empty string) |
| `timestamp` | Unix timestamp in seconds |
| `nonce` | Random 16-byte hex string |

### Example

```
POST\nhttps://api.example.com/v1/tasks\n9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08\n1708123456\na3f1b2c4d5e6f7089012
```

### Signature

```
signature = Ed25519.sign(canonical_payload, private_key)
```

Encoded as Base64 URL-safe, no padding.

## HTTP Headers

Signed requests MUST include these headers:

```
X-Agent-DID: did:agent:tokli:agt_a1B2c3D4e5
X-Agent-Timestamp: 1708123456
X-Agent-Nonce: a3f1b2c4d5e6f7089012
X-Agent-Signature: <base64url_signature>
```

## Verification

1. Extract DID from `X-Agent-DID` header
2. Resolve public key (cache → API → on-chain)
3. Reconstruct canonical payload from request
4. Verify Ed25519 signature against public key
5. Check timestamp is within ±300 seconds (5 min) of current time
6. Check nonce has not been seen before (optional, for replay protection)

## Key Encoding

- **Public key**: Base64 URL-safe, no padding (44 characters)
- **Private key**: Base64 URL-safe, no padding (88 characters, includes public key)
- **Multibase** (for DID Document): `z` prefix + Base58btc encoded
