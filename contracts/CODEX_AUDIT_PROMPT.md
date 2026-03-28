# Smart Contract Security Audit Request

You are a senior smart contract security auditor. Perform a comprehensive security audit of the following 4 Solidity contracts that form the Open Agent ID protocol — an on-chain identity system for AI agents deployed on Base L2 (Ethereum).

## System Architecture

```
┌─────────────────────┐     ┌──────────────────────────┐
│  AgentRegistry      │────▶│  AgentWalletFactory      │
│  (identity registry)│     │  (CREATE2 deployer)       │
└─────────────────────┘     └──────────┬───────────────┘
                                       │ deploys
                                       ▼
                            ┌──────────────────────────┐
                            │  AgentWallet             │
                            │  (BeaconProxy wallet)    │
                            │  holds ETH/ERC20/NFTs    │
                            └──────────────────────────┘

┌─────────────────────┐
│  TrustPayment       │  USDC fee collection ($10 verify, $1 report)
│  (payment contract) │  referral commission system
└─────────────────────┘
```

- **Chain:** Base L2 (Ethereum), Solidity ^0.8.24
- **Dependencies:** OpenZeppelin Contracts (Initializable, BeaconProxy, UpgradeableBeacon, Create2, IERC20, IERC721Receiver, IERC1155Receiver)
- **Token:** USDC (6 decimals, Circle's upgradeable proxy with blacklist capability)
- **Key roles:** Admin (governance), Relayer (hot wallet for batch registrations), Owner (per-wallet EOA), Signer (optional operational key per wallet)

## What Was Already Fixed (from a previous Claude audit)

These issues were already identified and fixed. Please verify the fixes are correct and complete:

1. **AgentWallet:** Added `nonReentrant` modifier on execute/executeBatch
2. **AgentWallet:** Added two-step `transferOwnership` / `acceptOwnership`
3. **AgentWallet:** Added `pause()` / `unpause()` emergency freeze
4. **AgentWallet:** Added `__gap[48]` storage gap for upgrade safety
5. **AgentWallet:** `setSigner` now prevents setting signer == owner
6. **AgentWallet:** `execute` now rejects `address(0)` target
7. **TrustPayment:** Constructor now validates `_usdc` and `_admin` != address(0)
8. **TrustPayment:** Referral payment now decodes ERC20 return value properly
9. **TrustPayment:** Added `ReferralFailed` event for silent failures
10. **TrustPayment:** Referral commission capped at 50% (`MAX_REFERRAL_COMMISSION`)
11. **TrustPayment:** Added `ReferralCommissionUpdated` event
12. **TrustPayment:** Two-step `transferAdmin` / `acceptAdmin`
13. **AgentRegistry:** Constructor validates `_factory` and `_relayer` != address(0)
14. **AgentRegistry:** Constructor emits initial events
15. **AgentRegistry:** Two-step `transferAdmin` / `acceptAdmin`
16. **AgentRegistry:** Added `pause()` / `unpause()` for emergency
17. **AgentRegistry:** `rotateKey` rejects same hash
18. **AgentWalletFactory:** Constructor validates `_beacon` != address(0) and has code
19. **AgentWalletFactory:** `_salt` uses `abi.encode` instead of `abi.encodePacked`

## Audit Requirements

### 1. Verify Previous Fixes
For each of the 19 fixes above, verify:
- Is the fix correctly implemented?
- Does it introduce any new vulnerabilities?
- Are there edge cases the fix misses?

### 2. Find NEW Issues
Look for anything the previous audit missed. Pay special attention to:

**Cross-contract interactions:**
- Registry → Factory → Wallet deployment chain
- Can a malicious factory be used to register invalid agents?
- Beacon upgrade impact on all wallets simultaneously

**Economic attacks:**
- Flash loan attack vectors on TrustPayment
- MEV/front-running on any function
- Referral farming/gaming
- Fee manipulation scenarios

**Proxy/upgrade safety:**
- Storage layout collision risk in AgentWallet (BeaconProxy)
- What happens if beacon is upgraded to a malicious implementation?
- Can `_reentrancyStatus` be manipulated via storage collision?

**ERC-20 edge cases (USDC-specific):**
- USDC blacklisting of the TrustPayment contract
- USDC proxy upgrade changing behavior
- approval front-running

**Access control:**
- Can the signer escalate to owner privileges?
- Can a compromised relayer do permanent damage?
- What's the worst case if admin key is compromised?

**Denial of Service:**
- Can anyone permanently brick the system?
- Gas griefing vectors
- Storage bloat attacks

### 3. Output Format

For each finding, use:
```
[SEVERITY] Title
- Description: What the issue is
- Impact: What could go wrong
- Location: File and line numbers
- Proof of Concept: How to exploit
- Recommendation: How to fix
```

Severity: CRITICAL / HIGH / MEDIUM / LOW / INFO

### 4. Summary
Provide a final summary table and overall assessment of mainnet readiness.

---

## CONTRACT SOURCE CODE

### File 1: AgentRegistry.sol (273 lines)

```solidity
// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {IAgentWalletFactory} from "./interfaces/IAgentWalletFactory.sol";

contract AgentRegistry {
    enum Status { None, Active, Revoked }

    struct AgentRecord {
        bytes32 pubKeyHash;
        address owner;
        Status status;
        uint64 registeredAt;
        uint64 updatedAt;
    }

    IAgentWalletFactory public immutable factory;
    address public relayer;
    address public admin;
    address public pendingAdmin;
    bool public paused;
    mapping(address => AgentRecord) public agents;
    uint256 public agentCount;

    event AgentRegistered(address indexed agentAddr, bytes32 indexed pubKeyHash, address indexed owner);
    event AgentSkipped(address indexed agentAddr, address indexed owner, uint256 nonce);
    event AgentRevoked(address indexed agentAddr);
    event KeyRotated(address indexed agentAddr, bytes32 indexed oldPubKeyHash, bytes32 indexed newPubKeyHash);
    event RelayerUpdated(address indexed oldRelayer, address indexed newRelayer);
    event AdminTransferred(address indexed oldAdmin, address indexed newAdmin);
    event AdminTransferStarted(address indexed currentAdmin, address indexed newAdmin);
    event Paused(address indexed account);
    event Unpaused(address indexed account);

    error AgentAlreadyExists();
    error AgentNotFound();
    error AgentNotActive();
    error NotOwner();
    error NotRelayer();
    error NotAdmin();
    error NotPendingAdmin();
    error InvalidHash();
    error SameHash();
    error LengthMismatch();
    error ZeroAddress();
    error BatchTooLarge();
    error RegistryPaused();

    uint256 public constant MAX_BATCH_SIZE = 100;

    modifier onlyRelayer() { if (msg.sender != relayer) revert NotRelayer(); _; }
    modifier onlyAdmin() { if (msg.sender != admin) revert NotAdmin(); _; }
    modifier whenNotPaused() { if (paused) revert RegistryPaused(); _; }

    constructor(address _factory, address _relayer) {
        if (_factory == address(0)) revert ZeroAddress();
        if (_relayer == address(0)) revert ZeroAddress();
        factory = IAgentWalletFactory(_factory);
        relayer = _relayer;
        admin = msg.sender;
        emit RelayerUpdated(address(0), _relayer);
        emit AdminTransferred(address(0), msg.sender);
    }

    function register(bytes32 pubKeyHash, address owner, uint256 nonce) external onlyRelayer whenNotPaused {
        if (pubKeyHash == bytes32(0)) revert InvalidHash();
        if (owner == address(0)) revert ZeroAddress();
        address agentAddr = factory.computeAddress(owner, nonce);
        if (agents[agentAddr].status != Status.None) revert AgentAlreadyExists();
        agents[agentAddr] = AgentRecord({ pubKeyHash: pubKeyHash, owner: owner, status: Status.Active, registeredAt: uint64(block.timestamp), updatedAt: uint64(block.timestamp) });
        unchecked { agentCount++; }
        emit AgentRegistered(agentAddr, pubKeyHash, owner);
    }

    function registerBatch(bytes32[] calldata pubKeyHashes, address[] calldata owners, uint256[] calldata nonces) external onlyRelayer whenNotPaused {
        uint256 len = pubKeyHashes.length;
        if (len != owners.length || len != nonces.length) revert LengthMismatch();
        if (len > MAX_BATCH_SIZE) revert BatchTooLarge();
        for (uint256 i = 0; i < len; i++) {
            if (pubKeyHashes[i] == bytes32(0)) continue;
            if (owners[i] == address(0)) continue;
            address agentAddr = factory.computeAddress(owners[i], nonces[i]);
            if (agents[agentAddr].status != Status.None) { emit AgentSkipped(agentAddr, owners[i], nonces[i]); continue; }
            agents[agentAddr] = AgentRecord({ pubKeyHash: pubKeyHashes[i], owner: owners[i], status: Status.Active, registeredAt: uint64(block.timestamp), updatedAt: uint64(block.timestamp) });
            unchecked { agentCount++; }
            emit AgentRegistered(agentAddr, pubKeyHashes[i], owners[i]);
        }
    }

    function revoke(address agentAddr) external {
        AgentRecord storage agent = agents[agentAddr];
        if (agent.status == Status.None) revert AgentNotFound();
        if (agent.status == Status.Revoked) revert AgentNotActive();
        if (agent.owner != msg.sender) revert NotOwner();
        agent.status = Status.Revoked;
        agent.updatedAt = uint64(block.timestamp);
        emit AgentRevoked(agentAddr);
    }

    function rotateKey(address agentAddr, bytes32 newPubKeyHash) external {
        if (newPubKeyHash == bytes32(0)) revert InvalidHash();
        AgentRecord storage agent = agents[agentAddr];
        if (agent.status == Status.None) revert AgentNotFound();
        if (agent.status == Status.Revoked) revert AgentNotActive();
        if (agent.owner != msg.sender) revert NotOwner();
        bytes32 oldPubKeyHash = agent.pubKeyHash;
        if (newPubKeyHash == oldPubKeyHash) revert SameHash();
        agent.pubKeyHash = newPubKeyHash;
        agent.updatedAt = uint64(block.timestamp);
        emit KeyRotated(agentAddr, oldPubKeyHash, newPubKeyHash);
    }

    function getAgent(address agentAddr) external view returns (AgentRecord memory) {
        AgentRecord memory agent = agents[agentAddr];
        if (agent.status == Status.None) revert AgentNotFound();
        return agent;
    }

    function isActive(address agentAddr) external view returns (bool) { return agents[agentAddr].status == Status.Active; }

    function setRelayer(address newRelayer) external onlyAdmin {
        if (newRelayer == address(0)) revert ZeroAddress();
        address old = relayer;
        relayer = newRelayer;
        emit RelayerUpdated(old, newRelayer);
    }

    function transferAdmin(address newAdmin) external onlyAdmin {
        if (newAdmin == address(0)) revert ZeroAddress();
        pendingAdmin = newAdmin;
        emit AdminTransferStarted(admin, newAdmin);
    }

    function acceptAdmin() external {
        if (msg.sender != pendingAdmin) revert NotPendingAdmin();
        address old = admin;
        admin = msg.sender;
        pendingAdmin = address(0);
        emit AdminTransferred(old, msg.sender);
    }

    function pause() external onlyAdmin { paused = true; emit Paused(msg.sender); }
    function unpause() external onlyAdmin { paused = false; emit Unpaused(msg.sender); }
}
```

### File 2: AgentWallet.sol (225 lines)

```solidity
// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

contract AgentWallet is Initializable, IERC721Receiver, IERC1155Receiver {
    address public owner;
    address public signer;
    address public pendingOwner;
    bool public paused;
    uint256 private _reentrancyStatus;
    uint256[48] private __gap;

    event Executed(address indexed to, uint256 value, bytes data);
    event SignerUpdated(address indexed oldSigner, address indexed newSigner);
    event OwnershipTransferStarted(address indexed currentOwner, address indexed newOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event Paused(address indexed account);
    event Unpaused(address indexed account);

    error NotOwner();
    error NotAuthorized();
    error ExecutionFailed(bytes returnData);
    error LengthMismatch();
    error ZeroAddress();
    error WalletPaused();
    error ReentrancyGuardReentrantCall();
    error NotPendingOwner();

    constructor() { _disableInitializers(); }

    modifier onlyOwner() { if (msg.sender != owner) revert NotOwner(); _; }
    modifier onlyOwnerOrSigner() { if (msg.sender != owner && msg.sender != signer) revert NotAuthorized(); _; }
    modifier whenNotPaused() { if (paused) revert WalletPaused(); _; }
    modifier nonReentrant() {
        if (_reentrancyStatus == 2) revert ReentrancyGuardReentrantCall();
        _reentrancyStatus = 2; _; _reentrancyStatus = 1;
    }

    function initialize(address _owner) external initializer {
        if (_owner == address(0)) revert ZeroAddress();
        owner = _owner;
        _reentrancyStatus = 1;
    }

    function execute(address to, uint256 value, bytes calldata data) external onlyOwnerOrSigner whenNotPaused nonReentrant returns (bytes memory result) {
        if (to == address(0)) revert ZeroAddress();
        bool success;
        (success, result) = to.call{value: value}(data);
        if (!success) revert ExecutionFailed(result);
        emit Executed(to, value, data);
    }

    function executeBatch(address[] calldata targets, uint256[] calldata values, bytes[] calldata calldatas) external onlyOwnerOrSigner whenNotPaused nonReentrant returns (bytes[] memory results) {
        if (targets.length != values.length || targets.length != calldatas.length) revert LengthMismatch();
        results = new bytes[](targets.length);
        for (uint256 i = 0; i < targets.length; i++) {
            if (targets[i] == address(0)) revert ZeroAddress();
            (bool success, bytes memory result) = targets[i].call{value: values[i]}(calldatas[i]);
            if (!success) revert ExecutionFailed(result);
            results[i] = result;
            emit Executed(targets[i], values[i], calldatas[i]);
        }
    }

    function setSigner(address _signer) external onlyOwner {
        if (_signer == owner) revert NotAuthorized();
        address old = signer;
        signer = _signer;
        emit SignerUpdated(old, _signer);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert NotPendingOwner();
        address oldOwner = owner;
        owner = msg.sender;
        pendingOwner = address(0);
        if (signer != address(0)) {
            address oldSigner = signer;
            signer = address(0);
            emit SignerUpdated(oldSigner, address(0));
        }
        emit OwnershipTransferred(oldOwner, msg.sender);
    }

    function pause() external onlyOwner { paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner { paused = false; emit Unpaused(msg.sender); }

    receive() external payable {}

    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) { return IERC721Receiver.onERC721Received.selector; }
    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure override returns (bytes4) { return IERC1155Receiver.onERC1155Received.selector; }
    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata) external pure override returns (bytes4) { return IERC1155Receiver.onERC1155BatchReceived.selector; }
    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC721Receiver).interfaceId || interfaceId == type(IERC1155Receiver).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}
```

### File 3: AgentWalletFactory.sol (71 lines)

```solidity
// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {IAgentWalletFactory} from "./interfaces/IAgentWalletFactory.sol";
import {AgentWallet} from "./AgentWallet.sol";

contract AgentWalletFactory is IAgentWalletFactory {
    address public immutable beacon;
    bytes32 public immutable WALLET_BYTECODE_HASH;

    error WalletAlreadyDeployed(address wallet);
    error ZeroAddress();

    constructor(address _beacon) {
        if (_beacon == address(0)) revert ZeroAddress();
        if (_beacon.code.length == 0) revert ZeroAddress();
        beacon = _beacon;
        WALLET_BYTECODE_HASH = keccak256(_walletBytecode());
    }

    function computeAddress(address owner, uint256 nonce) external view returns (address) {
        return Create2.computeAddress(_salt(owner, nonce), WALLET_BYTECODE_HASH);
    }

    function deploy(address owner, uint256 nonce) external returns (address wallet) {
        bytes32 salt = _salt(owner, nonce);
        address predicted = Create2.computeAddress(salt, WALLET_BYTECODE_HASH);
        if (predicted.code.length > 0) revert WalletAlreadyDeployed(predicted);
        wallet = Create2.deploy(0, salt, _walletBytecode());
        AgentWallet(payable(wallet)).initialize(owner);
        emit WalletDeployed(wallet, owner, nonce);
    }

    function _salt(address owner, uint256 nonce) internal pure returns (bytes32) {
        return keccak256(abi.encode(owner, nonce));
    }

    function _walletBytecode() internal view returns (bytes memory) {
        return abi.encodePacked(type(BeaconProxy).creationCode, abi.encode(beacon, bytes("")));
    }
}
```

### File 4: TrustPayment.sol (157 lines)

```solidity
// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TrustPayment {
    IERC20 public immutable usdc;
    address public admin;
    address public pendingAdmin;

    uint256 public constant VERIFICATION_FEE = 10 * 1e6;
    uint256 public constant REPORT_FEE = 1 * 1e6;
    uint256 public constant MAX_REFERRAL_COMMISSION = 5 * 1e6;
    uint256 public referralCommission = 1 * 1e6;

    event VerificationPaid(string indexed agentDidHash, string agentDid, address indexed payer, uint256 amount);
    event ReportPaid(string indexed reportedDidHash, string reportedDid, string indexed reporterDidHash, string reporterDid, address indexed payer, uint256 amount);
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

    function payVerification(string calldata agentDid) external {
        if (bytes(agentDid).length == 0) revert EmptyDid();
        bool ok = usdc.transferFrom(msg.sender, address(this), VERIFICATION_FEE);
        if (!ok) revert TransferFailed();
        emit VerificationPaid(agentDid, agentDid, msg.sender, VERIFICATION_FEE);
    }

    function payVerificationWithReferral(string calldata agentDid, address referrer) external {
        if (bytes(agentDid).length == 0) revert EmptyDid();
        if (referrer == msg.sender) revert SelfReferral();
        bool ok = usdc.transferFrom(msg.sender, address(this), VERIFICATION_FEE);
        if (!ok) revert TransferFailed();
        emit VerificationPaid(agentDid, agentDid, msg.sender, VERIFICATION_FEE);
        if (referrer != address(0) && referralCommission > 0) {
            if (usdc.balanceOf(address(this)) < referralCommission) revert InsufficientBalance();
            (bool success, bytes memory ret) = address(usdc).call(
                abi.encodeWithSelector(usdc.transfer.selector, referrer, referralCommission)
            );
            bool transferred = success && (ret.length == 0 || abi.decode(ret, (bool)));
            if (transferred) { emit ReferralPaid(agentDid, referrer, referralCommission); }
            else { emit ReferralFailed(agentDid, referrer, referralCommission); }
        }
    }

    function setReferralCommission(uint256 _amount) external {
        if (msg.sender != admin) revert NotAdmin();
        if (_amount > MAX_REFERRAL_COMMISSION) revert CommissionTooHigh();
        uint256 oldAmount = referralCommission;
        referralCommission = _amount;
        emit ReferralCommissionUpdated(oldAmount, _amount);
    }

    function payReport(string calldata reportedDid, string calldata reporterDid) external {
        if (bytes(reportedDid).length == 0) revert EmptyDid();
        if (bytes(reporterDid).length == 0) revert EmptyDid();
        bool ok = usdc.transferFrom(msg.sender, address(this), REPORT_FEE);
        if (!ok) revert TransferFailed();
        emit ReportPaid(reportedDid, reportedDid, reporterDid, reporterDid, msg.sender, REPORT_FEE);
    }

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

    function transferAdmin(address newAdmin) external {
        if (msg.sender != admin) revert NotAdmin();
        if (newAdmin == address(0)) revert ZeroAddress();
        pendingAdmin = newAdmin;
        emit AdminTransferStarted(admin, newAdmin);
    }

    function acceptAdmin() external {
        if (msg.sender != pendingAdmin) revert NotPendingAdmin();
        address oldAdmin = admin;
        admin = msg.sender;
        pendingAdmin = address(0);
        emit AdminTransferred(oldAdmin, msg.sender);
    }

    function setAdmin(address newAdmin) external {
        if (msg.sender != admin) revert NotAdmin();
        if (newAdmin == address(0)) revert ZeroAddress();
        emit AdminTransferred(admin, newAdmin);
        admin = newAdmin;
    }
}
```

### File 5: IAgentWalletFactory.sol (interface)

```solidity
// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

interface IAgentWalletFactory {
    event WalletDeployed(address indexed wallet, address indexed owner, uint256 nonce);
    function beacon() external view returns (address);
    function WALLET_BYTECODE_HASH() external view returns (bytes32);
    function computeAddress(address owner, uint256 nonce) external view returns (address);
    function deploy(address owner, uint256 nonce) external returns (address wallet);
}
```
