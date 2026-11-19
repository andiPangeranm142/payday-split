// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { PaydaySplit } from "../src/PaydaySplit.sol";
import { SplitExecutor } from "../src/SplitExecutor.sol";
import { PaydayUSD } from "../src/PaydayUSD.sol";
import { MockSwapper } from "../src/MockSwapper.sol";
import { SavingsVault } from "../src/SavingsVault.sol";
import { PaydayVault } from "../src/PaydayVault.sol";

/// @notice Edge-case, access-control and fuzz tests added after the initial
///         submission to harden the suite: accounting identities that must
///         hold for every deposit size and rule combination, boundary checks
///         around the dust guard, and owner-guard coverage for every admin
///         function.
contract PaydayVaultEdgeTest is Test {
    PaydayUSD stable;
    MockSwapper swapper;
    SavingsVault savings;
    PaydayVault vault;

    address user = address(0xBEEF);
    address executor = address(0xE9E9);

    function setUp() public {
        savings = new SavingsVault();
        address predictedSwapper = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);
        stable = new PaydayUSD(predictedSwapper);
        swapper = new MockSwapper(stable);
        require(address(swapper) == predictedSwapper, "prediction mismatch");
        vault = new PaydayVault(swapper, stable, savings);
        savings.setVault(address(vault));
        vault.setExecutor(executor);
        vm.deal(user, 100 ether);
    }

    /// @notice Accounting identity: for ANY deposit size and ANY valid rules,
    ///         spendable + locked + swapped-out must equal the deposit, and the
    ///         pUSD credited must equal the swapped leg at the fixed rate.
    function testFuzzSplitAccounting(uint96 rawAmount, uint16 rawSavingsBps, uint16 rawStableBps) public {
        uint256 amount = bound(uint256(rawAmount), 1, 100 ether);
        uint16 savingsBps = uint16(bound(uint256(rawSavingsBps), 0, 10_000));
        uint16 stableBps = uint16(bound(uint256(rawStableBps), 0, 10_000 - savingsBps));
        uint256 savingsAmount = (amount * savingsBps) / 10_000;
        uint256 stableAmount = (amount * stableBps) / 10_000;

        vm.prank(user);
        vault.setRules(savingsBps, stableBps);
        vm.prank(user);
        uint256 id = vault.deposit{ value: amount }();

        vm.prank(executor);
        vault.executeSplit(id, savingsAmount, stableAmount);

        assertEq(vault.availableOf(user), amount - savingsAmount - stableAmount, "spendable");
        assertEq(vault.stableOf(user), stableAmount * 2000, "pUSD credited");
        if (savingsAmount > 0) {
            uint256[] memory lockIds = savings.lockIdsOf(user);
            assertEq(lockIds.length, 1);
            (, uint256 locked,,) = savings.locks(lockIds[0]);
            assertEq(locked, savingsAmount, "locked");
        } else {
            assertEq(savings.lockIdsOf(user).length, 0);
        }
    }

    function testRulesExactly100Percent() public {
        vm.prank(user);
        vault.setRules(6000, 4000);
        vm.prank(user);
        uint256 id = vault.deposit{ value: 1 ether }();
        vm.prank(executor);
        vault.executeSplit(id, 0.6 ether, 0.4 ether);
        assertEq(vault.availableOf(user), 0, "nothing stays spendable at 100%");
    }

    function testZeroRulesAllSpendable() public {
        vm.prank(user);
        vault.setRules(0, 0);
        vm.prank(user);
        uint256 id = vault.deposit{ value: 1 ether }();
        vm.prank(executor);
        vault.executeSplit(id, 0, 0);
        assertEq(vault.availableOf(user), 1 ether);
        assertEq(savings.lockIdsOf(user).length, 0);
    }

    function testWithdrawMoreThanAvailableReverts() public {
        vm.prank(user);
        vault.deposit{ value: 1 ether }();
        vm.prank(user);
        vm.expectRevert(PaydayVault.InsufficientBalance.selector);
        vault.withdraw(1 ether + 1);
    }

    function testWithdrawStableMoreThanCreditedReverts() public {
        vm.prank(user);
        uint256 id = vault.deposit{ value: 10 ether }();
        vm.prank(executor);
        vault.executeSplit(id, 3 ether, 3 ether);
        vm.prank(user);
        vm.expectRevert(PaydayVault.InsufficientBalance.selector);
        vault.withdrawStable(6000 ether + 1);
    }

    function testExecuteSplitUnknownDepositReverts() public {
        vm.prank(executor);
        vm.expectRevert(PaydayVault.UnknownDeposit.selector);
        vault.executeSplit(999, 0.1 ether, 0.1 ether);
    }

    function testMultipleDepositsMultipleLocks() public {
        vm.prank(user);
        uint256 id1 = vault.deposit{ value: 2 ether }();
        vm.prank(user);
        uint256 id2 = vault.deposit{ value: 4 ether }();
        vm.prank(executor);
        vault.executeSplit(id1, 0.6 ether, 0.6 ether);
        vm.prank(executor);
        vault.executeSplit(id2, 1.2 ether, 1.2 ether);

        uint256[] memory lockIds = savings.lockIdsOf(user);
        assertEq(lockIds.length, 2);
        (, uint256 a1,,) = savings.locks(lockIds[0]);
        (, uint256 a2,,) = savings.locks(lockIds[1]);
        assertEq(a1, 0.6 ether);
        assertEq(a2, 1.2 ether);
        assertEq(vault.availableOf(user), 2.4 ether);
    }
}

