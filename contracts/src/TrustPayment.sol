// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TrustPayment {
    IERC20 public immutable usdc;
    address public admin;

    uint256 public constant VERIFICATION_FEE = 10 * 1e6; // $10 USDC (6 decimals)
    uint256 public constant REPORT_FEE = 1 * 1e6; // $1 USDC (6 decimals)
    uint256 public referralCommission = 1 * 1e6; // $1 USDC default

    event VerificationPaid(
        string indexed agentDidHash, // keccak256 of DID string for indexing
        string agentDid, // actual DID string
        address indexed payer,
        uint256 amount
    );

    event ReportPaid(
        string indexed reportedDidHash,
        string reportedDid,
        string indexed reporterDidHash,
        string reporterDid,
        address indexed payer,
        uint256 amount
    );

    event ReferralPaid(string agentDid, address indexed referrer, uint256 amount);

    event Withdrawn(address indexed to, uint256 amount);

    event AdminTransferred(address indexed oldAdmin, address indexed newAdmin);

    error TransferFailed();
    error NotAdmin();
    error ZeroAddress();
    error EmptyDid();
    error ZeroAmount();
    error SelfReferral();
    error InsufficientBalance();

    constructor(address _usdc, address _admin) {
        usdc = IERC20(_usdc);
        admin = _admin;
    }

    /// @notice Pay $10 USDC to verify an agent
    /// @param agentDid The DID of the agent to verify
    function payVerification(string calldata agentDid) external {
        if (bytes(agentDid).length == 0) revert EmptyDid();
        bool ok = usdc.transferFrom(msg.sender, address(this), VERIFICATION_FEE);
        if (!ok) revert TransferFailed();

        emit VerificationPaid(agentDid, agentDid, msg.sender, VERIFICATION_FEE);
    }

    /// @notice Pay $10 USDC to verify an agent, with optional referral commission
    /// @param agentDid The DID of the agent to verify
    /// @param referrer The address that referred this verification (or address(0) for none)
    function payVerificationWithReferral(string calldata agentDid, address referrer) external {
        if (bytes(agentDid).length == 0) revert EmptyDid();
        if (referrer == msg.sender) revert SelfReferral();

        bool ok = usdc.transferFrom(msg.sender, address(this), VERIFICATION_FEE);
        if (!ok) revert TransferFailed();

        emit VerificationPaid(agentDid, agentDid, msg.sender, VERIFICATION_FEE);

        if (referrer != address(0) && referralCommission > 0) {
            if (usdc.balanceOf(address(this)) < referralCommission) revert InsufficientBalance();
            // Try to pay referrer; skip if transfer fails (e.g., blocklisted address)
            (bool success, ) = address(usdc).call(
                abi.encodeWithSelector(usdc.transfer.selector, referrer, referralCommission)
            );
            if (success) {
                emit ReferralPaid(agentDid, referrer, referralCommission);
            }
            // If transfer fails, verification still succeeds — referral is best-effort
        }
    }

    /// @notice Set the referral commission amount (admin only)
    /// @param _amount The new referral commission in USDC (6 decimals), 0 to disable
    function setReferralCommission(uint256 _amount) external {
        if (msg.sender != admin) revert NotAdmin();
        require(_amount <= VERIFICATION_FEE, "Commission exceeds fee");
        referralCommission = _amount;
    }

    /// @notice Pay $1 USDC to file a report against an agent
    /// @param reportedDid The DID of the agent being reported
    /// @param reporterDid The DID of the reporting agent
    function payReport(string calldata reportedDid, string calldata reporterDid) external {
        if (bytes(reportedDid).length == 0) revert EmptyDid();
        if (bytes(reporterDid).length == 0) revert EmptyDid();
        bool ok = usdc.transferFrom(msg.sender, address(this), REPORT_FEE);
        if (!ok) revert TransferFailed();

        emit ReportPaid(reportedDid, reportedDid, reporterDid, reporterDid, msg.sender, REPORT_FEE);
    }

    /// @notice Admin withdraws collected fees
    /// @param to The address to send the funds to
    /// @param amount The amount to withdraw
    function withdraw(address to, uint256 amount) external {
        if (msg.sender != admin) revert NotAdmin();
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        uint256 balBefore = usdc.balanceOf(address(this));
        bool ok = usdc.transfer(to, amount);
        if (!ok) revert TransferFailed();
        if (usdc.balanceOf(address(this)) != balBefore - amount) revert TransferFailed();
        emit Withdrawn(to, amount);
    }

    /// @notice Transfer admin role to a new address
    /// @param newAdmin The new admin address
    function setAdmin(address newAdmin) external {
        if (msg.sender != admin) revert NotAdmin();
        if (newAdmin == address(0)) revert ZeroAddress();
        emit AdminTransferred(admin, newAdmin);
        admin = newAdmin;
    }
}
