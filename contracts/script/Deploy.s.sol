// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";
import {AgentWalletFactory} from "../src/AgentWalletFactory.sol";
import {AgentWallet} from "../src/AgentWallet.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address relayer = vm.envAddress("RELAYER_ADDRESS");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy wallet implementation
        AgentWallet walletImpl = new AgentWallet();
        console.log("AgentWallet implementation:", address(walletImpl));

        // 2. Deploy beacon (deployer = beacon owner, can upgrade)
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(walletImpl), deployer);
        console.log("UpgradeableBeacon:", address(beacon));

        // 3. Deploy factory
        AgentWalletFactory factory = new AgentWalletFactory(address(beacon));
        console.log("AgentWalletFactory:", address(factory));
        console.log("  WALLET_BYTECODE_HASH:", vm.toString(factory.WALLET_BYTECODE_HASH()));

        // 4. Deploy registry
        AgentRegistry registry = new AgentRegistry(address(factory), relayer);
        console.log("AgentRegistry:", address(registry));
        console.log("  relayer:", relayer);
        console.log("  admin:", deployer);

        vm.stopBroadcast();
    }
}
