// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TripFund} from "../src/TripFund.sol";
import {FailingToken} from "./mocks/FailingToken.sol";

/// П. 5: ошибка перевода откатывает всю операцию (учёт не меняется).
contract TripFundTransferFailureTest is Test {
    FailingToken internal token;
    TripFund internal fund;
    address internal organizer = makeAddr("organizer");
    address internal alice = makeAddr("alice");
    uint256 internal deadline;

    function setUp() public {
        deadline = block.timestamp + 1 days;
        token = new FailingToken();
        fund = new TripFund(IERC20(address(token)), organizer, 100 ether, deadline);
        token.mint(alice, 1_000 ether);
        vm.prank(alice);
        token.approve(address(fund), type(uint256).max);
    }

    function test_Refund_FailedTransferRevertsEverything() public {
        vm.prank(alice);
        fund.contribute(10 ether);
        vm.warp(deadline);
        token.setFail(true);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(token)));
        fund.refund();

        assertEq(fund.contributions(alice), 10 ether, "contribution must be restored");
        assertEq(token.balanceOf(address(fund)), 10 ether);

        token.setFail(false);
        vm.prank(alice);
        fund.refund();
        assertEq(fund.contributions(alice), 0);
    }

    function test_Withdraw_FailedTransferRevertsEverything() public {
        vm.prank(alice);
        fund.contribute(100 ether);
        vm.warp(deadline);
        token.setFail(true);

        vm.prank(organizer);
        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(token)));
        fund.withdraw();

        assertFalse(fund.withdrawn(), "withdrawn flag must be restored");

        token.setFail(false);
        vm.prank(organizer);
        fund.withdraw();
        assertEq(token.balanceOf(organizer), 100 ether);
    }
}
