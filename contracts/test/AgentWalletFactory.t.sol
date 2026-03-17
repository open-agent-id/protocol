// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AgentWalletFactory} from "../src/AgentWalletFactory.sol";
import {AgentWallet} from "../src/AgentWallet.sol";
import {IAgentWalletFactory} from "../src/interfaces/IAgentWalletFactory.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

contract AgentWalletFactoryTest is Test {
    AgentWalletFactory public factory;
    UpgradeableBeacon public beacon;
    AgentWallet public walletImpl;

    address public deployer = address(this);
    address public owner1 = address(0x1);
    address public owner2 = address(0x2);

    function setUp() public {
        walletImpl = new AgentWallet();
        beacon = new UpgradeableBeacon(address(walletImpl), deployer);
        factory = new AgentWalletFactory(address(beacon));
    }

    function test_computeAddress_deterministic() public view {
        address addr1 = factory.computeAddress(owner1, 0);
        address addr2 = factory.computeAddress(owner1, 0);
        assertEq(addr1, addr2);
    }

    function test_computeAddress_different_nonce() public view {
        address addr0 = factory.computeAddress(owner1, 0);
        address addr1 = factory.computeAddress(owner1, 1);
        assertTrue(addr0 != addr1);
    }

    function test_computeAddress_different_owner() public view {
        address addr1 = factory.computeAddress(owner1, 0);
        address addr2 = factory.computeAddress(owner2, 0);
        assertTrue(addr1 != addr2);
    }

    function test_deploy() public {
        address predicted = factory.computeAddress(owner1, 0);
        address deployed = factory.deploy(owner1, 0);

        assertEq(predicted, deployed);
        assertEq(AgentWallet(payable(deployed)).owner(), owner1);
    }

    function test_deploy_emits_event() public {
        address predicted = factory.computeAddress(owner1, 0);

        vm.expectEmit(true, true, false, true);
        emit IAgentWalletFactory.WalletDeployed(predicted, owner1, 0);
        factory.deploy(owner1, 0);
    }

    function test_deploy_duplicate_reverts() public {
        factory.deploy(owner1, 0);

        // CREATE2 with same salt should revert
        vm.expectRevert();
        factory.deploy(owner1, 0);
    }

    function test_deploy_multiple() public {
        address wallet0 = factory.deploy(owner1, 0);
        address wallet1 = factory.deploy(owner1, 1);
        address wallet2 = factory.deploy(owner2, 0);

        assertTrue(wallet0 != wallet1);
        assertTrue(wallet0 != wallet2);

        assertEq(AgentWallet(payable(wallet0)).owner(), owner1);
        assertEq(AgentWallet(payable(wallet1)).owner(), owner1);
        assertEq(AgentWallet(payable(wallet2)).owner(), owner2);
    }

    function test_deploy_receives_eth() public {
        address wallet = factory.deploy(owner1, 0);

        // Send ETH to the deployed wallet
        vm.deal(address(this), 1 ether);
        (bool ok,) = wallet.call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(wallet.balance, 1 ether);
    }

    function test_precomputed_address_receives_eth() public {
        // ETH can be sent to the address BEFORE deployment
        address predicted = factory.computeAddress(owner1, 0);

        vm.deal(address(this), 1 ether);
        (bool ok,) = predicted.call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(predicted.balance, 1 ether);

        // Now deploy — the ETH is still there
        address deployed = factory.deploy(owner1, 0);
        assertEq(deployed, predicted);
        assertEq(deployed.balance, 1 ether);
    }

    function test_bytecodeHash_immutable() public view {
        bytes32 hash = factory.WALLET_BYTECODE_HASH();
        assertTrue(hash != bytes32(0));
    }

    function test_deploy_permissionless() public {
        // Anyone can deploy (not just owner or relayer)
        address random = address(0xDEAD);
        vm.prank(random);
        address wallet = factory.deploy(owner1, 0);

        // But owner is still owner1
        assertEq(AgentWallet(payable(wallet)).owner(), owner1);
    }
}
