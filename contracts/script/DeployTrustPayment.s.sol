// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {TrustPayment} from "../src/TrustPayment.sol";

contract DeployTrustPaymentScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address usdcAddress = vm.envAddress("USDC_ADDRESS");
        address admin = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        TrustPayment payment = new TrustPayment(usdcAddress, admin);
        console.log("TrustPayment deployed at:", address(payment));
        console.log("  USDC:", usdcAddress);
        console.log("  Admin:", admin);

        vm.stopBroadcast();
    }
}
