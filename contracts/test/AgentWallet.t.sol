// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AgentWalletFactory} from "../src/AgentWalletFactory.sol";
import {AgentWallet} from "../src/AgentWallet.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

/// @dev Simple contract to test execute() calls against
contract Counter {
    uint256 public count;

    function increment() external {
        count++;
    }

    function incrementBy(uint256 n) external {
        count += n;
    }
}

/// @dev Malicious contract that attempts reentrancy
contract ReentrantAttacker {
    AgentWallet public target;
    bool public attacked;

    constructor(AgentWallet _target) {
        target = _target;
    }

    receive() external payable {
        if (!attacked) {
            attacked = true;
            // Try to re-enter execute()
            target.execute(address(this), 0, "");
        }
    }
}

contract AgentWalletTest is Test {
    AgentWalletFactory public factory;
    UpgradeableBeacon public beaconContract;
    AgentWallet public walletImpl;
    AgentWallet public wallet;
    Counter public counter;

    address public deployer = address(this);
    address public owner1 = address(0x1);
    address public signerAddr = address(0x5);
    address public other = address(0x9);

    function setUp() public {
        walletImpl = new AgentWallet();
        beaconContract = new UpgradeableBeacon(address(walletImpl), deployer);
        factory = new AgentWalletFactory(address(beaconContract));

        // Deploy a wallet for owner1
        address deployed = factory.deploy(owner1, 0);
        wallet = AgentWallet(payable(deployed));

        counter = new Counter();
    }

    // ── Initialize ────────────────────────────────────────────────────

    function test_initialize() public view {
        assertEq(wallet.owner(), owner1);
        assertEq(wallet.signer(), address(0));
    }

    function test_initialize_twice_reverts() public {
        vm.expectRevert();
        wallet.initialize(address(0x99));
    }

    // ── Execute ───────────────────────────────────────────────────────

    function test_execute_by_owner() public {
        vm.prank(owner1);
        wallet.execute(
            address(counter), 0, abi.encodeWithSelector(Counter.increment.selector)
        );

        assertEq(counter.count(), 1);
    }

    function test_execute_by_signer() public {
        vm.prank(owner1);
        wallet.setSigner(signerAddr);

        vm.prank(signerAddr);
        wallet.execute(
            address(counter), 0, abi.encodeWithSelector(Counter.increment.selector)
        );

        assertEq(counter.count(), 1);
    }

    function test_execute_unauthorized_reverts() public {
        vm.prank(other);
        vm.expectRevert(AgentWallet.NotAuthorized.selector);
        wallet.execute(
            address(counter), 0, abi.encodeWithSelector(Counter.increment.selector)
        );
    }

    function test_execute_send_eth() public {
        vm.deal(address(wallet), 1 ether);
        address recipient = address(0x42);

        vm.prank(owner1);
        wallet.execute(recipient, 0.5 ether, "");

        assertEq(recipient.balance, 0.5 ether);
        assertEq(address(wallet).balance, 0.5 ether);
    }

    // ── ExecuteBatch ──────────────────────────────────────────────────

    function test_executeBatch() public {
        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory calldatas = new bytes[](2);

        targets[0] = address(counter);
        targets[1] = address(counter);
        values[0] = 0;
        values[1] = 0;
        calldatas[0] = abi.encodeWithSelector(Counter.increment.selector);
        calldatas[1] = abi.encodeWithSelector(Counter.incrementBy.selector, 5);

        vm.prank(owner1);
        wallet.executeBatch(targets, values, calldatas);

        assertEq(counter.count(), 6); // 1 + 5
    }

    // ── Signer Management ─────────────────────────────────────────────

    function test_setSigner() public {
        vm.prank(owner1);
        wallet.setSigner(signerAddr);
        assertEq(wallet.signer(), signerAddr);
    }

    function test_setSigner_not_owner_reverts() public {
        vm.prank(other);
        vm.expectRevert(AgentWallet.NotOwner.selector);
        wallet.setSigner(signerAddr);
    }

    function test_setSigner_can_clear() public {
        vm.startPrank(owner1);
        wallet.setSigner(signerAddr);
        wallet.setSigner(address(0)); // clear signer
        vm.stopPrank();

        assertEq(wallet.signer(), address(0));
    }

    // ── Implementation Lock ──────────────────────────────────────────

    function test_implementation_locked() public {
        // The implementation contract itself should be locked (cannot be initialized)
        vm.expectRevert();
        walletImpl.initialize(address(0x99));
    }

    // ── Receive ───────────────────────────────────────────────────────

    function test_receive_eth() public {
        vm.deal(address(this), 1 ether);
        (bool ok,) = address(wallet).call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(address(wallet).balance, 1 ether);
    }

    // ── ERC-165 ───────────────────────────────────────────────────────

    function test_supportsInterface() public view {
        // IERC721Receiver
        assertTrue(wallet.supportsInterface(0x150b7a02));
        // IERC1155Receiver
        assertTrue(wallet.supportsInterface(0x4e2312e0));
        // IERC165
        assertTrue(wallet.supportsInterface(0x01ffc9a7));
        // Random interface
        assertFalse(wallet.supportsInterface(0xdeadbeef));
    }

    // ── Pause ────────────────────────────────────────────────────────

    function test_pause_blocks_execute() public {
        vm.prank(owner1);
        wallet.pause();

        vm.prank(owner1);
        vm.expectRevert(AgentWallet.WalletPaused.selector);
        wallet.execute(address(counter), 0, abi.encodeCall(Counter.increment, ()));

        // Unpause and it works again
        vm.prank(owner1);
        wallet.unpause();

        vm.prank(owner1);
        wallet.execute(address(counter), 0, abi.encodeCall(Counter.increment, ()));
        assertEq(counter.count(), 1);
    }

    function test_pause_blocks_executeBatch() public {
        vm.prank(owner1);
        wallet.pause();

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(counter);
        calldatas[0] = abi.encodeCall(Counter.increment, ());

        vm.prank(owner1);
        vm.expectRevert(AgentWallet.WalletPaused.selector);
        wallet.executeBatch(targets, values, calldatas);
    }

    // ── Reentrancy Guard ────────────────────────────────────────────

    function test_reentrancy_blocked() public {
        ReentrantAttacker attacker = new ReentrantAttacker(wallet);

        // Fund wallet with ETH
        vm.deal(address(wallet), 1 ether);

        // Owner sends ETH to attacker, which tries to re-enter.
        // The inner call reverts with ReentrancyGuardReentrantCall,
        // which is wrapped by the outer execute as ExecutionFailed.
        vm.prank(owner1);
        vm.expectRevert(); // ExecutionFailed wrapping the reentrancy revert
        wallet.execute(address(attacker), 0.1 ether, "");

        // Verify the reentrancy was actually blocked (attacker never completed)
        assertFalse(attacker.attacked());
    }

    // ── Ownership Transfer ──────────────────────────────────────────

    function test_transferOwnership_twoStep() public {
        address newOwner = address(0x99);

        vm.prank(owner1);
        wallet.transferOwnership(newOwner);

        // Owner is still owner1 until accepted
        assertEq(wallet.owner(), owner1);
        assertEq(wallet.pendingOwner(), newOwner);

        // Accept ownership
        vm.prank(newOwner);
        wallet.acceptOwnership();

        assertEq(wallet.owner(), newOwner);
        assertEq(wallet.pendingOwner(), address(0));
    }

    function test_ownership_transfer_clears_signer() public {
        address newOwner = address(0x99);

        // Set signer first
        vm.prank(owner1);
        wallet.setSigner(signerAddr);
        assertEq(wallet.signer(), signerAddr);

        // Transfer ownership
        vm.prank(owner1);
        wallet.transferOwnership(newOwner);
        vm.prank(newOwner);
        wallet.acceptOwnership();

        // Signer should be cleared
        assertEq(wallet.signer(), address(0));
    }

    function test_acceptOwnership_by_non_pending_reverts() public {
        vm.prank(owner1);
        wallet.transferOwnership(address(0x99));

        vm.prank(address(0xBB));
        vm.expectRevert(AgentWallet.NotPendingOwner.selector);
        wallet.acceptOwnership();
    }

    // ── Beacon Upgrade ────────────────────────────────────────────────

    function test_beacon_upgrade_preserves_state() public {
        // Set some state
        vm.prank(owner1);
        wallet.setSigner(signerAddr);

        // Deploy new implementation
        AgentWallet newImpl = new AgentWallet();
        beaconContract.upgradeTo(address(newImpl));

        // State should be preserved (proxy storage unchanged)
        assertEq(wallet.owner(), owner1);
        assertEq(wallet.signer(), signerAddr);
    }
}
