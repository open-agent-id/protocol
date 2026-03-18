// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";
import {AgentWalletFactory} from "../src/AgentWalletFactory.sol";
import {AgentWallet} from "../src/AgentWallet.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

contract AgentRegistryTest is Test {
    AgentRegistry public registry;
    AgentWalletFactory public factory;
    UpgradeableBeacon public beacon;
    AgentWallet public walletImpl;

    address public deployer = address(this);
    address public relayer = address(0xBEEF);
    address public owner1 = address(0x1);
    address public owner2 = address(0x2);

    bytes32 public pubKeyHash1 = keccak256("ed25519_pub_key_1");
    bytes32 public pubKeyHash2 = keccak256("ed25519_pub_key_2");

    function setUp() public {
        // Deploy implementation
        walletImpl = new AgentWallet();

        // Deploy beacon pointing to implementation
        beacon = new UpgradeableBeacon(address(walletImpl), deployer);

        // Deploy factory with beacon
        factory = new AgentWalletFactory(address(beacon));

        // Deploy registry with factory and relayer
        registry = new AgentRegistry(address(factory), relayer);
    }

    // ── Registration ──────────────────────────────────────────────────

    function test_register() public {
        vm.prank(relayer);
        registry.register(pubKeyHash1, owner1, 0);

        address agentAddr = factory.computeAddress(owner1, 0);
        AgentRegistry.AgentRecord memory agent = registry.getAgent(agentAddr);

        assertEq(agent.pubKeyHash, pubKeyHash1);
        assertEq(agent.owner, owner1);
        assertTrue(agent.status == AgentRegistry.Status.Active);
        assertEq(registry.agentCount(), 1);
    }

    function test_register_emits_event() public {
        address agentAddr = factory.computeAddress(owner1, 0);

        vm.prank(relayer);
        vm.expectEmit(true, true, true, true);
        emit AgentRegistry.AgentRegistered(agentAddr, pubKeyHash1, owner1);
        registry.register(pubKeyHash1, owner1, 0);
    }

    function test_register_not_relayer_reverts() public {
        vm.prank(owner1);
        vm.expectRevert(AgentRegistry.NotRelayer.selector);
        registry.register(pubKeyHash1, owner1, 0);
    }

    function test_register_duplicate_reverts() public {
        vm.prank(relayer);
        registry.register(pubKeyHash1, owner1, 0);

        vm.prank(relayer);
        vm.expectRevert(AgentRegistry.AgentAlreadyExists.selector);
        registry.register(pubKeyHash1, owner1, 0);
    }

    function test_register_zero_hash_reverts() public {
        vm.prank(relayer);
        vm.expectRevert(AgentRegistry.InvalidHash.selector);
        registry.register(bytes32(0), owner1, 0);
    }

    function test_register_multiple_agents_same_owner() public {
        vm.startPrank(relayer);
        registry.register(pubKeyHash1, owner1, 0);
        registry.register(pubKeyHash2, owner1, 1);
        vm.stopPrank();

        address agent0 = factory.computeAddress(owner1, 0);
        address agent1 = factory.computeAddress(owner1, 1);

        assertTrue(agent0 != agent1);
        assertTrue(registry.isActive(agent0));
        assertTrue(registry.isActive(agent1));
        assertEq(registry.agentCount(), 2);
    }

    // ── Batch Registration ────────────────────────────────────────────

    function test_registerBatch() public {
        bytes32[] memory hashes = new bytes32[](3);
        address[] memory owners = new address[](3);
        uint256[] memory nonces = new uint256[](3);

        hashes[0] = keccak256("key_a");
        hashes[1] = keccak256("key_b");
        hashes[2] = keccak256("key_c");
        owners[0] = owner1;
        owners[1] = owner1;
        owners[2] = owner2;
        nonces[0] = 0;
        nonces[1] = 1;
        nonces[2] = 0;

        vm.prank(relayer);
        registry.registerBatch(hashes, owners, nonces);

        assertEq(registry.agentCount(), 3);
        assertTrue(registry.isActive(factory.computeAddress(owner1, 0)));
        assertTrue(registry.isActive(factory.computeAddress(owner1, 1)));
        assertTrue(registry.isActive(factory.computeAddress(owner2, 0)));
    }

    function test_registerBatch_skips_duplicates() public {
        // Register one first
        vm.prank(relayer);
        registry.register(pubKeyHash1, owner1, 0);

        // Batch includes the already-registered agent
        bytes32[] memory hashes = new bytes32[](2);
        address[] memory owners = new address[](2);
        uint256[] memory nonces = new uint256[](2);

        hashes[0] = pubKeyHash1; // duplicate
        hashes[1] = pubKeyHash2; // new
        owners[0] = owner1;
        owners[1] = owner1;
        nonces[0] = 0; // duplicate
        nonces[1] = 1; // new

        address dupAddr = factory.computeAddress(owner1, 0);

        vm.prank(relayer);
        vm.expectEmit(true, true, false, true);
        emit AgentRegistry.AgentSkipped(dupAddr, owner1, 0);
        registry.registerBatch(hashes, owners, nonces);

        assertEq(registry.agentCount(), 2); // only 2, not 3
    }

    function test_registerBatch_skips_zero_hash() public {
        bytes32[] memory hashes = new bytes32[](2);
        address[] memory owners = new address[](2);
        uint256[] memory nonces = new uint256[](2);

        hashes[0] = bytes32(0); // invalid, skip
        hashes[1] = pubKeyHash1;
        owners[0] = owner1;
        owners[1] = owner1;
        nonces[0] = 0;
        nonces[1] = 1;

        vm.prank(relayer);
        registry.registerBatch(hashes, owners, nonces);

        assertEq(registry.agentCount(), 1);
    }

    function test_registerBatch_length_mismatch_reverts() public {
        bytes32[] memory hashes = new bytes32[](2);
        address[] memory owners = new address[](1);
        uint256[] memory nonces = new uint256[](2);

        hashes[0] = pubKeyHash1;
        hashes[1] = pubKeyHash2;
        owners[0] = owner1;
        nonces[0] = 0;
        nonces[1] = 1;

        vm.prank(relayer);
        vm.expectRevert(AgentRegistry.LengthMismatch.selector);
        registry.registerBatch(hashes, owners, nonces);
    }

    function test_registerBatch_not_relayer_reverts() public {
        bytes32[] memory hashes = new bytes32[](1);
        address[] memory owners = new address[](1);
        uint256[] memory nonces = new uint256[](1);

        hashes[0] = pubKeyHash1;
        owners[0] = owner1;
        nonces[0] = 0;

        vm.prank(owner1);
        vm.expectRevert(AgentRegistry.NotRelayer.selector);
        registry.registerBatch(hashes, owners, nonces);
    }

    // ── Revoke ────────────────────────────────────────────────────────

    function test_revoke() public {
        vm.prank(relayer);
        registry.register(pubKeyHash1, owner1, 0);

        address agentAddr = factory.computeAddress(owner1, 0);

        vm.prank(owner1);
        registry.revoke(agentAddr);

        AgentRegistry.AgentRecord memory agent = registry.getAgent(agentAddr);
        assertTrue(agent.status == AgentRegistry.Status.Revoked);
        assertFalse(registry.isActive(agentAddr));
    }

    function test_revoke_not_owner_reverts() public {
        vm.prank(relayer);
        registry.register(pubKeyHash1, owner1, 0);

        address agentAddr = factory.computeAddress(owner1, 0);

        vm.prank(owner2);
        vm.expectRevert(AgentRegistry.NotOwner.selector);
        registry.revoke(agentAddr);
    }

    function test_revoke_nonexistent_reverts() public {
        vm.prank(owner1);
        vm.expectRevert(AgentRegistry.AgentNotFound.selector);
        registry.revoke(address(0xDEAD));
    }

    function test_revoke_already_revoked_reverts() public {
        vm.prank(relayer);
        registry.register(pubKeyHash1, owner1, 0);

        address agentAddr = factory.computeAddress(owner1, 0);

        vm.prank(owner1);
        registry.revoke(agentAddr);

        vm.prank(owner1);
        vm.expectRevert(AgentRegistry.AgentNotActive.selector);
        registry.revoke(agentAddr);
    }

    // ── Key Rotation ──────────────────────────────────────────────────

    function test_rotateKey() public {
        vm.prank(relayer);
        registry.register(pubKeyHash1, owner1, 0);

        address agentAddr = factory.computeAddress(owner1, 0);
        bytes32 newKey = keccak256("new_ed25519_key");

        vm.prank(owner1);
        registry.rotateKey(agentAddr, newKey);

        AgentRegistry.AgentRecord memory agent = registry.getAgent(agentAddr);
        assertEq(agent.pubKeyHash, newKey);
    }

    function test_rotateKey_emits_event() public {
        vm.prank(relayer);
        registry.register(pubKeyHash1, owner1, 0);

        address agentAddr = factory.computeAddress(owner1, 0);
        bytes32 newKey = keccak256("new_ed25519_key");

        vm.prank(owner1);
        vm.expectEmit(true, true, true, true);
        emit AgentRegistry.KeyRotated(agentAddr, pubKeyHash1, newKey);
        registry.rotateKey(agentAddr, newKey);
    }

    function test_rotateKey_not_owner_reverts() public {
        vm.prank(relayer);
        registry.register(pubKeyHash1, owner1, 0);

        address agentAddr = factory.computeAddress(owner1, 0);

        vm.prank(owner2);
        vm.expectRevert(AgentRegistry.NotOwner.selector);
        registry.rotateKey(agentAddr, keccak256("new_key"));
    }

    function test_rotateKey_zero_hash_reverts() public {
        vm.prank(relayer);
        registry.register(pubKeyHash1, owner1, 0);

        address agentAddr = factory.computeAddress(owner1, 0);

        vm.prank(owner1);
        vm.expectRevert(AgentRegistry.InvalidHash.selector);
        registry.rotateKey(agentAddr, bytes32(0));
    }

    // ── Queries ───────────────────────────────────────────────────────

    function test_isActive() public {
        address agentAddr = factory.computeAddress(owner1, 0);
        assertFalse(registry.isActive(agentAddr));

        vm.prank(relayer);
        registry.register(pubKeyHash1, owner1, 0);
        assertTrue(registry.isActive(agentAddr));

        vm.prank(owner1);
        registry.revoke(agentAddr);
        assertFalse(registry.isActive(agentAddr));
    }

    function test_getAgent_nonexistent_reverts() public {
        vm.expectRevert(AgentRegistry.AgentNotFound.selector);
        registry.getAgent(address(0xDEAD));
    }

    // ── Admin ─────────────────────────────────────────────────────────

    function test_setRelayer() public {
        address newRelayer = address(0xCAFE);

        vm.expectEmit(true, true, false, true);
        emit AgentRegistry.RelayerUpdated(relayer, newRelayer);
        registry.setRelayer(newRelayer);

        // Old relayer should be rejected
        vm.prank(relayer);
        vm.expectRevert(AgentRegistry.NotRelayer.selector);
        registry.register(pubKeyHash1, owner1, 0);

        // New relayer should work
        vm.prank(newRelayer);
        registry.register(pubKeyHash1, owner1, 0);
    }

    function test_setRelayer_not_admin_reverts() public {
        vm.prank(owner1);
        vm.expectRevert(AgentRegistry.NotAdmin.selector);
        registry.setRelayer(address(0xCAFE));
    }

    function test_transferAdmin() public {
        address newAdmin = address(0xAD);

        vm.expectEmit(true, true, false, true);
        emit AgentRegistry.AdminTransferred(deployer, newAdmin);
        registry.transferAdmin(newAdmin);

        // Old admin should be rejected
        vm.expectRevert(AgentRegistry.NotAdmin.selector);
        registry.setRelayer(address(0xCAFE));

        // New admin should work
        vm.prank(newAdmin);
        registry.setRelayer(address(0xCAFE));
    }

    function test_setRelayer_zero_reverts() public {
        vm.expectRevert(AgentRegistry.ZeroAddress.selector);
        registry.setRelayer(address(0));
    }

    function test_transferAdmin_zero_reverts() public {
        vm.expectRevert(AgentRegistry.ZeroAddress.selector);
        registry.transferAdmin(address(0));
    }

    function test_register_zeroAddress_owner_reverts() public {
        vm.prank(relayer);
        vm.expectRevert(AgentRegistry.ZeroAddress.selector);
        registry.register(pubKeyHash1, address(0), 0);
    }

    function test_registerBatch_exceeds_max_batch_size_reverts() public {
        uint256 size = 101;
        bytes32[] memory hashes = new bytes32[](size);
        address[] memory owners = new address[](size);
        uint256[] memory nonces = new uint256[](size);

        for (uint256 i = 0; i < size; i++) {
            hashes[i] = keccak256(abi.encodePacked("key_", i));
            owners[i] = address(uint160(i + 1));
            nonces[i] = 0;
        }

        vm.prank(relayer);
        vm.expectRevert(AgentRegistry.BatchTooLarge.selector);
        registry.registerBatch(hashes, owners, nonces);
    }

    // ── CREATE2 Address Determinism ───────────────────────────────────

    function test_address_determinism() public view {
        address addr1 = factory.computeAddress(owner1, 0);
        address addr2 = factory.computeAddress(owner1, 0);
        assertEq(addr1, addr2);

        // Different nonce → different address
        address addr3 = factory.computeAddress(owner1, 1);
        assertTrue(addr1 != addr3);

        // Different owner → different address
        address addr4 = factory.computeAddress(owner2, 0);
        assertTrue(addr1 != addr4);
    }
}
