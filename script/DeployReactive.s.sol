// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Script, console } from "forge-std/Script.sol";
import { PaydaySplit } from "../src/PaydaySplit.sol";

/// @notice Deploys the reactive contract on Reactive Lasna.
///         Env: PRIVATE_KEY, ORIGIN_VAULT (PaydayVault on Base Sepolia),
///         FUND_LREACT_WEI (optional, default 0.15 ether — funds react() calls).
contract DeployReactive is Script {
    uint256 constant BASE_SEPOLIA = 84532;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address originVault = vm.envAddress("ORIGIN_VAULT");
        uint256 fund = vm.envOr("FUND_LREACT_WEI", uint256(0.15 ether));
        uint256 topic0 = uint256(keccak256("DepositReceived(address,uint256,uint256,uint16,uint16)"));

        vm.startBroadcast(deployerKey);
        PaydaySplit reactive = new PaydaySplit{ value: fund }(BASE_SEPOLIA, originVault, topic0);
        vm.stopBroadcast();

        console.log("PaydaySplit (Lasna): ", address(reactive));
        console.log("Funded with lREACT:  ", fund);
    }
}
