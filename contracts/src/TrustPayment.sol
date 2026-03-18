// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TrustPayment {
    IERC20 public immutable usdc;
    address public admin;

    uint256 public constant VERIFICATION_FEE = 10 * 1e6; // $10 USDC (6 decimals)
    uint256 public constant REPORT_FEE = 1 * 1e6; // $1 USDC (6 decimals)

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

    event Withdrawn(address indexed to, uint256 amount);

    error InsufficientPayment(uint256 required, uint256 provided);
    error TransferFailed();
    error NotAdmin();

    constructor(address _usdc, address _admin) {
        usdc = IERC20(_usdc);
        admin = _admin;
    }

    /// @notice Pay $10 USDC to verify an agent
    /// @param agentDid The DID of the agent to verify
    function payVerification(string calldata agentDid) external {
        bool ok = usdc.transferFrom(msg.sender, address(this), VERIFICATION_FEE);
        if (!ok) revert TransferFailed();

        emit VerificationPaid(agentDid, agentDid, msg.sender, VERIFICATION_FEE);
    }

    /// @notice Pay $1 USDC to file a report against an agent
    /// @param reportedDid The DID of the agent being reported
    /// @param reporterDid The DID of the reporting agent
    function payReport(string calldata reportedDid, string calldata reporterDid) external {
        bool ok = usdc.transferFrom(msg.sender, address(this), REPORT_FEE);
        if (!ok) revert TransferFailed();

        emit ReportPaid(reportedDid, reportedDid, reporterDid, reporterDid, msg.sender, REPORT_FEE);
    }

    /// @notice Admin withdraws collected fees
    /// @param to The address to send the funds to
    /// @param amount The amount to withdraw
    function withdraw(address to, uint256 amount) external {
        if (msg.sender != admin) revert NotAdmin();
        bool ok = usdc.transfer(to, amount);
        if (!ok) revert TransferFailed();
        emit Withdrawn(to, amount);
    }

    /// @notice Transfer admin role to a new address
    /// @param newAdmin The new admin address
    function setAdmin(address newAdmin) external {
        if (msg.sender != admin) revert NotAdmin();
        admin = newAdmin;
    }
}
