// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";
import {AgentWalletFactory} from "../src/AgentWalletFactory.sol";
import {AgentWallet} from "../src/AgentWallet.sol";
import {TrustPayment} from "../src/TrustPayment.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

/// @title DeployMainnet — Deploy all OAID contracts to Base Mainnet
/// @notice Deploys all 4 contracts, then transfers admin/ownership to Safe multisigs.
///
/// Usage:
///   export DEPLOYER_PRIVATE_KEY=0x...
///   export RELAYER_ADDRESS=0x...        # Registry server hot wallet
///   export SAFE_A=0x14Fc...21DE         # 2/5 multisig (daily admin)
///   export SAFE_B=0x0Af1...5272         # 3/5 multisig (critical ops)
///   export USDC_ADDRESS=0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913  # Base USDC
///
///   forge script script/DeployMainnet.s.sol --rpc-url https://mainnet.base.org --broadcast --verify
contract DeployMainnetScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address relayer = vm.envAddress("RELAYER_ADDRESS");
        address safeA = vm.envAddress("SAFE_A");
        address safeB = vm.envAddress("SAFE_B");
        address usdcAddress = vm.envAddress("USDC_ADDRESS");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== OAID Mainnet Deployment ===");
        console.log("Deployer:", deployer);
        console.log("Relayer:", relayer);
        console.log("Safe A (2/5):", safeA);
        console.log("Safe B (3/5):", safeB);
        console.log("USDC:", usdcAddress);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // ── Step 1: Deploy AgentWallet implementation ─────────────────
        AgentWallet walletImpl = new AgentWallet();
        console.log("[1/6] AgentWallet implementation:", address(walletImpl));

        // ── Step 2: Deploy UpgradeableBeacon ──────────────────────────
        // Owner is deployer initially, will transfer to Safe B
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(walletImpl), deployer);
        console.log("[2/6] UpgradeableBeacon:", address(beacon));

        // ── Step 3: Deploy AgentWalletFactory ─────────────────────────
        AgentWalletFactory factory = new AgentWalletFactory(address(beacon));
        console.log("[3/6] AgentWalletFactory:", address(factory));
        console.log("      WALLET_BYTECODE_HASH:", vm.toString(factory.WALLET_BYTECODE_HASH()));

        // ── Step 4: Deploy AgentRegistry ──────────────────────────────
        // Admin is deployer initially, will transfer to Safe A
        AgentRegistry registry = new AgentRegistry(address(factory), relayer);
        console.log("[4/6] AgentRegistry:", address(registry));

        // ── Step 5: Deploy TrustPayment ──────────────────────────────
        // Admin is deployer initially, will transfer to Safe A
        TrustPayment payment = new TrustPayment(usdcAddress, deployer);
        console.log("[5/6] TrustPayment:", address(payment));

        // ── Step 6: Transfer ownership to Safe multisigs ─────────────
        console.log("");
        console.log("=== Transferring ownership to Safe ===");

        // Beacon owner → Safe B (3/5, critical ops)
        beacon.transferOwnership(safeB);
        console.log("[6a] Beacon.transferOwnership -> Safe B (3/5)");

        // Registry admin → Safe A (2/5, daily admin)
        registry.transferAdmin(safeA);
        console.log("[6b] Registry.transferAdmin -> Safe A (2/5)");
        console.log("     NOTE: Safe A must call registry.acceptAdmin() to complete");

        // TrustPayment admin → Safe A (2/5, daily admin)
        payment.transferAdmin(safeA);
        console.log("[6c] TrustPayment.transferAdmin -> Safe A (2/5)");
        console.log("     NOTE: Safe A must call payment.acceptAdmin() to complete");

        vm.stopBroadcast();

        // ── Summary ──────────────────────────────────────────────────
        console.log("");
        console.log("=== DEPLOYMENT COMPLETE ===");
        console.log("");
        console.log("Contracts:");
        console.log("  AgentWallet impl:   ", address(walletImpl));
        console.log("  UpgradeableBeacon:  ", address(beacon));
        console.log("  AgentWalletFactory: ", address(factory));
        console.log("  AgentRegistry:      ", address(registry));
        console.log("  TrustPayment:       ", address(payment));
        console.log("");
        console.log("WALLET_BYTECODE_HASH: ", vm.toString(factory.WALLET_BYTECODE_HASH()));
        console.log("");
        console.log("NEXT STEPS:");
        console.log("  1. Safe A (2/5) must call registry.acceptAdmin()");
        console.log("  2. Safe A (2/5) must call payment.acceptAdmin()");
        console.log("  3. Update registry server .env with new contract addresses");
        console.log("  4. Fund relayer wallet with ETH for gas");
    }
}
