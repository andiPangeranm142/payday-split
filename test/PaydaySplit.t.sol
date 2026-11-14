// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { PaydaySplit } from "../src/PaydaySplit.sol";
import { SplitExecutor } from "../src/SplitExecutor.sol";
import { PaydayVault } from "../src/PaydayVault.sol";
import { PaydayUSD } from "../src/PaydayUSD.sol";
import { MockSwapper } from "../src/MockSwapper.sol";
import { SavingsVault } from "../src/SavingsVault.sol";

contract PaydaySplitTest is Test {
    address constant SYSTEM_ADDR = 0x8888888888888888888888888888888888888888;
    uint256 constant BASE_SEPOLIA = 84532;

    PaydaySplit reactive;
    address vault = address(0x1234567890123456789012345678901234567890);
    address executor = address(0xE9E9);
    address user = address(0xBEEF);

    bytes32 topic0;

    function setUp() public {
        // The system contract has no code in a local test env; etch a stub
        // so subscribe()/requestCallback() calls succeed as no-ops.
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

    function testReactRequestsSplit() public {
        vm.expectEmit(true, true, false, true, address(reactive));
        emit PaydaySplit.SplitRequested(user, 7, 10 ether, 3 ether, 3 ether, uint256(keccak256(abi.encode(uint256(7)))));
        _react(_log(10 ether, 7, 3000, 3000));
        assertTrue(reactive.processed(7));
        assertEq(reactive.splitsRequested(), 1);
    }

    function testReactComputesCustomRules() public {
        _react(_log(4 ether, 1, 5000, 2000));
        assertTrue(reactive.processed(1));
        assertEq(reactive.splitsRequested(), 1);
    }

    function testReactRejectsNonSystemCaller() public {
        vm.expectRevert();
        reactive.react(_log(1 ether, 1, 3000, 3000));
    }

    function testReactIgnoresWrongTopic() public {
        IReactive.LogRecord memory log_ = _log(1 ether, 1, 3000, 3000);
        log_.topic0 = uint256(keccak256("SomethingElse()"));
        _react(log_);
        assertEq(reactive.splitsRequested(), 0);
    }

    function testReactIgnoresWrongContract() public {
        IReactive.LogRecord memory log_ = _log(1 ether, 1, 3000, 3000);
        log_.contractAddress = address(0xDEAD);
        _react(log_);
        assertEq(reactive.splitsRequested(), 0);
    }

    function testReactIgnoresWrongOpCode() public {
        IReactive.LogRecord memory log_ = _log(1 ether, 1, 3000, 3000);
        log_.opCode = 3;
        _react(log_);
        assertEq(reactive.splitsRequested(), 0);
    }

    function testReactSkipsDust() public {
        _react(_log(0.0005 ether, 2, 3000, 3000));
        assertEq(reactive.splitsRequested(), 0);
        assertEq(reactive.depositsSkipped(), 1);
        assertFalse(reactive.processed(2));
    }

    function testReactDedupes() public {
        _react(_log(1 ether, 3, 3000, 3000));
        _react(_log(1 ether, 3, 3000, 3000));
        assertEq(reactive.splitsRequested(), 1);
        assertEq(reactive.depositsSkipped(), 1);
    }

    function testReactSkipsWhenPaused() public {
        reactive.setPaused(true);
        _react(_log(1 ether, 4, 3000, 3000));
        assertEq(reactive.splitsRequested(), 0);
        assertEq(reactive.depositsSkipped(), 1);
    }

    function testReactSkipsWithoutExecutor() public {
        PaydaySplit fresh = new PaydaySplit(BASE_SEPOLIA, vault, uint256(topic0));
        vm.prank(SYSTEM_ADDR);
        fresh.react(_log(1 ether, 5, 3000, 3000));
        assertEq(fresh.splitsRequested(), 0);
        assertEq(fresh.depositsSkipped(), 1);
    }

    function testOnlyOwnerCanConfigure() public {
        vm.prank(user);
        vm.expectRevert(PaydaySplit.OnlyOwner.selector);
        reactive.setMinDeposit(1);
    }
}

contract SplitExecutorTest is Test {
    address constant PROXY = 0x476F44b11F5C942c58f4c8E3d0300E5710743585;
    address constant REACTIVE_SENDER = address(0xAA77);

    PaydayUSD stable;
    MockSwapper swapper;
    SavingsVault savings;
    PaydayVault vault;
    SplitExecutor executor;

    address user = address(0xBEEF);

    function setUp() public {
        savings = new SavingsVault();
        address predicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);
        stable = new PaydayUSD(predicted);
        swapper = new MockSwapper(stable);
        vault = new PaydayVault(swapper, stable, savings);
        savings.setVault(address(vault));
        executor = new SplitExecutor(IPayable(payable(PROXY)), REACTIVE_SENDER, vault);
        vault.setExecutor(address(executor));
        vm.deal(user, 100 ether);
    }

    function testCallbackExecutesSplit() public {
        vm.prank(user);
        uint256 id = vault.deposit{ value: 10 ether }();

        vm.prank(PROXY);
        executor.executeSplit(REACTIVE_SENDER, user, id, 10 ether, 3 ether, 3 ether);

        assertEq(vault.availableOf(user), 4 ether);
        assertEq(vault.stableOf(user), 6000 ether);
        assertEq(savings.lockIdsOf(user).length, 1);
    }

    function testCallbackRejectsNonProxyCaller() public {
        vm.prank(user);
        uint256 id = vault.deposit{ value: 1 ether }();
        vm.expectRevert();
        executor.executeSplit(REACTIVE_SENDER, user, id, 1 ether, 0.3 ether, 0.3 ether);
    }

    function testCallbackRejectsWrongReactiveSender() public {
        vm.prank(user);
        uint256 id = vault.deposit{ value: 1 ether }();
        vm.prank(PROXY);
        vm.expectRevert();
        executor.executeSplit(address(0xDEAD), user, id, 1 ether, 0.3 ether, 0.3 ether);
    }
}
