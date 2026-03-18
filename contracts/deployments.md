# Contract Deployments

## V2 (Current)

**Network:** Base Sepolia | **Chain ID:** 84532 | **Deployed:** 2026-03-18

| Contract | Address | Tx Hash |
|----------|---------|---------|
| AgentWallet (impl) | `0xaef7a487f4f44e59efa029b34477ab31838e36c9` | `0xd8c21f40e528e5edb0f41d40b3f2034eb8f5aa1df03439e7103427e116a1d7d5` |
| UpgradeableBeacon | `0xf9c17be190b12e9e1adc8ad41c3b17332d89a7f5` | `0x09f181a6b0bce53249989be175557d51ae481cebd0a71be6679b0c59b3c17a41` |
| AgentWalletFactory | `0xdb8cc3da316e390a889e91327c5d6acf35542001` | `0x26f01a94e9bcbbfade79527029ee8f69dd6e00620382401e554a406c48065f1c` |
| AgentRegistry | `0xe63f1adbc4c2eaa088c5e78d2a0cf51272ef9688` | `0x2ede29b729ee978b8baff2c09fcc7cdc6a2f59aa5be0d1833ca4dd08de2ba815` |

**Config:**
- `WALLET_BYTECODE_HASH`: `0x95e3574b9d6b6868dfb3cb3e07fd8dd4f992f0e35795f6a2eb725bba75834dce`
- Relayer/Admin: `0x8f48fc00f061f13b95bd803dd862b8676f7219cc`

## TrustPayment (USDC Fees)

**Network:** Base Sepolia | **Deployed:** 2026-03-18

| Contract | Address | Tx Hash |
|----------|---------|---------|
| TrustPayment | `0xb68008668baa229f7790a1eb84c8b6592f19fb9a` | `0x79fbb0e9860e8e9a257da9c20c12321735e3e63821658232cb5ea5b93a147517` |

**Config:**
- USDC: `0x036CbD53842c5426634e7929541eC2318f3dCF7e` (Circle test USDC on Base Sepolia)
- Admin: `0x8f48fc00f061f13b95bd803dd862b8676f7219cc`
- Verification fee: 10 USDC ($10)
- Report fee: 1 USDC ($1)

## V1 (Deprecated)

| Network | Chain ID | Address | Tx Hash |
|---------|----------|---------|---------|
| Base Sepolia | 84532 | `0x5d9F4e3fb75cE6221665e8f5099192BDA42ebd01` | `0xdd41fc946b2ee52ed469249741e97df763b076b8f3188905f5fe9ce313ff0417` |
