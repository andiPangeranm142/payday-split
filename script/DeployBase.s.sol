// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Script, console } from "forge-std/Script.sol";
import { PaydayUSD } from "../src/PaydayUSD.sol";
import { MockSwapper } from "../src/MockSwapper.sol";
import { SavingsVault } from "../src/SavingsVault.sol";
import { PaydayVault } from "../src/PaydayVault.sol";

/// @notice Deploys the Base Sepolia side: savings vault, pUSD token,
///         mock swapper, payday vault. Wires savings -> vault.
///         Executor wiring happens after the reactive contract exists
///         (see DeployExecutor + Configure).
contract DeployBase is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);

        // PaydayUSD's minter is the swapper; the swapper needs the token
        // address. Break the cycle with a CREATE nonce prediction:
        // savings (nonce+0), token (nonce+1), swapper (nonce+2), vault (nonce+3).
        uint256 nonce = vm.getNonce(deployer);
        address predictedSwapper = vm.computeCreateAddress(deployer, nonce + 2);

        SavingsVault savings = new SavingsVault();
        PaydayUSD stable = new PaydayUSD(predictedSwapper);
        MockSwapper swapper = new MockSwapper(stable);
        require(address(swapper) == predictedSwapper, "swapper prediction mismatch");
        PaydayVault vault = new PaydayVault(swapper, stable, savings);

        savings.setVault(address(vault));

        vm.stopBroadcast();

        console.log("SavingsVault: ", address(savings));
        console.log("PaydayUSD:    ", address(stable));
        console.log("MockSwapper:  ", address(swapper));
        console.log("PaydayVault:  ", address(vault));
    }
}
