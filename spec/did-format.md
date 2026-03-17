# Open Agent ID — DID Format Specification

Version: 0.2.0 (V2)

## DID Syntax

```
did:oaid:{chain}:{agent_address}
```

### Components

| Component | Format | Example |
|-----------|--------|---------|
| Method | `oaid` (fixed) | `oaid` |
| Chain | Lowercase chain identifier | `base`, `base-sepolia` |
| Agent Address | `0x` + 40 lowercase hex chars | `0x7f4e3d2c1b0a9f8e7d6c5b4a3f2e1d0c9b8a7f6e` |

### Chain Identifiers

| Chain | Identifier |
|-------|------------|
| Base (mainnet) | `base` |
| Base Sepolia (testnet) | `base-sepolia` |

Chain identifiers are lowercase, using hyphens to separate words.

### Address Format

- Prefixed with `0x`
- 40 hexadecimal characters (20 bytes)
- All lowercase (no EIP-55 mixed-case checksum)

### Examples

```
did:oaid:base:0x7f4e3d2c1b0a9f8e7d6c5b4a3f2e1d0c9b8a7f6e
did:oaid:base:0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
did:oaid:base-sepolia:0x1234567890abcdef1234567890abcdef12345678
```

### Validation Rules

1. Method MUST be `oaid`
2. Chain MUST be a lowercase alphanumeric string with optional hyphens, 1-20 characters `[a-z0-9-]`
3. Agent address MUST be `0x` followed by exactly 40 lowercase hex characters `[0-9a-f]`
4. Total DID length MUST NOT exceed 80 characters

### Platform as Metadata

In V1, `platform` was part of the DID (`did:agent:{platform}:{id}`). In V2, the agent's wallet address is the identity. Platform is optional metadata stored off-chain (e.g., in the registry) and is NOT part of the DID string.

### DID Document

A minimal DID Document for an Open Agent ID:

```json
{
  "@context": "https://www.w3.org/ns/did/v1",
  "id": "did:oaid:base:0x7f4e3d2c1b0a9f8e7d6c5b4a3f2e1d0c9b8a7f6e",
  "verificationMethod": [{
    "id": "did:oaid:base:0x7f4e3d2c1b0a9f8e7d6c5b4a3f2e1d0c9b8a7f6e#key-1",
    "type": "Ed25519VerificationKey2020",
    "controller": "did:oaid:base:0x7f4e3d2c1b0a9f8e7d6c5b4a3f2e1d0c9b8a7f6e",
    "publicKeyMultibase": "z6Mkf5rGMoatrSj1f4CyvuHBeXJELe9RPdzo2PKGNCKVtZxP"
  }],
  "authentication": [
    "did:oaid:base:0x7f4e3d2c1b0a9f8e7d6c5b4a3f2e1d0c9b8a7f6e#key-1"
  ]
}
```

## On-Chain Representation

On-chain, the agent address is the primary key. No hashing is needed — the address itself is used directly for lookups and ownership verification.

```
agentAddress = 0x7f4e3d2c1b0a9f8e7d6c5b4a3f2e1d0c9b8a7f6e  // 20 bytes
```
