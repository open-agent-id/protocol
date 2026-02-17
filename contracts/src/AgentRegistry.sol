// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

/// @title AgentRegistry - On-chain registry for AI Agent identities
/// @notice Stores DID hash → public key hash mappings for verifiable agent identities
/// @dev Minimal contract: register, revoke, rotate key, query
contract AgentRegistry {
    enum Status {
        None,
        Active,
        Revoked
    }

    struct AgentRecord {
        bytes32 pubKeyHash;
        address owner;
        bytes32 platform;
        Status status;
        uint64 registeredAt;
        uint64 updatedAt;
    }

    /// @notice DID hash → agent record
    mapping(bytes32 => AgentRecord) public agents;

    /// @notice Total number of registered agents
    uint256 public agentCount;

    // Events
    event AgentRegistered(
        bytes32 indexed didHash,
        bytes32 indexed pubKeyHash,
        bytes32 indexed platform,
        address owner
    );

    event AgentRevoked(bytes32 indexed didHash);

    event KeyRotated(
        bytes32 indexed didHash,
        bytes32 indexed oldPubKeyHash,
        bytes32 indexed newPubKeyHash
    );

    // Errors
    error AgentAlreadyExists();
    error AgentNotFound();
    error AgentNotActive();
    error NotOwner();
    error InvalidHash();

    /// @notice Register a new agent identity
    /// @param didHash keccak256 hash of the full DID string
    /// @param pubKeyHash keccak256 hash of the Ed25519 public key bytes
    /// @param platform keccak256 hash of the platform name (e.g., "tokli")
    function register(
        bytes32 didHash,
        bytes32 pubKeyHash,
        bytes32 platform
    ) external {
        if (didHash == bytes32(0) || pubKeyHash == bytes32(0)) revert InvalidHash();
        if (agents[didHash].status != Status.None) revert AgentAlreadyExists();

        agents[didHash] = AgentRecord({
            pubKeyHash: pubKeyHash,
            owner: msg.sender,
            platform: platform,
            status: Status.Active,
            registeredAt: uint64(block.timestamp),
            updatedAt: uint64(block.timestamp)
        });

        unchecked {
            agentCount++;
        }

        emit AgentRegistered(didHash, pubKeyHash, platform, msg.sender);
    }

    /// @notice Revoke an agent identity
    /// @param didHash keccak256 hash of the DID to revoke
    function revoke(bytes32 didHash) external {
        AgentRecord storage agent = agents[didHash];
        if (agent.status == Status.None) revert AgentNotFound();
        if (agent.status == Status.Revoked) revert AgentNotActive();
        if (agent.owner != msg.sender) revert NotOwner();

        agent.status = Status.Revoked;
        agent.updatedAt = uint64(block.timestamp);

        emit AgentRevoked(didHash);
    }

    /// @notice Rotate an agent's public key
    /// @param didHash keccak256 hash of the DID
    /// @param newPubKeyHash keccak256 hash of the new public key
    function rotateKey(bytes32 didHash, bytes32 newPubKeyHash) external {
        if (newPubKeyHash == bytes32(0)) revert InvalidHash();

        AgentRecord storage agent = agents[didHash];
        if (agent.status == Status.None) revert AgentNotFound();
        if (agent.status == Status.Revoked) revert AgentNotActive();
        if (agent.owner != msg.sender) revert NotOwner();

        bytes32 oldPubKeyHash = agent.pubKeyHash;
        agent.pubKeyHash = newPubKeyHash;
        agent.updatedAt = uint64(block.timestamp);

        emit KeyRotated(didHash, oldPubKeyHash, newPubKeyHash);
    }

    /// @notice Get agent record by DID hash
    /// @param didHash keccak256 hash of the DID
    /// @return record The agent record
    function getAgent(bytes32 didHash) external view returns (AgentRecord memory record) {
        record = agents[didHash];
        if (record.status == Status.None) revert AgentNotFound();
        return record;
    }

    /// @notice Check if an agent exists and is active
    /// @param didHash keccak256 hash of the DID
    /// @return True if agent is active
    function isActive(bytes32 didHash) external view returns (bool) {
        return agents[didHash].status == Status.Active;
    }
}
