# Open Agent ID — Protocol

The open protocol for verifiable, wallet-native AI Agent identities.

Every AI agent gets a unique, chain-anchored, cryptographically verifiable identity (DID) owned by the user's Ethereum wallet.

## DID Format (V2)

```
did:oaid:{chain}:{agent_address}
did:oaid:base:0x7f4e3d2c1b0a9f8e7d6c5b4a3f2e1d0c9b8a7f6e
```

- **Method:** `oaid` (fixed)
- **Chain:** lowercase chain identifier (`base`, `base-sepolia`)
- **Address:** CREATE2-derived agent wallet address, `0x` + 40 hex, all lowercase

See [spec/did-format.md](spec/did-format.md) for full specification.

## Repository Structure

```
protocol/
├── spec/                    # Protocol specifications
│   ├── did-format.md        # DID V2 syntax and validation
│   ├── signing.md           # Dual-domain signing (oaid-http/v1, oaid-msg/v1)
│   └── api.yaml             # OpenAPI 3.1 — Registry API V2
├── contracts/               # Solidity smart contracts (Base L2)
│   ├── src/
│   │   ├── AgentRegistry.sol       # On-chain registry (batch + relayer)
│   │   ├── AgentWalletFactory.sol  # CREATE2 wallet factory
│   │   ├── AgentWallet.sol         # Minimal agent wallet (BeaconProxy)
│   │   └── interfaces/
│   │       └── IAgentWalletFactory.sol
│   ├── test/                # Foundry tests (52 tests)
│   └── script/
│       └── Deploy.s.sol     # Full deployment script
├── test-vectors/            # Shared test vectors for all SDKs
│   └── vectors.json
└── docs/
    └── mainnet-deployment.md
```

## Smart Contracts (V2)

Three contracts on Base L2:

### AgentRegistry
- `register(pubKeyHash, owner, nonce)` — Register via relayer
- `registerBatch(pubKeyHashes[], owners[], nonces[])` — Batch register (30-50% gas savings)
- `revoke(agentAddr)` — Revoke (owner only)
- `rotateKey(agentAddr, newPubKeyHash)` — Rotate key (owner only)
- `getAgent(agentAddr)` / `isActive(agentAddr)` — Query

### AgentWalletFactory
- `computeAddress(owner, nonce)` — Deterministic CREATE2 address (instant DID)
- `deploy(owner, nonce)` — Lazy deploy wallet (permissionless)

### AgentWallet
- Minimal wallet behind `BeaconProxy` (upgradeable via beacon)
- Receives ETH/ERC-20/ERC-721/ERC-1155
- `execute()` / `executeBatch()` — Arbitrary calls (owner or signer)
- ERC-4337 integration deferred to future beacon upgrade

### Build & Test

```bash
cd contracts
forge install
forge build
forge test -vv   # 52 tests
```

### Deploy

```bash
cd contracts
DEPLOYER_PRIVATE_KEY=0x... RELAYER_ADDRESS=0x... \
  forge script script/Deploy.s.sol --rpc-url https://sepolia.base.org --broadcast
```

## Signing

Two domains with domain separation (prevents cross-domain replay):

- **HTTP API:** `oaid-http/v1\n{METHOD}\n{URL}\n{BODY_HASH}\n{TIMESTAMP}\n{NONCE}`
- **P2P Messages:** `oaid-msg/v1\n{TYPE}\n{ID}\n{FROM}\n{TO}\n{REF}\n{TS}\n{EXP}\n{HASH}`

See [spec/signing.md](spec/signing.md) for full specification.

## SDKs

| Language | Package | Version |
|----------|---------|---------|
| Python | `pip install open-agent-id` | 0.2.0 |
| JavaScript | `npm install @openagentid/sdk` | 0.2.0 |
| Rust | `cargo add open-agent-id` | 0.2.0 |

## License

Apache-2.0