contract SavingsVaultEdgeTest is Test {
    SavingsVault savings;
    address user = address(0xBEEF);

    function setUp() public {
        savings = new SavingsVault();
        savings.setVault(address(this));
    }

    function testWithdrawTwiceReverts() public {
        uint256 id = savings.depositFor{ value: 1 ether }(user);
        vm.warp(block.timestamp + 31 days);
        vm.prank(user);
        savings.withdraw(id);
        vm.prank(user);
        vm.expectRevert(SavingsVault.AlreadyWithdrawn.selector);
        savings.withdraw(id);
    }

    function testDepositForZeroReverts() public {
        vm.expectRevert(SavingsVault.ZeroAmount.selector);
        savings.depositFor(user);
    }

    function testSetLockDurationOnlyOwner() public {
        vm.prank(user);
        vm.expectRevert(SavingsVault.OnlyOwner.selector);
        savings.setLockDuration(1 days);
    }

    function testSetLockDurationChangesNewLocks() public {
        savings.setLockDuration(7 days);
        assertEq(savings.lockDuration(), 7 days);
        uint256 id = savings.depositFor{ value: 1 ether }(user);
        (,, uint256 unlockTime,) = savings.locks(id);
        assertEq(unlockTime, block.timestamp + 7 days);
    }

    function testSetVaultOnlyOwner() public {
        vm.prank(user);
        vm.expectRevert(SavingsVault.OnlyOwner.selector);
        savings.setVault(address(0x1234));
    }
}

contract MockSwapperEdgeTest is Test {
    PaydayUSD stable;
    MockSwapper swapper;
    address user = address(0xBEEF);

    function setUp() public {
        address predicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);
        stable = new PaydayUSD(predicted);
        swapper = new MockSwapper(stable);
    }

    function testSetRateOnlyOwner() public {
        vm.prank(user);
        vm.expectRevert(MockSwapper.OnlyOwner.selector);
        swapper.setRate(1);
    }

    function testSweepOnlyOwner() public {
        vm.prank(user);
        vm.expectRevert(MockSwapper.OnlyOwner.selector);
        swapper.sweep(payable(user));
    }

    function testSweepRecoversEth() public {
        swapper.swap{ value: 1 ether }(address(this));
        assertEq(address(swapper).balance, 1 ether);
        uint256 before = user.balance;
        swapper.sweep(payable(user));
        assertEq(address(swapper).balance, 0);
        assertEq(user.balance, before + 1 ether);
    }
}

contract PaydayUSDEdgeTest is Test {
    PaydayUSD stable;
    address user = address(0xBEEF);
    address spender = address(0x5EED);

    function setUp() public {
        stable = new PaydayUSD(address(this));
    }

    function testMintOnlyMinter() public {
        vm.prank(user);
        vm.expectRevert(PaydayUSD.OnlyMinter.selector);
        stable.mint(user, 1 ether);
    }

    function testTransferFromWithAllowance() public {
        stable.mint(user, 100 ether);
        vm.prank(user);
        stable.approve(spender, 40 ether);
        vm.prank(spender);
        stable.transferFrom(user, spender, 40 ether);
        assertEq(stable.balanceOf(spender), 40 ether);
        assertEq(stable.balanceOf(user), 60 ether);
        assertEq(stable.allowance(user, spender), 0);
    }

    function testTransferFromExceedsAllowanceReverts() public {
        stable.mint(user, 100 ether);
        vm.prank(user);
        stable.approve(spender, 10 ether);
        vm.prank(spender);
        vm.expectRevert(PaydayUSD.InsufficientAllowance.selector);
        stable.transferFrom(user, spender, 11 ether);
    }

    function testTransferInsufficientReverts() public {
        stable.mint(user, 1 ether);
        vm.prank(user);
        vm.expectRevert(PaydayUSD.InsufficientBalance.selector);
        stable.transfer(spender, 2 ether);
    }
}

