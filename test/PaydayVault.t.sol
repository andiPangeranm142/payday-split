// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { PaydayUSD } from "../src/PaydayUSD.sol";
import { MockSwapper } from "../src/MockSwapper.sol";
import { SavingsVault } from "../src/SavingsVault.sol";
import { PaydayVault } from "../src/PaydayVault.sol";

contract PaydayVaultTest is Test {
    PaydayUSD stable;
    MockSwapper swapper;
    SavingsVault savings;
    PaydayVault vault;

    address user = address(0xBEEF);
    address executor = address(0xE9E9);

    function setUp() public {
        savings = new SavingsVault();
        // PaydayUSD's minter is the swapper, and the swapper needs the token
        // address — break the cycle by predicting the swapper's address from
        // the deployer nonce (same trick the deploy script uses).
        address predictedSwapper = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);
        stable = new PaydayUSD(predictedSwapper);
        swapper = new MockSwapper(stable);
        require(address(swapper) == predictedSwapper, "prediction mismatch");
        vault = new PaydayVault(swapper, stable, savings);
        savings.setVault(address(vault));
        vault.setExecutor(executor);
        vm.deal(user, 100 ether);
    }

    function testDefaultRulesAre30_30() public view {
        PaydayVault.Rules memory r = vault.effectiveRules(user);
        assertEq(r.savingsBps, 3000);
        assertEq(r.stableBps, 3000);
    }

    function testSetRules() public {
        vm.prank(user);
        vault.setRules(5000, 2000);
        PaydayVault.Rules memory r = vault.effectiveRules(user);
        assertEq(r.savingsBps, 5000);
        assertEq(r.stableBps, 2000);
    }

    function testSetRulesRejectsOver100Percent() public {
        vm.prank(user);
        vm.expectRevert(PaydayVault.RulesExceed100Percent.selector);
        vault.setRules(6000, 5000);
    }

    function testExplicitZeroRulesStayZero() public {
        vm.prank(user);
        vault.setRules(0, 0);
        PaydayVault.Rules memory r = vault.effectiveRules(user);
        assertEq(r.savingsBps, 0);
        assertEq(r.stableBps, 0);
    }

    function testDepositEmitsEventWithRules() public {
        vm.expectEmit(true, false, false, true, address(vault));
        emit PaydayVault.DepositReceived(user, 1 ether, 0, 3000, 3000);
        vm.prank(user);
        vault.deposit{ value: 1 ether }();
        assertEq(vault.availableOf(user), 1 ether);
    }

    function testDepositRejectsZero() public {
        vm.prank(user);
        vm.expectRevert(PaydayVault.ZeroAmount.selector);
        vault.deposit();
    }

    function testExecuteSplitMovesMoney() public {
        vm.prank(user);
        uint256 id = vault.deposit{ value: 10 ether }();

        vm.prank(executor);
        vault.executeSplit(id, 3 ether, 3 ether);

        // 30% savings locked, 30% swapped at 2000 pUSD/ETH, 40% remains.
        assertEq(vault.availableOf(user), 4 ether);
        assertEq(vault.stableOf(user), 6000 ether);
        assertEq(stable.balanceOf(address(vault)), 6000 ether);
        uint256[] memory lockIds = savings.lockIdsOf(user);
        assertEq(lockIds.length, 1);
        (address u, uint256 amt,, bool w) = savings.locks(lockIds[0]);
        assertEq(u, user);
        assertEq(amt, 3 ether);
        assertFalse(w);
    }

    function testExecuteSplitOnlyExecutor() public {
        vm.prank(user);
        uint256 id = vault.deposit{ value: 1 ether }();
        vm.expectRevert(PaydayVault.OnlyExecutor.selector);
        vault.executeSplit(id, 0.3 ether, 0.3 ether);
    }

    function testExecuteSplitTwiceReverts() public {
        vm.prank(user);
        uint256 id = vault.deposit{ value: 1 ether }();
        vm.prank(executor);
        vault.executeSplit(id, 0.3 ether, 0.3 ether);
        vm.prank(executor);
        vm.expectRevert(PaydayVault.DepositAlreadySplit.selector);
        vault.executeSplit(id, 0.3 ether, 0.3 ether);
    }

    function testExecuteSplitRejectsOvershoot() public {
        vm.prank(user);
        uint256 id = vault.deposit{ value: 1 ether }();
        vm.prank(executor);
        vm.expectRevert(PaydayVault.SplitAmountsMismatch.selector);
        vault.executeSplit(id, 0.6 ether, 0.6 ether);
    }

    function testWithdraw() public {
        vm.prank(user);
        vault.deposit{ value: 2 ether }();
        uint256 before = user.balance;
        vm.prank(user);
        vault.withdraw(1.5 ether);
        assertEq(user.balance, before + 1.5 ether);
        assertEq(vault.availableOf(user), 0.5 ether);
    }

    function testWithdrawStable() public {
        vm.prank(user);
        uint256 id = vault.deposit{ value: 10 ether }();
        vm.prank(executor);
        vault.executeSplit(id, 3 ether, 3 ether);
        vm.prank(user);
        vault.withdrawStable(6000 ether);
        assertEq(stable.balanceOf(user), 6000 ether);
        assertEq(vault.stableOf(user), 0);
    }
}

contract MockSwapperTest is Test {
    PaydayUSD stable;
    MockSwapper swapper;

    function setUp() public {
        address predicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);
        stable = new PaydayUSD(predicted);
        swapper = new MockSwapper(stable);
    }

    function testFixedRate() public {
        uint256 out = swapper.swap{ value: 2 ether }(address(this));
        assertEq(out, 4000 ether);
        assertEq(stable.balanceOf(address(this)), 4000 ether);
    }

    function testRateUpdate() public {
        swapper.setRate(3000 ether);
        uint256 out = swapper.swap{ value: 1 ether }(address(this));
        assertEq(out, 3000 ether);
    }

    function testSwapRejectsZero() public {
        vm.expectRevert(MockSwapper.ZeroAmount.selector);
        swapper.swap(address(this));
    }
}

contract SavingsVaultTest is Test {
    SavingsVault savings;
    address user = address(0xBEEF);

    function setUp() public {
        savings = new SavingsVault();
        savings.setVault(address(this));
    }

    function testLockAndWithdrawAfterUnlock() public {
        uint256 id = savings.depositFor{ value: 1 ether }(user);
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(SavingsVault.StillLocked.selector, block.timestamp + 30 days)
        );
        savings.withdraw(id);

        vm.warp(block.timestamp + 30 days + 1);
        uint256 before = user.balance;
        vm.prank(user);
        savings.withdraw(id);
        assertEq(user.balance, before + 1 ether);
    }

    function testOnlyVaultCanDeposit() public {
        vm.prank(user);
        vm.expectRevert(SavingsVault.OnlyVault.selector);
        savings.depositFor(user);
    }

    function testOnlyLockOwnerCanWithdraw() public {
        uint256 id = savings.depositFor{ value: 1 ether }(user);
        vm.warp(block.timestamp + 31 days);
        vm.expectRevert(SavingsVault.NotLockOwner.selector);
        savings.withdraw(id);
    }
}
