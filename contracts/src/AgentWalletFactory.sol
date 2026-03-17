// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {IAgentWalletFactory} from "./interfaces/IAgentWalletFactory.sol";
import {AgentWallet} from "./AgentWallet.sol";

/// @title AgentWalletFactory — CREATE2 factory for deterministic agent wallet addresses
/// @notice Computes agent addresses before deployment. Deploys BeaconProxy wallets on demand.
///         All wallets share one UpgradeableBeacon → implementation can be upgraded without
///         changing any agent address or DID.
contract AgentWalletFactory is IAgentWalletFactory {
    /// @notice The UpgradeableBeacon that all wallet proxies point to.
    address public immutable beacon;

    /// @notice keccak256 of BeaconProxy creation code with our beacon address.
    ///         This NEVER changes (BeaconProxy init code doesn't include implementation address).
    bytes32 public immutable WALLET_BYTECODE_HASH;

    // ── Errors ────────────────────────────────────────────────────────
    error WalletAlreadyDeployed(address wallet);

    constructor(address _beacon) {
        beacon = _beacon;
        WALLET_BYTECODE_HASH = keccak256(_walletBytecode());
    }

    /// @notice Compute the deterministic address for a wallet without deploying.
    /// @param owner The owner wallet address
    /// @param nonce The agent nonce (0, 1, 2, ...)
    /// @return The CREATE2-derived agent wallet address (= agent DID address component)
    function computeAddress(address owner, uint256 nonce) external view returns (address) {
        bytes32 salt = _salt(owner, nonce);
        return Create2.computeAddress(salt, WALLET_BYTECODE_HASH);
    }

    /// @notice Deploy a wallet via CREATE2. Permissionless — anyone can call.
    ///         Security: initialize() has Initializable guard, and is called atomically.
    /// @param owner The owner wallet address
    /// @param nonce The agent nonce
    /// @return wallet The deployed wallet address
    function deploy(address owner, uint256 nonce) external returns (address wallet) {
        bytes32 salt = _salt(owner, nonce);
        address predicted = Create2.computeAddress(salt, WALLET_BYTECODE_HASH);
        if (predicted.code.length > 0) revert WalletAlreadyDeployed(predicted);

        // Deploy BeaconProxy via CREATE2
        wallet = Create2.deploy(0, salt, _walletBytecode());

        // Initialize atomically (no front-running window)
        AgentWallet(payable(wallet)).initialize(owner);

        emit WalletDeployed(wallet, owner, nonce);
    }

    // ── Internal ──────────────────────────────────────────────────────

    function _salt(address owner, uint256 nonce) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(owner, nonce));
    }

    function _walletBytecode() internal view returns (bytes memory) {
        // BeaconProxy(beacon, data) — empty data means no delegatecall during construction.
        // initialize() is called separately by deploy().
        return abi.encodePacked(type(BeaconProxy).creationCode, abi.encode(beacon, bytes("")));
    }
}
