// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {IAgentWalletFactory} from "./interfaces/IAgentWalletFactory.sol";

/// @title AgentRegistry V2 — Wallet-native on-chain registry for AI Agent identities
/// @notice Stores agent address → record mappings. Agent addresses are deterministically
///         derived via CREATE2 (factory.computeAddress). Registry server batches registrations
///         to save gas (30-50% vs single-tx).
/// @dev Key changes from V1:
///      - Keyed by agent address (CREATE2-derived), not DID hash
///      - Relayer model: registry server submits on behalf of users
///      - Batch registration for gas efficiency
///      - Factory integration for address verification
contract AgentRegistry {
    enum Status {
        None,
        Active,
        Revoked
    }

    struct AgentRecord {
        bytes32 pubKeyHash; // keccak256(Ed25519 public key bytes)
        address owner; // owner wallet (EOA)
        Status status;
        uint64 registeredAt;
        uint64 updatedAt;
    }

    /// @notice The factory used to verify CREATE2 addresses.
    IAgentWalletFactory public immutable factory;

    /// @notice The relayer address (registry server's hot wallet).
    address public relayer;

    /// @notice Admin that can update the relayer. Set to deployer initially.
    address public admin;

    /// @notice Agent address → on-chain record.
    mapping(address => AgentRecord) public agents;

    /// @notice Total registered agents (including revoked).
    uint256 public agentCount;

    // ── Events ────────────────────────────────────────────────────────
    event AgentRegistered(
        address indexed agentAddr, bytes32 indexed pubKeyHash, address indexed owner
    );
    event AgentSkipped(address indexed agentAddr, address indexed owner, uint256 nonce);
    event AgentRevoked(address indexed agentAddr);
    event KeyRotated(
        address indexed agentAddr, bytes32 indexed oldPubKeyHash, bytes32 indexed newPubKeyHash
    );
    event RelayerUpdated(address indexed oldRelayer, address indexed newRelayer);
    event AdminTransferred(address indexed oldAdmin, address indexed newAdmin);

    // ── Errors ────────────────────────────────────────────────────────
    error AgentAlreadyExists();
    error AgentNotFound();
    error AgentNotActive();
    error NotOwner();
    error NotRelayer();
    error NotAdmin();
    error InvalidHash();
    error LengthMismatch();
    error ZeroAddress();
    error BatchTooLarge();

    uint256 public constant MAX_BATCH_SIZE = 100;

    // ── Modifiers ─────────────────────────────────────────────────────
    modifier onlyRelayer() {
        if (msg.sender != relayer) revert NotRelayer();
        _;
    }

    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAdmin();
        _;
    }

    // ── Constructor ───────────────────────────────────────────────────

    /// @param _factory The AgentWalletFactory address (for computeAddress verification)
    /// @param _relayer The initial relayer (registry server's hot wallet)
    constructor(address _factory, address _relayer) {
        factory = IAgentWalletFactory(_factory);
        relayer = _relayer;
        admin = msg.sender;
    }

    // ── Registration (Relayer only) ───────────────────────────────────

    /// @notice Register a single agent. Contract computes the address via factory — no trust
    ///         in externally supplied addresses.
    /// @param pubKeyHash keccak256 of the Ed25519 public key
    /// @param owner The owner wallet
    /// @param nonce The agent nonce (from wallet_nonces table)
    function register(bytes32 pubKeyHash, address owner, uint256 nonce) external onlyRelayer {
        if (pubKeyHash == bytes32(0)) revert InvalidHash();
        if (owner == address(0)) revert ZeroAddress();

        address agentAddr = factory.computeAddress(owner, nonce);
        if (agents[agentAddr].status != Status.None) revert AgentAlreadyExists();

        agents[agentAddr] = AgentRecord({
            pubKeyHash: pubKeyHash,
            owner: owner,
            status: Status.Active,
            registeredAt: uint64(block.timestamp),
            updatedAt: uint64(block.timestamp)
        });

        unchecked {
            agentCount++;
        }

        emit AgentRegistered(agentAddr, pubKeyHash, owner);
    }

    /// @notice Batch register agents. Skips duplicates instead of reverting (idempotent).
    ///         Saves 30-50% gas vs individual register() calls.
    /// @param pubKeyHashes Array of keccak256(Ed25519 public key)
    /// @param owners Array of owner wallets
    /// @param nonces Array of agent nonces
    function registerBatch(
        bytes32[] calldata pubKeyHashes,
        address[] calldata owners,
        uint256[] calldata nonces
    ) external onlyRelayer {
        uint256 len = pubKeyHashes.length;
        if (len != owners.length || len != nonces.length) revert LengthMismatch();
        if (len > MAX_BATCH_SIZE) revert BatchTooLarge();

        for (uint256 i = 0; i < len; i++) {
            if (pubKeyHashes[i] == bytes32(0)) continue; // skip invalid
            if (owners[i] == address(0)) continue; // skip zero-address owner

            address agentAddr = factory.computeAddress(owners[i], nonces[i]);

            if (agents[agentAddr].status != Status.None) {
                emit AgentSkipped(agentAddr, owners[i], nonces[i]);
                continue;
            }

            agents[agentAddr] = AgentRecord({
                pubKeyHash: pubKeyHashes[i],
                owner: owners[i],
                status: Status.Active,
                registeredAt: uint64(block.timestamp),
                updatedAt: uint64(block.timestamp)
            });

            unchecked {
                agentCount++;
            }

            emit AgentRegistered(agentAddr, pubKeyHashes[i], owners[i]);
        }
    }

    // ── Owner Operations ──────────────────────────────────────────────

    /// @notice Revoke an agent. Only the owner can call.
    /// @param agentAddr The agent's CREATE2 address
    function revoke(address agentAddr) external {
        AgentRecord storage agent = agents[agentAddr];
        if (agent.status == Status.None) revert AgentNotFound();
        if (agent.status == Status.Revoked) revert AgentNotActive();
        if (agent.owner != msg.sender) revert NotOwner();

        agent.status = Status.Revoked;
        agent.updatedAt = uint64(block.timestamp);

        emit AgentRevoked(agentAddr);
    }

    /// @notice Rotate an agent's Ed25519 public key. Only the owner can call.
    /// @param agentAddr The agent's CREATE2 address
    /// @param newPubKeyHash keccak256 of the new Ed25519 public key
    function rotateKey(address agentAddr, bytes32 newPubKeyHash) external {
        if (newPubKeyHash == bytes32(0)) revert InvalidHash();

        AgentRecord storage agent = agents[agentAddr];
        if (agent.status == Status.None) revert AgentNotFound();
        if (agent.status == Status.Revoked) revert AgentNotActive();
        if (agent.owner != msg.sender) revert NotOwner();

        bytes32 oldPubKeyHash = agent.pubKeyHash;
        agent.pubKeyHash = newPubKeyHash;
        agent.updatedAt = uint64(block.timestamp);

        emit KeyRotated(agentAddr, oldPubKeyHash, newPubKeyHash);
    }

    // ── Queries ───────────────────────────────────────────────────────

    /// @notice Get agent record. Reverts if not found.
    function getAgent(address agentAddr) external view returns (AgentRecord memory) {
        AgentRecord memory agent = agents[agentAddr];
        if (agent.status == Status.None) revert AgentNotFound();
        return agent;
    }

    /// @notice Check if an agent is active.
    function isActive(address agentAddr) external view returns (bool) {
        return agents[agentAddr].status == Status.Active;
    }

    // ── Admin ─────────────────────────────────────────────────────────

    /// @notice Update the relayer address.
    function setRelayer(address newRelayer) external onlyAdmin {
        if (newRelayer == address(0)) revert ZeroAddress();
        address old = relayer;
        relayer = newRelayer;
        emit RelayerUpdated(old, newRelayer);
    }

    /// @notice Transfer admin role.
    function transferAdmin(address newAdmin) external onlyAdmin {
        if (newAdmin == address(0)) revert ZeroAddress();
        address old = admin;
        admin = newAdmin;
        emit AdminTransferred(old, newAdmin);
    }
}
