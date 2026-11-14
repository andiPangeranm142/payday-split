// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { PaydayUSD } from "./PaydayUSD.sol";

/// @notice Minimal swap interface so the demo swapper can be replaced by a
///         real DEX adapter (e.g. Uniswap) without touching the vault.
interface ISwapper {
    /// @notice Swaps the attached ETH for stablecoin, crediting `to_`.
    /// @return stableOut Amount of stablecoin minted/credited.
    function swap(address to_) external payable returns (uint256 stableOut);
}

/// @title MockSwapper — fixed-rate ETH -> pUSD swap for the testnet demo.
/// @notice HONEST LIMITATION: this is a demo swapper with a fixed, owner-set
///         rate (default 1 ETH = 2000 pUSD). It does not route through a DEX.
///         The vault talks to it only through `ISwapper`, so a production
///         deployment swaps in a real DEX adapter with no vault changes.
contract MockSwapper is ISwapper {
    PaydayUSD public immutable stable;
    address public immutable owner;

    /// @notice pUSD (18 decimals) paid per 1 ETH.
    uint256 public rate = 2000 ether;

    event Swapped(address indexed user, uint256 ethIn, uint256 stableOut, uint256 rate);
    event RateUpdated(uint256 oldRate, uint256 newRate);

    error OnlyOwner();
    error ZeroAmount();

    constructor(PaydayUSD stable_) {
        stable = stable_;
        owner = msg.sender;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    function setRate(uint256 rate_) external onlyOwner {
        emit RateUpdated(rate, rate_);
        rate = rate_;
    }

    /// @inheritdoc ISwapper
    function swap(address to_) external payable returns (uint256 stableOut) {
        if (msg.value == 0) revert ZeroAmount();
        stableOut = (msg.value * rate) / 1 ether;
        stable.mint(to_, stableOut);
        emit Swapped(to_, msg.value, stableOut, rate);
    }

    /// @notice Recover ETH held by the swapper (testnet housekeeping only).
    function sweep(address payable to_) external onlyOwner {
        to_.transfer(address(this).balance);
    }
}
