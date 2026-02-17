# Open Agent ID — DID Format Specification

Version: 0.1.0

## DID Syntax

```
did:agent:{platform}:{unique_id}
```

### Components

| Component | Format | Example |
|-----------|--------|---------|
| Method | `agent` (fixed) | `agent` |
| Platform | 3-20 lowercase alphanumeric | `tokli` |
| Unique ID | `agt_` + 10 base62 chars | `agt_a1B2c3D4e5` |

### Base62 Character Set

```
0-9 A-Z a-z
```

10 base62 characters = 62^10 ≈ 8.4 × 10^17 possible IDs.

### Examples

```
did:agent:tokli:agt_a1B2c3D4e5
did:agent:openai:agt_X9yZ8wV7u6
did:agent:langchain:agt_Q3rS4tU5v6
```

### Validation Rules

1. Method MUST be `agent`
2. Platform MUST be 3-20 characters, lowercase `[a-z0-9]`
3. Unique ID MUST start with `agt_` followed by exactly 10 base62 characters `[0-9A-Za-z]`
4. Total DID length MUST NOT exceed 60 characters

### DID Document

A minimal DID Document for an Open Agent ID:

```json
{
  "@context": "https://www.w3.org/ns/did/v1",
  "id": "did:agent:tokli:agt_a1B2c3D4e5",
  "verificationMethod": [{
    "id": "did:agent:tokli:agt_a1B2c3D4e5#key-1",
    "type": "Ed25519VerificationKey2020",
    "controller": "did:agent:tokli:agt_a1B2c3D4e5",
    "publicKeyMultibase": "z6Mkf5rGMoatrSj1f4CyvuHBeXJELe9RPdzo2PKGNCKVtZxP"
  }],
  "authentication": [
    "did:agent:tokli:agt_a1B2c3D4e5#key-1"
  ]
}
```

## On-Chain Representation

On-chain, only hashes are stored to minimize gas costs:

```
didHash    = keccak256(did_string)        // 32 bytes
pubKeyHash = keccak256(public_key_bytes)  // 32 bytes
```
