// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { UniswapSwapper } from "../src/UniswapSwapper.sol";
import { PaydayVault } from "../src/PaydayVault.sol";
import { SavingsVault } from "../src/SavingsVault.sol";
import { IERC20 } from "../src/IERC20.sol";

/// @notice Fork tests against the REAL Base Sepolia Uniswap V3 deployment.
///         Needs network access: run with `forge test --match-contract UniswapSwapperFork`.
///         RPC defaults to the public endpoint; override with BASE_SEPOLIA_RPC.
contract UniswapSwapperForkTest is Test {
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
    address constant ROUTER = 0x94cC0AaC535CCDB3C01d6787D6413C739ae12bc4;
    address constant QUOTER = 0xC5290058841028F1614F3A6F0F5816cAd0df5E27;
    uint24 constant FEE = 3000;

    UniswapSwapper swapper;
    IERC20 usdc = IERC20(USDC);
    address user = address(0xBEEF);

    function setUp() public {
        string memory rpc = vm.envOr("BASE_SEPOLIA_RPC", string("https://sepolia.base.org"));
        vm.createSelectFork(rpc);
        swapper = new UniswapSwapper(WETH, USDC, ROUTER, QUOTER, FEE);
        vm.deal(address(this), 10 ether);
    }

    /// @notice The real pool swaps: 0.0001 WETH must yield real USDC in a sane
    ///         band (wide bounds — the pool price moves; the point is that the
    ///         route, quoter tightening and floor all work against live state).
    ///         At v2 launch the pool prices ETH at ~$26,500 (testnet pools are
    ///         seeded arbitrarily), so 0.0001 ETH yields ~2.65 USDC.
    function testForkRealSwap() public {
        // NOTE: 0xBEEF may already hold USDC on the fork — compare deltas.
        uint256 before = usdc.balanceOf(user);
        uint256 out = swapper.swap{ value: 0.0001 ether }(user);
        assertGt(out, 1e6, "too little USDC out");
        assertLt(out, 5e6, "too much USDC out");
        assertEq(usdc.balanceOf(user) - before, out);
    }

    /// @notice Full v2 stack on the fork: deposit, then the executor path
    ///         (pranked) splits through the real swapper — savings lock,
    ///         real USDC credit and spendable remainder all land correctly.
    function testForkVaultSplitWithRealSwap() public {
        SavingsVault savings = new SavingsVault();
        PaydayVault vault = new PaydayVault(swapper, IERC20(USDC), savings);
        savings.setVault(address(vault));
        vault.setExecutor(address(this));

        address alice = address(0xA11CE);
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        vault.setRules(5000, 3000); // 50% savings / 30% stable / 20% spendable
        vm.prank(alice);
        uint256 depositId = vault.deposit{ value: 0.001 ether }();

        vault.executeSplit(depositId, 0.0005 ether, 0.0003 ether);

        // Savings: one lock of 0.0005 ETH.
        assertEq(savings.nextLockId(), 1);
        (address lockUser, uint256 lockAmount,,) = savings.locks(0);
        assertEq(lockUser, alice);
        assertEq(lockAmount, 0.0005 ether);
        // Stable: real USDC, 0.0003 ETH at ~$26,500 = ~7.95 USDC (wide band).
        uint256 stable = vault.stableOf(alice);
        assertGt(stable, 3e6);
        assertLt(stable, 15e6);
        // Spendable remainder: 20% of 0.001 = 0.0002 ETH.
        assertEq(vault.availableOf(alice), 0.0002 ether);
        // Vault actually holds the USDC it credited.
        assertGe(usdc.balanceOf(address(vault)), stable);
    }
}
