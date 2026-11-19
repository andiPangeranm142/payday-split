// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @notice Minimal ERC-20 interface — just what the vault and swapper need.
///         Kept in-repo (no OpenZeppelin dependency) so any ERC-20 stablecoin
///         (pUSD, USDC, ...) can be wired in.
interface IERC20 {
    function transfer(address to_, uint256 amount_) external returns (bool);
    function approve(address spender_, uint256 amount_) external returns (bool);
    function balanceOf(address account_) external view returns (uint256);
}
