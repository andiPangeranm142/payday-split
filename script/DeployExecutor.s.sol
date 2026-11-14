// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Script, console } from "forge-std/Script.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { SplitExecutor } from "../src/SplitExecutor.sol";
import { PaydayVault } from "../src/PaydayVault.sol";

/// @notice Deploys the callback contract on Base Sepolia.
///         Env: PRIVATE_KEY, REACTIVE_ADDR (PaydaySplit on Lasna),
///         VAULT_ADDR (PaydayVault), FUND_ETH_WEI (optional, default 0.0005 ether).
contract DeployExecutor is Script {
    address constant BASE_SEPOLIA_PROXY = 0x476F44b11F5C942c58f4c8E3d0300E5710743585;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address reactiveAddr = vm.envAddress("REACTIVE_ADDR");
        PaydayVault vault = PaydayVault(vm.envAddress("VAULT_ADDR"));
        uint256 fund = vm.envOr("FUND_ETH_WEI", uint256(0.0005 ether));

        vm.startBroadcast(deployerKey);
        SplitExecutor executor =
            new SplitExecutor{ value: fund }(IPayable(payable(BASE_SEPOLIA_PROXY)), reactiveAddr, vault);
        vm.stopBroadcast();

        console.log("SplitExecutor: ", address(executor));
        console.log("Funded with ETH: ", fund);
    }
}
