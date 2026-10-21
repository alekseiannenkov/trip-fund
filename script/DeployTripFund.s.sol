// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TripFund} from "../src/TripFund.sol";
import {MockToken} from "../src/mocks/MockToken.sol";

/// Локальный деплой: MockToken + TripFund. Деплоер получает 1000 TRIP.
/// ORGANIZER, GOAL, DURATION можно переопределить переменными окружения.
contract DeployTripFund is Script {
    function run() external returns (MockToken token, TripFund fund) {
        address organizer = vm.envOr("ORGANIZER", msg.sender);
        uint256 goal = vm.envOr("GOAL", uint256(100 ether));
        uint256 deadline = block.timestamp + vm.envOr("DURATION", uint256(7 days));

        vm.startBroadcast();
        token = new MockToken();
        token.mint(msg.sender, 1_000 ether);
        fund = new TripFund(IERC20(address(token)), organizer, goal, deadline);
        vm.stopBroadcast();

        console.log("MockToken:", address(token));
        console.log("TripFund: ", address(fund));
        console.log("deadline: ", deadline);
    }
}
