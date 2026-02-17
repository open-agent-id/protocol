# AgentRegistry -- Base Mainnet Deployment Guide

This guide covers deploying the `AgentRegistry` contract to Base mainnet (chain ID 8453) and configuring the registry server to use it.

**Reference:** The testnet deployment is at `0x5d9F4e3fb75cE6221665e8f5099192BDA42ebd01` on Base Sepolia (chain ID 84532).

---

## 1. Prerequisites

### 1.1 Foundry toolchain

Foundry must be installed. The deploy script uses `forge script`. Verify installation:

```bash
~/.foundry/bin/forge --version
```

### 1.2 Dedicated deployer wallet

Create a **new** Ethereum wallet specifically for the mainnet deployment. Do NOT reuse the testnet deployer wallet or any personal wallet.

```bash
# Generate a new wallet (save the private key securely)
~/.foundry/bin/cast wallet new
```

Record the address and private key. The private key will be used as `DEPLOYER_PRIVATE_KEY` during deployment and later as `CHAIN_PRIVATE_KEY` in the registry server config (since the registry server sends `register()` and `rotateKey()` transactions from this wallet).

### 1.3 ETH on Base mainnet

Fund the deployer wallet with ETH on Base mainnet. You need ETH for:

- Contract deployment: ~500K gas
- Ongoing `register()` calls: ~100K gas each
- Ongoing `rotateKey()` calls: ~80K gas each

See Section 5 for detailed cost estimates. As a starting point, **0.005 ETH** (~$15 USD at current prices) is more than sufficient for deployment plus hundreds of registrations at Base L2 gas prices.

