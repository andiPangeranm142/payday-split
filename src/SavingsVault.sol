// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title SavingsVault — timelocked savings leg of a Payday Split.
/// @notice Every savings slice becomes its own lock record with an unlock time.
///         A user withdraws a lock only after it matures, which is the whole
///         point of "pay yourself first": the money is out of reach until then.
contract SavingsVault {
    struct Lock {
        address user;
        uint256 amount;
        uint256 unlockTime;
        bool withdrawn;
    }

    /// @notice Lock duration for new savings deposits (default 30 days).
    uint256 public lockDuration = 30 days;

    address public immutable owner;
    address public vault; // PaydayVault — the only contract allowed to deposit.

    uint256 public nextLockId;
    mapping(uint256 => Lock) public locks;
    mapping(address => uint256[]) public locksOf;

    event SavingsDeposited(address indexed user, uint256 indexed lockId, uint256 amount, uint256 unlockTime);
    event SavingsWithdrawn(address indexed user, uint256 indexed lockId, uint256 amount);
    event LockDurationUpdated(uint256 oldDuration, uint256 newDuration);

    error OnlyOwner();
    error OnlyVault();
    error ZeroAmount();
    error NotLockOwner();
    error StillLocked(uint256 unlockTime);
    error AlreadyWithdrawn();

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    /// @notice One-time wiring: point the vault at the deployed PaydayVault.
    function setVault(address vault_) external onlyOwner {
        vault = vault_;
    }

    function setLockDuration(uint256 duration_) external onlyOwner {
        emit LockDurationUpdated(lockDuration, duration_);
        lockDuration = duration_;
    }

    /// @notice Called by PaydayVault (only) when a split routes savings here.
    function depositFor(address user_) external payable returns (uint256 lockId) {
        if (msg.sender != vault) revert OnlyVault();
        if (msg.value == 0) revert ZeroAmount();
        lockId = nextLockId++;
        locks[lockId] = Lock({
            user: user_,
            amount: msg.value,
            unlockTime: block.timestamp + lockDuration,
            withdrawn: false
        });
        locksOf[user_].push(lockId);
        emit SavingsDeposited(user_, lockId, msg.value, block.timestamp + lockDuration);
    }

    /// @notice Withdraw a matured lock.
    function withdraw(uint256 lockId_) external {
        Lock storage lock = locks[lockId_];
        if (lock.user != msg.sender) revert NotLockOwner();
        if (lock.withdrawn) revert AlreadyWithdrawn();
        if (block.timestamp < lock.unlockTime) revert StillLocked(lock.unlockTime);
        lock.withdrawn = true;
        (bool ok,) = payable(msg.sender).call{ value: lock.amount }("");
        require(ok, "ETH transfer failed");
        emit SavingsWithdrawn(msg.sender, lockId_, lock.amount);
    }

    function lockIdsOf(address user_) external view returns (uint256[] memory) {
        return locksOf[user_];
    }
}
