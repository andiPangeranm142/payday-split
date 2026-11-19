// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Script, console } from "forge-std/Script.sol";
import { UniswapSwapper } from "../src/UniswapSwapper.sol";
import { SavingsVault } from "../src/SavingsVault.sol";
import { PaydayVault } from "../src/PaydayVault.sol";
import { IERC20 } from "../src/IERC20.sol";

/// @notice Deploys the v2 Base Sepolia side: savings vault, Uniswap swapper
///         (real WETH -> USDC via Uniswap V3), payday vault. Wires savings ->
///         vault. No pUSD in v2 — the stable leg is real Circle USDC.
///         Executor + reactive wiring reuse DeployExecutor / DeployReactive
///         (see README "v2 deployment").
contract DeployBaseV2 is Script {
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
    address constant ROUTER = 0x94cC0AaC535CCDB3C01d6787D6413C739ae12bc4;
    address constant QUOTER = 0xC5290058841028F1614F3A6F0F5816cAd0df5E27;
    uint24 constant FEE = 3000; // WETH/USDC 0.3% pool (deepest on Base Sepolia)

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerKey);

        SavingsVault savings = new SavingsVault();
        UniswapSwapper swapper = new UniswapSwapper(WETH, USDC, ROUTER, QUOTER, FEE);
        PaydayVault vault = new PaydayVault(swapper, IERC20(USDC), savings);

        savings.setVault(address(vault));

        vm.stopBroadcast();

        console.log("SavingsVault v2:  ", address(savings));
        console.log("UniswapSwapper:   ", address(swapper));
        console.log("PaydayVault v2:   ", address(vault));
        console.log("USDC (Circle):    ", USDC);
    }
}
