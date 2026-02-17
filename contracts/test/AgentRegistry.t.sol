// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";

contract AgentRegistryTest is Test {
    AgentRegistry public registry;
    address public owner = address(0x1);
    address public other = address(0x2);

    bytes32 public didHash = keccak256("did:agent:tokli:agt_a1B2c3D4e5");
    bytes32 public pubKeyHash = keccak256("test_public_key_bytes");
    bytes32 public platform = keccak256("tokli");

    function setUp() public {
        registry = new AgentRegistry();
    }

    function test_register() public {
        vm.prank(owner);
        registry.register(didHash, pubKeyHash, platform);

        AgentRegistry.AgentRecord memory agent = registry.getAgent(didHash);
        assertEq(agent.pubKeyHash, pubKeyHash);
        assertEq(agent.owner, owner);
        assertEq(agent.platform, platform);
        assertTrue(agent.status == AgentRegistry.Status.Active);
        assertEq(registry.agentCount(), 1);
    }

    function test_register_emits_event() public {
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit AgentRegistry.AgentRegistered(didHash, pubKeyHash, platform, owner);
        registry.register(didHash, pubKeyHash, platform);
    }

    function test_register_duplicate_reverts() public {
        vm.prank(owner);
        registry.register(didHash, pubKeyHash, platform);

        vm.prank(owner);
        vm.expectRevert(AgentRegistry.AgentAlreadyExists.selector);
        registry.register(didHash, pubKeyHash, platform);
    }

    function test_register_zero_hash_reverts() public {
        vm.prank(owner);
        vm.expectRevert(AgentRegistry.InvalidHash.selector);
        registry.register(bytes32(0), pubKeyHash, platform);

        vm.prank(owner);
        vm.expectRevert(AgentRegistry.InvalidHash.selector);
        registry.register(didHash, bytes32(0), platform);
    }

    function test_revoke() public {
        vm.prank(owner);
        registry.register(didHash, pubKeyHash, platform);

        vm.prank(owner);
        registry.revoke(didHash);

        AgentRegistry.AgentRecord memory agent = registry.getAgent(didHash);
        assertTrue(agent.status == AgentRegistry.Status.Revoked);
    }

    function test_revoke_not_owner_reverts() public {
        vm.prank(owner);
        registry.register(didHash, pubKeyHash, platform);

        vm.prank(other);
        vm.expectRevert(AgentRegistry.NotOwner.selector);
        registry.revoke(didHash);
    }

    function test_revoke_nonexistent_reverts() public {
        vm.prank(owner);
        vm.expectRevert(AgentRegistry.AgentNotFound.selector);
        registry.revoke(didHash);
    }

    function test_revoke_already_revoked_reverts() public {
        vm.prank(owner);
        registry.register(didHash, pubKeyHash, platform);

        vm.prank(owner);
        registry.revoke(didHash);

        vm.prank(owner);
        vm.expectRevert(AgentRegistry.AgentNotActive.selector);
        registry.revoke(didHash);
    }

    function test_rotateKey() public {
        vm.prank(owner);
        registry.register(didHash, pubKeyHash, platform);

        bytes32 newPubKeyHash = keccak256("new_public_key_bytes");

        vm.prank(owner);
        registry.rotateKey(didHash, newPubKeyHash);

        AgentRegistry.AgentRecord memory agent = registry.getAgent(didHash);
        assertEq(agent.pubKeyHash, newPubKeyHash);
    }

    function test_rotateKey_emits_event() public {
        vm.prank(owner);
        registry.register(didHash, pubKeyHash, platform);

        bytes32 newPubKeyHash = keccak256("new_public_key_bytes");

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit AgentRegistry.KeyRotated(didHash, pubKeyHash, newPubKeyHash);
        registry.rotateKey(didHash, newPubKeyHash);
    }

    function test_rotateKey_not_owner_reverts() public {
        vm.prank(owner);
        registry.register(didHash, pubKeyHash, platform);

        vm.prank(other);
        vm.expectRevert(AgentRegistry.NotOwner.selector);
        registry.rotateKey(didHash, keccak256("new_key"));
    }

    function test_rotateKey_zero_hash_reverts() public {
        vm.prank(owner);
        registry.register(didHash, pubKeyHash, platform);

        vm.prank(owner);
        vm.expectRevert(AgentRegistry.InvalidHash.selector);
        registry.rotateKey(didHash, bytes32(0));
    }

    function test_isActive() public {
        assertFalse(registry.isActive(didHash));

        vm.prank(owner);
        registry.register(didHash, pubKeyHash, platform);
        assertTrue(registry.isActive(didHash));

        vm.prank(owner);
        registry.revoke(didHash);
        assertFalse(registry.isActive(didHash));
    }

    function test_getAgent_nonexistent_reverts() public {
        vm.expectRevert(AgentRegistry.AgentNotFound.selector);
        registry.getAgent(didHash);
    }
}
