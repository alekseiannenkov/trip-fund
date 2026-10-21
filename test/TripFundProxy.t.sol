// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {TripFundV1} from "../src/TripFundV1.sol";
import {MockToken} from "../src/mocks/MockToken.sol";

/// Бонус, п. 10: TripFundV1 за TransparentUpgradeableProxy (OpenZeppelin 5.x).
contract TripFundProxyTest is Test {
    MockToken internal token;
    TripFundV1 internal implementation;
    TripFundV1 internal fund; // = прокси, приведённый к ABI TripFundV1
    ProxyAdmin internal proxyAdmin;

    address internal adminOwner = makeAddr("adminOwner");
    address internal organizer = makeAddr("organizer");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal attacker = makeAddr("attacker");

    uint256 internal constant GOAL = 100 ether;
    uint256 internal deadline;

    function setUp() public {
        deadline = block.timestamp + 7 days;
        token = new MockToken();
        implementation = new TripFundV1();

        fund = _deployProxy(address(token), organizer, GOAL, deadline);
        proxyAdmin = ProxyAdmin(_adminOf(address(fund)));

        token.mint(alice, 1_000 ether);
        token.mint(bob, 1_000 ether);
        // spender — адрес ПРОКСИ
        vm.prank(alice);
        token.approve(address(fund), type(uint256).max);
        vm.prank(bob);
        token.approve(address(fund), type(uint256).max);
    }

    function _deployProxy(address token_, address organizer_, uint256 goal_, uint256 deadline_)
        internal
        returns (TripFundV1)
    {
        bytes memory initData = abi.encodeCall(TripFundV1.initialize, (IERC20(token_), organizer_, goal_, deadline_));
        // OZ 5.x: прокси сам создаёт ProxyAdmin, владелец — adminOwner
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(implementation), adminOwner, initData);
        return TripFundV1(address(proxy));
    }

    function _adminOf(address proxy) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, ERC1967Utils.ADMIN_SLOT))));
    }

    function _implOf(address proxy) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, ERC1967Utils.IMPLEMENTATION_SLOT))));
    }

    // ---------------------------------------------------------------------
    // Инициализация
    // ---------------------------------------------------------------------
    function test_Proxy_InitializedParams() public view {
        assertEq(address(fund.token()), address(token));
        assertEq(fund.organizer(), organizer);
        assertEq(fund.goal(), GOAL);
        assertEq(fund.deadline(), deadline);
        assertEq(fund.version(), "1");
        assertEq(_implOf(address(fund)), address(implementation));
        assertEq(proxyAdmin.owner(), adminOwner);
    }

    function test_Proxy_RevertReinitialize() public {
        vm.prank(attacker);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        fund.initialize(IERC20(address(token)), attacker, 1, block.timestamp + 1);
        assertEq(fund.organizer(), organizer);
    }

    function test_Implementation_RevertDirectInitialize() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementation.initialize(IERC20(address(token)), attacker, 1, block.timestamp + 1);
    }

    function test_Proxy_RevertInvalidParams() public {
        vm.expectRevert(TripFundV1.ZeroAddress.selector);
        _deployProxy(address(0), organizer, GOAL, deadline);

        vm.expectRevert(TripFundV1.ZeroAddress.selector);
        _deployProxy(address(token), address(0), GOAL, deadline);

        vm.expectRevert(TripFundV1.ZeroGoal.selector);
        _deployProxy(address(token), organizer, 0, deadline);

        vm.expectRevert(TripFundV1.DeadlineNotInFuture.selector);
        _deployProxy(address(token), organizer, GOAL, block.timestamp);
    }

    // ---------------------------------------------------------------------
    // Работа через прокси
    // ---------------------------------------------------------------------
    function test_Proxy_ContributeAndWithdraw() public {
        vm.prank(alice);
        fund.contribute(60 ether);
        vm.prank(bob);
        fund.contribute(40 ether);

        assertEq(token.balanceOf(address(fund)), GOAL, "tokens are held by the proxy");
        assertEq(token.balanceOf(address(implementation)), 0);

        vm.warp(deadline);
        vm.prank(organizer);
        fund.withdraw();
        assertEq(token.balanceOf(organizer), GOAL);
    }

    function test_Proxy_Refund() public {
        vm.prank(alice);
        fund.contribute(10 ether);
        vm.warp(deadline);
        vm.prank(alice);
        fund.refund();
        assertEq(token.balanceOf(alice), 1_000 ether);
    }

    // ---------------------------------------------------------------------
    // Обновление: только владелец ProxyAdmin
    // ---------------------------------------------------------------------
    function test_Upgrade_RevertNotProxyAdminOwner() public {
        TripFundV1 newImpl = new TripFundV1();

        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(fund)), address(newImpl), "");

        // организатор фонда тоже не может
        vm.prank(organizer);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, organizer));
        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(fund)), address(newImpl), "");

        assertEq(_implOf(address(fund)), address(implementation));
    }

    function test_Upgrade_ByOwner_KeepsState() public {
        vm.prank(alice);
        fund.contribute(30 ether);

        TripFundV1 newImpl = new TripFundV1();
        address proxyAddr = address(fund);

        vm.prank(adminOwner);
        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(proxyAddr), address(newImpl), "");

        assertEq(_implOf(proxyAddr), address(newImpl));
        assertEq(address(fund), proxyAddr, "same address");
        assertEq(fund.organizer(), organizer);
        assertEq(fund.goal(), GOAL);
        assertEq(fund.deadline(), deadline);
        assertEq(fund.contributions(alice), 30 ether);
        assertEq(fund.totalRaised(), 30 ether);
        assertEq(token.balanceOf(proxyAddr), 30 ether);

        // после обновления повторная инициализация всё равно запрещена
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        fund.initialize(IERC20(address(token)), attacker, 1, block.timestamp + 1);
    }
}