You can bridge ETH from Ethereum mainnet to Base using the [Base Bridge](https://bridge.base.org).

### 1.4 BaseScan API key

Required for contract verification. Get one at [https://basescan.org/myapikey](https://basescan.org/myapikey). You will need a free BaseScan account.

### 1.5 Base mainnet RPC

The public RPC endpoint is:

```
https://mainnet.base.org
```

For production use with higher rate limits, consider a dedicated RPC provider (Alchemy, Infura, QuickNode).

---

## 2. Contract Deployment

All commands assume you are in the `protocol/contracts/` directory:

```bash
cd protocol/contracts/
```

### 2.1 Set environment variables

```bash
export DEPLOYER_PRIVATE_KEY="0x<your-mainnet-deployer-private-key>"
export BASESCAN_API_KEY="<your-basescan-api-key>"
```

### 2.2 Build the contract

```bash
~/.foundry/bin/forge build
```

### 2.3 Deploy (dry run first)

Run a simulation to verify everything works before spending gas:

```bash
~/.foundry/bin/forge script script/Deploy.s.sol:DeployScript \
  --rpc-url https://mainnet.base.org \
  --chain-id 8453 \
  --broadcast \
  --dry-run
```

Review the output. The script will log: `AgentRegistry deployed at: <address>`.

### 2.4 Deploy (live)

```bash
~/.foundry/bin/forge script script/Deploy.s.sol:DeployScript \
  --rpc-url https://mainnet.base.org \
  --chain-id 8453 \
  --broadcast \
  --verify \
  --etherscan-api-key $BASESCAN_API_KEY \
  -vvvv
```

The `-vvvv` flag provides verbose output so you can see the transaction hash and deployed address. The `--verify` flag will automatically verify the contract on BaseScan after deployment.

Record the deployed contract address from the console output.

### 2.5 Verify contract (if automatic verification failed)

If the `--verify` flag did not succeed during deployment, verify manually:

```bash
~/.foundry/bin/forge verify-contract \
  --chain-id 8453 \
  --etherscan-api-key $BASESCAN_API_KEY \
  --watch \
  <DEPLOYED_CONTRACT_ADDRESS> \
  src/AgentRegistry.sol:AgentRegistry
```

### 2.6 Update deployments.md

Add the mainnet deployment to `protocol/contracts/deployments.md`:

```markdown
| Base Mainnet | 8453 | `<DEPLOYED_ADDRESS>` | `<TX_HASH>` |
```

---

## 3. Registry Server Configuration

The registry server (Axum-based Rust service) reads chain configuration from environment variables at startup. The relevant config fields are defined in `registry/src/config.rs`:

| Env Var | Description |
|---------|-------------|
| `CHAIN_ENABLED` | Set to `true` to enable on-chain anchoring |
| `CHAIN_RPC_URL` | Base mainnet RPC endpoint |
| `CHAIN_PRIVATE_KEY` | Private key of the deployer wallet (hex, with 0x prefix) |
| `CHAIN_CONTRACT_ADDRESS` | Deployed AgentRegistry contract address |

### 3.1 Update the production .env file

Edit `/opt/openagentid/.env` and update the chain-related variables:

```bash
# --- Chain anchoring (Base Mainnet) ---
CHAIN_ENABLED=true
CHAIN_RPC_URL=https://mainnet.base.org
CHAIN_PRIVATE_KEY=0x<your-mainnet-deployer-private-key>
CHAIN_CONTRACT_ADDRESS=<deployed-mainnet-contract-address>
```

If you were previously pointing at Base Sepolia, the old values to replace are:

```bash
# Old testnet values (replace these):
# CHAIN_RPC_URL=https://sepolia.base.org
# CHAIN_CONTRACT_ADDRESS=0x5d9F4e3fb75cE6221665e8f5099192BDA42ebd01
```

### 3.2 Restart the registry server

After updating the `.env` file, restart the service so it picks up the new config:

```bash
sudo systemctl restart openagentid-registry
```

Verify it started correctly:

```bash
sudo journalctl -u openagentid-registry -f --no-pager -n 50
```

Look for log lines confirming chain anchoring is enabled and the contract address is correct.

---

## 4. Post-Deployment Checklist

### 4.1 Verify contract on BaseScan

Open the contract on BaseScan and confirm the source code is verified:

```
https://basescan.org/address/<DEPLOYED_ADDRESS>#code
```

The contract tab should show a green checkmark and display the Solidity source.

### 4.2 Test registration and anchoring

Trigger a test agent registration through the registry API and confirm:

1. The API returns success.
2. The registry server logs show `Anchored <did> on-chain: 0x...`.
3. The transaction is visible on BaseScan.
4. The `agent_identities` table has `chain_status = 'anchored'` and a valid `chain_tx_hash`.

You can verify the on-chain record directly:

```bash
~/.foundry/bin/cast call <DEPLOYED_ADDRESS> \
  "isActive(bytes32)(bool)" \
  $(~/.foundry/bin/cast keccak "did:openagentid:<test-agent-id>") \
  --rpc-url https://mainnet.base.org
```

### 4.3 Monitor deployer wallet balance

The deployer wallet pays gas for every `register()` and `rotateKey()` call. Set up monitoring to alert when the balance drops below a threshold (e.g., 0.001 ETH).

Check balance manually:

```bash
~/.foundry/bin/cast balance <DEPLOYER_ADDRESS> --rpc-url https://mainnet.base.org --ether
```

### 4.4 Confirm agentCount increments

After a successful registration, query the on-chain agent count:

```bash
~/.foundry/bin/cast call <DEPLOYED_ADDRESS> \
  "agentCount()(uint256)" \
  --rpc-url https://mainnet.base.org
```

---

## 5. Cost Estimates

Base L2 gas prices are extremely low. Typical base fee is ~0.005 gwei (0.000000005 gwei effective cost with minimal priority fee).

| Operation | Gas Used | Cost at 0.005 gwei | Cost at 0.01 gwei | USD (ETH=$3000) |
|-----------|----------|--------------------|--------------------|------------------|
| Deploy AgentRegistry | ~500,000 | 0.0000025 ETH | 0.000005 ETH | < $0.02 |
| `register()` | ~100,000 | 0.0000005 ETH | 0.000001 ETH | < $0.01 |
| `rotateKey()` | ~80,000 | 0.0000004 ETH | 0.0000008 ETH | < $0.01 |
| `revoke()` | ~50,000 | 0.00000025 ETH | 0.0000005 ETH | < $0.01 |

**Practical example:** With 0.005 ETH (~$15) in the deployer wallet, you can deploy the contract and execute roughly 10,000 registrations before needing to top up.

Note: Gas prices on Base can spike during periods of high L1 demand. The estimates above use typical 2024-2025 gas prices. Monitor actual costs after deployment.

---

## 6. Security Considerations

### 6.1 Dedicated deployer wallet

Use a wallet that exists solely for this purpose. Do not store significant value in it beyond what is needed for gas. This limits exposure if the private key is compromised.

### 6.2 Private key handling

- Store the private key ONLY in the `/opt/openagentid/.env` file on the production server.
- Set restrictive file permissions: `chmod 600 /opt/openagentid/.env`.
- Never commit the private key to version control.
- Never pass the private key as a CLI argument in production (it will appear in shell history and process listings).

### 6.3 Contract ownership model

The `AgentRegistry` contract is ownerless by design -- there is no admin, no pause, no upgrade mechanism. Each agent record is owned by the `msg.sender` who registered it. This means:

- The deployer wallet does not have special privileges on the contract itself.
- However, the deployer wallet (used as `CHAIN_PRIVATE_KEY` by the registry server) is the `owner` of all agent records it registers. Only it can revoke or rotate keys for those records.
- If the deployer key is compromised, an attacker could revoke or rotate keys for all agents registered by that wallet.

### 6.4 Consider a multisig for contract ownership

While the current contract has no admin functions, future upgrades or governance may require ownership. If you plan to deploy an upgradeable version later, use a multisig (e.g., Safe) as the owner rather than an EOA.

### 6.5 RPC endpoint security

If using a private RPC endpoint with an API key, ensure the key is stored in the `.env` file and not exposed. The public `https://mainnet.base.org` endpoint has rate limits that may be insufficient under heavy load.

### 6.6 Monitoring and incident response

- Monitor the deployer wallet for unexpected transactions.
- Set up alerts for failed anchoring attempts (check registry server logs for `Chain anchoring failed` messages).
- Have a plan to rotate the deployer wallet if compromised: deploy with a new wallet and update `CHAIN_PRIVATE_KEY` in the server config.

---

## Appendix: Quick Reference

| Item | Value |
|------|-------|
| Network | Base Mainnet |
| Chain ID | 8453 |
| RPC URL | https://mainnet.base.org |
| Block Explorer | https://basescan.org |
| Contract | AgentRegistry (to be deployed) |
| Testnet Reference | `0x5d9F4e3fb75cE6221665e8f5099192BDA42ebd01` on Base Sepolia (84532) |
| Server Config Path | `/opt/openagentid/.env` |
| Relevant Env Vars | `CHAIN_ENABLED`, `CHAIN_RPC_URL`, `CHAIN_PRIVATE_KEY`, `CHAIN_CONTRACT_ADDRESS` |
