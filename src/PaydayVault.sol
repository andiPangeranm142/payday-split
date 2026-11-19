// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { ISwapper } from "./MockSwapper.sol";
import { IERC20 } from "./IERC20.sol";
import { SavingsVault } from "./SavingsVault.sol";

/// @title PaydayVault — the origin contract of the Payday Split loop.
/// @notice Users deposit ETH here. Every deposit emits `DepositReceived`, which
///         the reactive contract on Reactive Lasna subscribes to. When the
///         reactive contract sees the deposit it requests a callback, and the
///         callback (via SplitExecutor) calls `executeSplit` here to move the
///         money: savings -> SavingsVault (timelocked), stable slice -> swapper
///         (stablecoin credited to the user), remainder stays as spendable balance.
///         Nobody — not even the owner — can move a user's funds except through
///         this split path or the user's own withdrawal.
contract PaydayVault {
    struct Rules {
        uint16 savingsBps; // basis points of each deposit routed to savings
        uint16 stableBps; // basis points of each deposit swapped to stablecoin
    }

    struct Deposit {
        address user;
        uint256 amount;
        bool split;
    }

    uint16 public constant MAX_BPS = 10_000;

    /// @notice Emitted on every deposit. The reactive contract subscribes to
    ///         this exact event (topic0) on this contract. The user's rules are
    ///         embedded so the reactive side is stateless w.r.t. rules.
    event DepositReceived(
        address indexed user,
        uint256 amount,
        uint256 depositId,
        uint16 savingsBps,
        uint16 stableBps
    );
    event SplitExecuted(
        address indexed user,
        uint256 indexed depositId,
        uint256 savingsAmount,
        uint256 stableAmount,
        uint256 stableReceived,
        uint256 remainder
    );
    event RulesUpdated(address indexed user, uint16 savingsBps, uint16 stableBps);
    event Withdrawn(address indexed user, uint256 amount);
    event StableWithdrawn(address indexed user, uint256 amount);

    error OnlyExecutor();
    error OnlyOwner();
    error ZeroAmount();
    error RulesExceed100Percent();
    error DepositAlreadySplit();
    error UnknownDeposit();
    error InsufficientBalance();
    error SplitAmountsMismatch();

    address public immutable owner;
    address public executor; // SplitExecutor — the only caller of executeSplit.

    ISwapper public immutable swapper;
    IERC20 public immutable stable;
    SavingsVault public immutable savingsVault;

    uint256 public nextDepositId;
    mapping(uint256 => Deposit) public deposits;
    mapping(address => Rules) public rulesOf;
    mapping(address => bool) public rulesSet;
    mapping(address => uint256) public availableOf; // spendable ETH balance
    mapping(address => uint256) public stableOf; // stablecoin balance held for user

    constructor(ISwapper swapper_, IERC20 stable_, SavingsVault savingsVault_) {
        owner = msg.sender;
        swapper = swapper_;
        stable = stable_;
        savingsVault = savingsVault_;
    }

    modifier onlyExecutor() {
        if (msg.sender != executor) revert OnlyExecutor();
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    /// @notice One-time wiring: point the vault at the deployed SplitExecutor.
    function setExecutor(address executor_) external onlyOwner {
        executor = executor_;
    }

    /// @notice Set your own split rules. Default (never set) is 30/30/40:
    ///         30% savings, 30% stablecoin, 40% stays spendable.
    function setRules(uint16 savingsBps_, uint16 stableBps_) external {
        if (uint256(savingsBps_) + uint256(stableBps_) > MAX_BPS) revert RulesExceed100Percent();
        rulesOf[msg.sender] = Rules(savingsBps_, stableBps_);
        rulesSet[msg.sender] = true;
        emit RulesUpdated(msg.sender, savingsBps_, stableBps_);
    }

    /// @notice Effective rules for a user: their own if set, else the default.
    function effectiveRules(address user_) public view returns (Rules memory) {
        if (!rulesSet[user_]) {
            return Rules({ savingsBps: 3000, stableBps: 3000 });
        }
        return rulesOf[user_];
    }

    /// @notice Deposit ETH. The full amount is credited as spendable first;
    ///         the split (triggered by the reactive callback) moves slices out.
    function deposit() external payable returns (uint256 depositId) {
        if (msg.value == 0) revert ZeroAmount();
        Rules memory r = effectiveRules(msg.sender);
        depositId = nextDepositId++;
        deposits[depositId] = Deposit({ user: msg.sender, amount: msg.value, split: false });
        availableOf[msg.sender] += msg.value;
        emit DepositReceived(msg.sender, msg.value, depositId, r.savingsBps, r.stableBps);
    }

    /// @notice Executes a split previously computed by the reactive contract.
    ///         Callable only by the SplitExecutor, which itself only runs on an
    ///         authenticated callback from the reactive contract.
    function executeSplit(uint256 depositId_, uint256 savingsAmount_, uint256 stableAmount_) external onlyExecutor {
        Deposit storage dep = deposits[depositId_];
        if (dep.user == address(0)) revert UnknownDeposit();
        if (dep.split) revert DepositAlreadySplit();
        if (savingsAmount_ + stableAmount_ > dep.amount) revert SplitAmountsMismatch();
        dep.split = true;

        uint256 stableReceived = 0;
        if (savingsAmount_ > 0) {
            savingsVault.depositFor{ value: savingsAmount_ }(dep.user);
        }
        if (stableAmount_ > 0) {
            stableReceived = swapper.swap{ value: stableAmount_ }(address(this));
            stableOf[dep.user] += stableReceived;
        }
        uint256 remainder = dep.amount - savingsAmount_ - stableAmount_;
        availableOf[dep.user] = availableOf[dep.user] - savingsAmount_ - stableAmount_;
        emit SplitExecuted(dep.user, depositId_, savingsAmount_, stableAmount_, stableReceived, remainder);
    }

    /// @notice Withdraw spendable ETH.
    function withdraw(uint256 amount_) external {
        if (amount_ > availableOf[msg.sender]) revert InsufficientBalance();
        availableOf[msg.sender] -= amount_;
        (bool ok,) = payable(msg.sender).call{ value: amount_ }("");
        require(ok, "ETH transfer failed");
        emit Withdrawn(msg.sender, amount_);
    }

    /// @notice Withdraw credited stablecoin.
    function withdrawStable(uint256 amount_) external {
        if (amount_ > stableOf[msg.sender]) revert InsufficientBalance();
        stableOf[msg.sender] -= amount_;
        require(stable.transfer(msg.sender, amount_), "stable transfer failed");
        emit StableWithdrawn(msg.sender, amount_);
    }
}
