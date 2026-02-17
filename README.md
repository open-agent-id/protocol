# Open Agent ID — Protocol

The open protocol for verifiable AI Agent identities.

Every AI agent gets a unique, chain-anchored, cryptographically verifiable identity (DID) that works across platforms.

## Repository Structure

```
protocol/
├── spec/                    # Protocol specifications
│   ├── did-format.md        # DID syntax and validation rules
│   ├── signing.md           # Request signing specification
│   └── api.yaml             # OpenAPI 3.1 — Registry API
├── contracts/               # Solidity smart contracts (Base L2)
│   ├── src/
│   │   └── AgentRegistry.sol
│   ├── test/
│   │   └── AgentRegistry.t.sol
│   └── script/
│       └── Deploy.s.sol
└── test-vectors/            # Shared test vectors for all SDKs
    └── vectors.json
```

## DID Format

```
did:agent:{platform}:{unique_id}
did:agent:tokli:agt_a1B2c3D4e5
```

See [spec/did-format.md](spec/did-format.md) for full specification.

## Smart Contract

A single `AgentRegistry` contract on Base L2 stores identity proofs:

- `register(didHash, pubKeyHash, platform)` — Register an agent
- `revoke(didHash)` — Revoke an agent
- `rotateKey(didHash, newPubKeyHash)` — Rotate public key
- `getAgent(didHash)` — Query agent record
- `isActive(didHash)` — Check if agent is active

Only hashes are stored on-chain (~181 bytes per agent). Full data lives off-chain.

### Build & Test

```bash
cd contracts
forge install
forge build
forge test
```

### Deploy to Base L2

```bash
DEPLOYER_PRIVATE_KEY=0x... forge script script/Deploy.s.sol --rpc-url https://mainnet.base.org --broadcast
```

## SDKs

| Language | Package | Repository |
|----------|---------|------------|
| Python | `pip install agent-id` | [agent-id-python](https://github.com/openagentid/agent-id-python) |
| JavaScript | `npm install @openagentid/sdk` | [agent-id-js](https://github.com/openagentid/agent-id-js) |
| Rust | `cargo add agent-id` | [agent-id-rust](https://github.com/openagentid/agent-id-rust) |

## License

Apache-2.0
