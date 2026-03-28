// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TrustPayment {
    IERC20 public immutable usdc;
    address public admin;
    address public pendingAdmin;

    uint256 public constant VERIFICATION_FEE = 10 * 1e6; // $10 USDC (6 decimals)
    uint256 public constant REPORT_FEE = 1 * 1e6; // $1 USDC (6 decimals)
    uint256 public constant MAX_REFERRAL_COMMISSION = 5 * 1e6; // $5 max (50% of fee)
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
    event ReferralFailed(string agentDid, address indexed referrer, uint256 amount);

    event Withdrawn(address indexed to, uint256 amount);

    event AdminTransferred(address indexed oldAdmin, address indexed newAdmin);
    event AdminTransferStarted(address indexed currentAdmin, address indexed newAdmin);
    event ReferralCommissionUpdated(uint256 oldAmount, uint256 newAmount);

    error TransferFailed();
    error NotAdmin();
    error NotPendingAdmin();
    error ZeroAddress();
    error EmptyDid();
    error ZeroAmount();
    error SelfReferral();
    error InsufficientBalance();
    error CommissionTooHigh();

    constructor(address _usdc, address _admin) {
        if (_usdc == address(0)) revert ZeroAddress();
        if (_admin == address(0)) revert ZeroAddress();
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
            // Pay referrer with proper return value decoding
            (bool success, bytes memory ret) = address(usdc).call(
                abi.encodeWithSelector(usdc.transfer.selector, referrer, referralCommission)
            );
            bool transferred = success && (ret.length == 0 || abi.decode(ret, (bool)));
            if (transferred) {
                emit ReferralPaid(agentDid, referrer, referralCommission);
            } else {
                emit ReferralFailed(agentDid, referrer, referralCommission);
            }
            // Verification still succeeds — referral is best-effort
        }
    }

    /// @notice Set the referral commission amount (admin only)
    /// @param _amount The new referral commission in USDC (6 decimals), 0 to disable
    function setReferralCommission(uint256 _amount) external {
        if (msg.sender != admin) revert NotAdmin();
        if (_amount > MAX_REFERRAL_COMMISSION) revert CommissionTooHigh();
        uint256 oldAmount = referralCommission;
        referralCommission = _amount;
        emit ReferralCommissionUpdated(oldAmount, _amount);
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

    /// @notice Start two-step admin transfer. New admin must call acceptAdmin().
    /// @param newAdmin The proposed new admin address
    function transferAdmin(address newAdmin) external {
        if (msg.sender != admin) revert NotAdmin();
        if (newAdmin == address(0)) revert ZeroAddress();
        pendingAdmin = newAdmin;
        emit AdminTransferStarted(admin, newAdmin);
    }

    /// @notice Accept admin transfer. Must be called by the pending admin.
    function acceptAdmin() external {
        if (msg.sender != pendingAdmin) revert NotPendingAdmin();
        address oldAdmin = admin;
        admin = msg.sender;
        pendingAdmin = address(0);
        emit AdminTransferred(oldAdmin, msg.sender);
    }

    // setAdmin removed — use transferAdmin() + acceptAdmin() for safe two-step transfer
}
