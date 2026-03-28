// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @title AgentWallet — Minimal smart contract wallet for AI Agents
/// @notice Each agent gets one wallet (deployed via CREATE2 through AgentWalletFactory).
///         Receives ETH/ERC-20 without deployment. ERC-721/1155 requires deployment.
///         ERC-4337 integration is deferred to a future beacon upgrade.
///
/// @dev Storage layout (DO NOT reorder or remove — upgrade safety):
///      Initializable._initialized — ERC-7201 namespaced slot (not sequential)
///      slot 0: address owner
///      slot 1: address signer
///      slot 2: address pendingOwner
///      slot 3: bool paused
///      slot 4: uint256 _reentrancyStatus
///      slots 5-52: __gap (48 slots reserved for future upgrades)
contract AgentWallet is Initializable, IERC721Receiver, IERC1155Receiver {
    /// @notice Owner wallet (recovery/admin).
    address public owner;

    /// @notice Optional operational EOA for on-chain transactions (secp256k1).
    ///         Independent from the Ed25519 signing key used off-chain.
    ///         address(0) means "no signer set".
    address public signer;

    /// @notice Pending owner for two-step ownership transfer.
    address public pendingOwner;

    /// @notice Whether the wallet is paused (emergency freeze).
    bool public paused;

    /// @dev Reentrancy guard status. 1 = not entered, 2 = entered.
    uint256 private _reentrancyStatus;

    /// @dev Reserved storage gap for future upgrades.
    uint256[48] private __gap;

    // ── Events ────────────────────────────────────────────────────────
    event Executed(address indexed to, uint256 value, bytes data);
    event SignerUpdated(address indexed oldSigner, address indexed newSigner);
    event OwnershipTransferStarted(address indexed currentOwner, address indexed newOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event Paused(address indexed account);
    event Unpaused(address indexed account);

    // ── Errors ────────────────────────────────────────────────────────
    error NotOwner();
    error NotAuthorized();
    error ExecutionFailed(bytes returnData);
    error LengthMismatch();
    error ZeroAddress();
    error WalletPaused();
    error ReentrancyGuardReentrantCall();
    error NotPendingOwner();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ── Modifiers ─────────────────────────────────────────────────────
    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyOwnerOrSigner() {
        if (msg.sender != owner && msg.sender != signer) revert NotAuthorized();
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert WalletPaused();
        _;
    }

    modifier nonReentrant() {
        if (_reentrancyStatus == 2) revert ReentrancyGuardReentrantCall();
        _reentrancyStatus = 2;
        _;
        _reentrancyStatus = 1;
    }

    /// @notice Initialize the wallet. Called once by AgentWalletFactory after CREATE2 deploy.
    /// @param _owner The owner wallet address (EOA that controls this agent)
    function initialize(address _owner) external initializer {
        if (_owner == address(0)) revert ZeroAddress();
        owner = _owner;
        _reentrancyStatus = 1;
    }

    // ── Execution ─────────────────────────────────────────────────────

    /// @notice Execute an arbitrary call. Owner or signer can call.
    /// @param to Target address
    /// @param value ETH value to send
    /// @param data Calldata
    /// @return result Return data from the call
    function execute(address to, uint256 value, bytes calldata data)
        external
        onlyOwnerOrSigner
        whenNotPaused
        nonReentrant
        returns (bytes memory result)
    {
        if (to == address(0)) revert ZeroAddress();
        bool success;
        (success, result) = to.call{value: value}(data);
        if (!success) revert ExecutionFailed(result);
        emit Executed(to, value, data);
    }

    /// @notice Execute a batch of calls atomically.
    /// @param targets Target addresses
    /// @param values ETH values
    /// @param calldatas Calldatas
    function executeBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas
    ) external onlyOwnerOrSigner whenNotPaused nonReentrant returns (bytes[] memory results) {
        if (targets.length != values.length || targets.length != calldatas.length) {
            revert LengthMismatch();
        }
        results = new bytes[](targets.length);
        for (uint256 i = 0; i < targets.length; i++) {
            if (targets[i] == address(0)) revert ZeroAddress();
            (bool success, bytes memory result) = targets[i].call{value: values[i]}(calldatas[i]);
            if (!success) revert ExecutionFailed(result);
            results[i] = result;
            emit Executed(targets[i], values[i], calldatas[i]);
        }
    }

    // ── Admin ─────────────────────────────────────────────────────────

    /// @notice Set or update the operational signer EOA.
    /// @param _signer The new signer address (address(0) to clear)
    function setSigner(address _signer) external onlyOwner {
        if (_signer == owner) revert NotAuthorized(); // signer must differ from owner
        address old = signer;
        signer = _signer;
        emit SignerUpdated(old, _signer);
    }

    /// @notice Start a two-step ownership transfer. New owner must call acceptOwnership().
    /// @param newOwner The proposed new owner address
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    /// @notice Accept ownership transfer. Must be called by the pending owner.
    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert NotPendingOwner();
        address oldOwner = owner;
        owner = msg.sender;
        pendingOwner = address(0);
        // Clear signer on ownership change for safety
        if (signer != address(0)) {
            address oldSigner = signer;
            signer = address(0);
            emit SignerUpdated(oldSigner, address(0));
        }
        emit OwnershipTransferred(oldOwner, msg.sender);
    }

    /// @notice Pause the wallet. Blocks all execute/executeBatch calls.
    function pause() external onlyOwner {
        paused = true;
        emit Paused(msg.sender);
    }

    /// @notice Unpause the wallet.
    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused(msg.sender);
    }

    // ── Receive ───────────────────────────────────────────────────────

    receive() external payable {}

    // ── ERC-721 / ERC-1155 Receiver ───────────────────────────────────

    function onERC721Received(address, address, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return IERC721Receiver.onERC721Received.selector;
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC721Receiver).interfaceId
            || interfaceId == type(IERC1155Receiver).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }
}
