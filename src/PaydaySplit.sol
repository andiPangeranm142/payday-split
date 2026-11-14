// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { AbstractReactive } from "@reactive/src/base/AbstractReactive.sol";

/// @title PaydaySplit — the reactive brain of the Payday Split loop.
/// @notice Lives on Reactive Lasna. Subscribes to `DepositReceived` events
///         emitted by PaydayVault on Base Sepolia. When a deposit lands, this
///         contract computes the user's split from the rules embedded in the
///         event and requests a callback to SplitExecutor on Base Sepolia,
///         which performs the actual money movement.
///
///         This contract does real work: it parses the event, enforces the
///         minimum-deposit and pause policy, deduplicates deposits, computes
///         the split amounts, and only then asks for a callback. It is not a
///         passthrough — without it, nothing splits.
contract PaydaySplit is AbstractReactive {
    /// @notice keccak256("DepositReceived(address,uint256,uint256,uint16,uint16)")
    uint256 public immutable depositTopic0;

    uint256 public immutable originChainId;
    address public immutable originVault;

    address public owner;
    address public executor; // SplitExecutor on the destination chain.
    uint256 public destinationChainId;

    /// @notice Deposits below this are left alone (dust guard).
    uint256 public minDeposit = 0.001 ether;

    /// @notice Gas limit requested for the destination callback. Minimum
    ///         enforced by the network is 100,000; 1,000,000 leaves ample
    ///         room for the vault + savings + swap calls.
    uint64 public callbackGasLimit = 1_000_000;

    bool public paused;

    /// @notice depositId (vault-scoped) -> already handled. Guards against
    ///         duplicate delivery of the same log.
    mapping(uint256 => bool) public processed;

    /// @notice depositId -> origin tx hash, for auditability from the dashboard.
    mapping(uint256 => uint256) public originTxHash;

    uint256 public splitsRequested;
    uint256 public depositsSkipped;

    event SplitRequested(
        address indexed user,
        uint256 indexed depositId,
        uint256 amount,
        uint256 savingsAmount,
        uint256 stableAmount,
        uint256 originTxHash
    );
    event DepositSkipped(address indexed user, uint256 indexed depositId, uint256 amount, string reason);
    event ExecutorUpdated(address indexed executor, uint256 indexed destinationChainId);
    event MinDepositUpdated(uint256 minDeposit);
    event CallbackGasLimitUpdated(uint64 gasLimit);
    event PausedChanged(bool paused);

    error OnlyOwner();
    error ExecutorNotSet();

    constructor(
        uint256 originChainId_,
        address originVault_,
        uint256 depositTopic0_
    ) payable {
        owner = msg.sender;
        originChainId = originChainId_;
        originVault = originVault_;
        depositTopic0 = depositTopic0_;

        SYSTEM.subscribe(
            originChainId_,
            originVault_,
            depositTopic0_,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    /// @notice Wire the destination after deploying SplitExecutor (the deploy
    ///         order required by Reactive: reactive first, callback second).
    function setExecutor(address executor_, uint256 destinationChainId_) external onlyOwner {
        executor = executor_;
        destinationChainId = destinationChainId_;
        emit ExecutorUpdated(executor_, destinationChainId_);
    }

    function setMinDeposit(uint256 minDeposit_) external onlyOwner {
        minDeposit = minDeposit_;
        emit MinDepositUpdated(minDeposit_);
    }

    function setCallbackGasLimit(uint64 gasLimit_) external onlyOwner {
        callbackGasLimit = gasLimit_;
        emit CallbackGasLimitUpdated(gasLimit_);
    }

    function setPaused(bool paused_) external onlyOwner {
        paused = paused_;
        emit PausedChanged(paused_);
    }

    /// @notice Settles outstanding debt from this contract's own balance.
    function coverDebt() external {
        _coverDebt();
    }

    /// @inheritdoc IReactive
    function react(LogRecord memory log_) external onlySystem {
        // Route on topic0 first; ignore anything else silently (reverting as
        // a filter would still bill us for the gas).
        if (log_.topic0 != depositTopic0) return;
        if (log_.contractAddress != originVault) return;
        if (log_.chainId != originChainId) return;
        // DepositReceived(address indexed user, uint256 amount,
        //   uint256 depositId, uint16 savingsBps, uint16 stableBps) is a LOG2:
        //   topic1 = user, data = (amount, depositId, savingsBps, stableBps).
        if (log_.opCode != 2) return;

        address user = address(uint160(log_.topic1));
        (uint256 amount, uint256 depositId, uint16 savingsBps, uint16 stableBps) =
            abi.decode(log_.data, (uint256, uint256, uint16, uint16));

        if (paused) {
            emit DepositSkipped(user, depositId, amount, "paused");
            depositsSkipped++;
            return;
        }
        if (amount < minDeposit) {
            emit DepositSkipped(user, depositId, amount, "below-minimum");
            depositsSkipped++;
            return;
        }
        if (processed[depositId]) {
            emit DepositSkipped(user, depositId, amount, "already-processed");
            depositsSkipped++;
            return;
        }
        if (executor == address(0)) {
            emit DepositSkipped(user, depositId, amount, "executor-not-set");
            depositsSkipped++;
            return;
        }

        uint256 savingsAmount = (amount * savingsBps) / 10_000;
        uint256 stableAmount = (amount * stableBps) / 10_000;

        processed[depositId] = true;
        originTxHash[depositId] = log_.txHash;
        splitsRequested++;

        // First payload argument is reserved: the network overwrites it with
        // this contract's address so the executor can authenticate us.
        bytes memory payload = abi.encodeWithSignature(
            "executeSplit(address,address,uint256,uint256,uint256,uint256)",
            address(0),
            user,
            depositId,
            amount,
            savingsAmount,
            stableAmount
        );

        SYSTEM.requestCallbackV_1_0(
            ISystemContract.CallbackConfiguration_V_1_0({
                chainId: destinationChainId,
                recipient: executor,
                gasLimit: callbackGasLimit,
                payload: payload
            })
        );

        emit SplitRequested(user, depositId, amount, savingsAmount, stableAmount, log_.txHash);
    }
}
