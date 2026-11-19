// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IERC20 } from "./IERC20.sol";

/// @title Payday USD — demo stablecoin for the Payday Split testnet demo.
/// @notice A minimal ERC-20 with a single minter (the swapper). Testnet only,
///         no economic value. Exists so the "swap to stablecoin" leg of a split
///         produces a real token balance a user can see and withdraw.
contract PaydayUSD is IERC20 {
    string public constant name = "Payday USD";
    string public constant symbol = "pUSD";
    uint8 public constant decimals = 18;

    uint256 public totalSupply;
    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    address public immutable minter;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    error OnlyMinter();
    error InsufficientBalance();
    error InsufficientAllowance();

    constructor(address minter_) {
        minter = minter_;
    }

    function mint(address to_, uint256 amount_) external {
        if (msg.sender != minter) revert OnlyMinter();
        totalSupply += amount_;
        balanceOf[to_] += amount_;
        emit Transfer(address(0), to_, amount_);
    }

    function transfer(address to_, uint256 amount_) external override returns (bool) {
        _transfer(msg.sender, to_, amount_);
        return true;
    }

    function approve(address spender_, uint256 amount_) external override returns (bool) {
        allowance[msg.sender][spender_] = amount_;
        emit Approval(msg.sender, spender_, amount_);
        return true;
    }

    function transferFrom(address from_, address to_, uint256 amount_) external returns (bool) {
        uint256 allowed = allowance[from_][msg.sender];
        if (allowed < amount_) revert InsufficientAllowance();
        if (allowed != type(uint256).max) {
            allowance[from_][msg.sender] = allowed - amount_;
        }
        _transfer(from_, to_, amount_);
        return true;
    }

    function _transfer(address from_, address to_, uint256 amount_) internal {
        if (balanceOf[from_] < amount_) revert InsufficientBalance();
        balanceOf[from_] -= amount_;
        balanceOf[to_] += amount_;
        emit Transfer(from_, to_, amount_);
    }
}
