// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { AbstractCallback } from "@reactive/src/base/AbstractCallback.sol";
import { PaydayVault } from "./PaydayVault.sol";

/// @title SplitExecutor — the callback contract on Base Sepolia.
/// @notice Receives authenticated callbacks from the PaydaySplit reactive
///         contract (via the Base Sepolia callback proxy) and forwards the
///         computed split to PaydayVault. The two guards — `onlyServiceProvider`
///         (caller is the proxy) and `onlyCallbackSender` (origin is our
///         reactive contract) — mean nobody else can trigger a split.
///         Funded in Base Sepolia ETH: the proxy bills this contract for each
///         callback delivery.
contract SplitExecutor is AbstractCallback {
    PaydayVault public immutable vault;

    event SplitExecuted(
        address indexed user,
        uint256 indexed depositId,
        uint256 amount,
        uint256 savingsAmount,
        uint256 stableAmount
    );

    constructor(IPayable callbackProxy_, address callbackSender_, PaydayVault vault_)
        payable
        AbstractCallback(callbackProxy_, callbackSender_)
    {
        vault = vault_;
    }

    /// @notice Settles outstanding debt from this contract's own balance.
    function coverDebt() external {
        _coverDebt();
    }

    /// @notice Callback entry point. `reactive_` is injected by the network:
    ///         it is the address of the reactive contract that requested this
    ///         callback, and `onlyCallbackSender` verifies it.
    function executeSplit(
        address reactive_,
        address user_,
        uint256 depositId_,
        uint256 amount_,
        uint256 savingsAmount_,
        uint256 stableAmount_
    ) external onlyServiceProvider onlyCallbackSender(reactive_) {
        vault.executeSplit(depositId_, savingsAmount_, stableAmount_);
        // Event intentionally emitted after the call: only log splits that
        // actually executed.
        // forge-lint: disable-next-line(reentrancy-events)
        emit SplitExecuted(user_, depositId_, amount_, savingsAmount_, stableAmount_);
    }
}
