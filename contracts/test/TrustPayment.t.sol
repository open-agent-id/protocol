// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {TrustPayment} from "../src/TrustPayment.sol";

contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {
        _mint(msg.sender, 1_000_000 * 1e6); // mint 1M USDC
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

contract TrustPaymentTest is Test {
    TrustPayment public payment;
    MockUSDC public usdc;

    address admin = makeAddr("admin");
    address payer = makeAddr("payer");
    address nonAdmin = makeAddr("nonAdmin");

    string constant AGENT_DID = "did:oaid:base:0x1234567890abcdef";
    string constant REPORTER_DID = "did:oaid:base:0xfedcba0987654321";

    function setUp() public {
        // Deploy mock USDC (minted to this test contract)
        usdc = new MockUSDC();

        // Deploy TrustPayment
        payment = new TrustPayment(address(usdc), admin);

        // Fund the payer with 1000 USDC
        usdc.transfer(payer, 1000 * 1e6);
    }

    // --- payVerification tests ---

    function test_payVerification_success() public {
        vm.startPrank(payer);
        usdc.approve(address(payment), payment.VERIFICATION_FEE());

        vm.expectEmit(true, true, false, true);
        emit TrustPayment.VerificationPaid(AGENT_DID, AGENT_DID, payer, 10 * 1e6);

        payment.payVerification(AGENT_DID);
        vm.stopPrank();

        assertEq(usdc.balanceOf(address(payment)), 10 * 1e6);
        assertEq(usdc.balanceOf(payer), 990 * 1e6);
    }

    function test_payVerification_insufficientBalance() public {
        // Give payer only 5 USDC
        address poorPayer = makeAddr("poorPayer");
        usdc.transfer(poorPayer, 5 * 1e6);

        vm.startPrank(poorPayer);
        usdc.approve(address(payment), payment.VERIFICATION_FEE());

        vm.expectRevert();
        payment.payVerification(AGENT_DID);
        vm.stopPrank();
    }

    function test_payVerification_noApproval() public {
        vm.startPrank(payer);
        // No approval given

        vm.expectRevert();
        payment.payVerification(AGENT_DID);
        vm.stopPrank();
    }

    // --- payReport tests ---

    function test_payReport_success() public {
        vm.startPrank(payer);
        usdc.approve(address(payment), payment.REPORT_FEE());

        vm.expectEmit(true, true, true, true);
        emit TrustPayment.ReportPaid(
            AGENT_DID, AGENT_DID, REPORTER_DID, REPORTER_DID, payer, 1 * 1e6
        );

        payment.payReport(AGENT_DID, REPORTER_DID);
        vm.stopPrank();

        assertEq(usdc.balanceOf(address(payment)), 1 * 1e6);
        assertEq(usdc.balanceOf(payer), 999 * 1e6);
    }

    // --- withdraw tests ---

    function test_withdraw_byAdmin() public {
        // First, have payer make a verification payment
        vm.startPrank(payer);
        usdc.approve(address(payment), payment.VERIFICATION_FEE());
        payment.payVerification(AGENT_DID);
        vm.stopPrank();

        // Admin withdraws
        address recipient = makeAddr("recipient");

        vm.startPrank(admin);
        vm.expectEmit(true, false, false, true);
        emit TrustPayment.Withdrawn(recipient, 10 * 1e6);

        payment.withdraw(recipient, 10 * 1e6);
        vm.stopPrank();

        assertEq(usdc.balanceOf(recipient), 10 * 1e6);
        assertEq(usdc.balanceOf(address(payment)), 0);
    }

    function test_withdraw_toZeroAddress_reverts() public {
        // Fund the contract
        vm.startPrank(payer);
        usdc.approve(address(payment), payment.VERIFICATION_FEE());
        payment.payVerification(AGENT_DID);
        vm.stopPrank();

        // Admin tries to withdraw to zero address
        vm.startPrank(admin);
        vm.expectRevert(TrustPayment.ZeroAddress.selector);
        payment.withdraw(address(0), 10 * 1e6);
        vm.stopPrank();
    }

    function test_withdraw_byNonAdmin_reverts() public {
        // First, fund the contract
        vm.startPrank(payer);
        usdc.approve(address(payment), payment.VERIFICATION_FEE());
        payment.payVerification(AGENT_DID);
        vm.stopPrank();

        // Non-admin tries to withdraw
        vm.startPrank(nonAdmin);
        vm.expectRevert(TrustPayment.NotAdmin.selector);
        payment.withdraw(nonAdmin, 10 * 1e6);
        vm.stopPrank();
    }

    // --- setAdmin tests ---

    function test_setAdmin_byAdmin() public {
        address newAdmin = makeAddr("newAdmin");

        vm.prank(admin);
        payment.setAdmin(newAdmin);

        assertEq(payment.admin(), newAdmin);
    }

    function test_setAdmin_byNonAdmin_reverts() public {
        vm.prank(nonAdmin);
        vm.expectRevert(TrustPayment.NotAdmin.selector);
        payment.setAdmin(nonAdmin);
    }

    function test_setAdmin_zeroAddress_reverts() public {
        vm.prank(admin);
        vm.expectRevert(TrustPayment.ZeroAddress.selector);
        payment.setAdmin(address(0));
    }

    function test_withdraw_zeroAmount_reverts() public {
        // Fund the contract
        vm.startPrank(payer);
        usdc.approve(address(payment), payment.VERIFICATION_FEE());
        payment.payVerification(AGENT_DID);
        vm.stopPrank();

        vm.prank(admin);
        vm.expectRevert(TrustPayment.ZeroAmount.selector);
        payment.withdraw(makeAddr("recipient"), 0);
    }

    function test_payVerification_emptyDid_reverts() public {
        vm.startPrank(payer);
        usdc.approve(address(payment), payment.VERIFICATION_FEE());
        vm.expectRevert(TrustPayment.EmptyDid.selector);
        payment.payVerification("");
        vm.stopPrank();
    }
}
