// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

interface IAgentWalletFactory {
    event WalletDeployed(address indexed wallet, address indexed owner, uint256 nonce);

    function beacon() external view returns (address);
    function WALLET_BYTECODE_HASH() external view returns (bytes32);
    function computeAddress(address owner, uint256 nonce) external view returns (address);
    function deploy(address owner, uint256 nonce) external returns (address wallet);
}