contract PaydaySplitEdgeTest is Test {
    address constant SYSTEM_ADDR = 0x8888888888888888888888888888888888888888;
    uint256 constant BASE_SEPOLIA = 84532;

    PaydaySplit reactive;
    address vault = address(0x1234567890123456789012345678901234567890);
    address executor = address(0xE9E9);
    address user = address(0xBEEF);

    bytes32 topic0;

    function setUp() public {
        vm.etch(SYSTEM_ADDR, hex"00");
        topic0 = keccak256("DepositReceived(address,uint256,uint256,uint16,uint16)");
        reactive = new PaydaySplit(BASE_SEPOLIA, vault, uint256(topic0));
        reactive.setExecutor(executor, BASE_SEPOLIA);
    }

    function _log(uint256 amount, uint256 depositId, uint16 savingsBps, uint16 stableBps)
        internal
        view
        returns (IReactive.LogRecord memory)
    {
        return IReactive.LogRecord({
            chainId: BASE_SEPOLIA,
            contractAddress: vault,
            topic0: uint256(topic0),
            topic1: uint256(uint160(user)),
            topic2: 0,
            topic3: 0,
            data: abi.encode(amount, depositId, savingsBps, stableBps),
            blockNumber: 1,
            opCode: 2,
            blockHash: 0,
            txHash: uint256(keccak256(abi.encode(depositId))),
            logIndex: 0
        });
    }

    function _react(IReactive.LogRecord memory log_) internal {
        vm.prank(SYSTEM_ADDR);
        reactive.react(log_);
    }

    /// @notice Split math must never revert and must always request exactly
    ///         one callback for any in-range deposit and any valid rules.
    function testFuzzSplitMath(uint256 rawAmount, uint16 rawSavingsBps, uint16 rawStableBps) public {
        uint256 amount = bound(rawAmount, reactive.minDeposit(), 1000 ether);
        uint16 savingsBps = uint16(bound(uint256(rawSavingsBps), 0, 10_000));
        uint16 stableBps = uint16(bound(uint256(rawStableBps), 0, 10_000 - savingsBps));
        _react(_log(amount, 1, savingsBps, stableBps));
        assertTrue(reactive.processed(1));
        assertEq(reactive.splitsRequested(), 1);
        assertEq(reactive.depositsSkipped(), 0);
    }

    function testMinDepositBoundary() public {
        uint256 min = reactive.minDeposit();
        _react(_log(min - 1, 11, 3000, 3000));
        assertEq(reactive.splitsRequested(), 0);
        assertEq(reactive.depositsSkipped(), 1);
        _react(_log(min, 12, 3000, 3000));
        assertTrue(reactive.processed(12));
        assertEq(reactive.splitsRequested(), 1);
    }

    /// @notice A skipped deposit is NOT marked processed, so it can be
    ///         retried after unpausing — pausing never loses a deposit.
    function testReactAfterUnpause() public {
        reactive.setPaused(true);
        _react(_log(1 ether, 13, 3000, 3000));
        assertEq(reactive.splitsRequested(), 0);
        assertFalse(reactive.processed(13));
        reactive.setPaused(false);
        _react(_log(1 ether, 13, 3000, 3000));
        assertTrue(reactive.processed(13));
        assertEq(reactive.splitsRequested(), 1);
    }

    function testOwnerGuards() public {
        vm.prank(user);
        vm.expectRevert(PaydaySplit.OnlyOwner.selector);
        reactive.setPaused(true);
        vm.prank(user);
        vm.expectRevert(PaydaySplit.OnlyOwner.selector);
        reactive.setExecutor(executor, BASE_SEPOLIA);
        vm.prank(user);
        vm.expectRevert(PaydaySplit.OnlyOwner.selector);
        reactive.setCallbackGasLimit(500_000);
    }
}
