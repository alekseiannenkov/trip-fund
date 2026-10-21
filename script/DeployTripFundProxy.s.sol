// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {TripFundV1} from "../src/TripFundV1.sol";
import {MockToken} from "../src/mocks/MockToken.sol";

/// Бонус V1: MockToken + реализация TripFundV1 + TransparentUpgradeableProxy.
/// Владелец ProxyAdmin — деплоер (или ADMIN_OWNER).
contract DeployTripFundProxy is Script {
    function run() external returns (MockToken token, TripFundV1 fund) {
        address organizer = vm.envOr("ORGANIZER", msg.sender);
        address adminOwner = vm.envOr("ADMIN_OWNER", msg.sender);
        uint256 goal = vm.envOr("GOAL", uint256(100 ether));
        uint256 deadline = block.timestamp + vm.envOr("DURATION", uint256(7 days));

        vm.startBroadcast();
        token = new MockToken();
        token.mint(msg.sender, 1_000 ether);
        TripFundV1 impl = new TripFundV1();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(impl),
            adminOwner,
            abi.encodeCall(TripFundV1.initialize, (IERC20(address(token)), organizer, goal, deadline))
        );
        vm.stopBroadcast();

        fund = TripFundV1(address(proxy));
        address proxyAdmin = address(uint160(uint256(vm.load(address(proxy), ERC1967Utils.ADMIN_SLOT))));

        console.log("MockToken:      ", address(token));
        console.log("Implementation: ", address(impl));
        console.log("Proxy (TripFund):", address(proxy));
        console.log("ProxyAdmin:     ", proxyAdmin);
    }
}
