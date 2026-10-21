// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {TripFund} from "../src/TripFund.sol";
import {MockToken} from "../src/mocks/MockToken.sol";

contract TripFundTest is Test {
    MockToken internal token;
    TripFund internal fund;

    address internal organizer = makeAddr("organizer");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol"); // без токенов
    address internal stranger = makeAddr("stranger");

    uint256 internal constant GOAL = 100 ether; // 100 TRIP (18 знаков)
    uint256 internal constant START_BALANCE = 1_000 ether;
    uint256 internal deadline;

    event Contributed(address indexed contributor, uint256 amount);
    event Refunded(address indexed contributor, uint256 amount);
    event Withdrawn(address indexed organizer, uint256 amount);

    function setUp() public {
        vm.warp(1_700_000_000);
        deadline = block.timestamp + 7 days;

        token = new MockToken();
        fund = new TripFund(IERC20(address(token)), organizer, GOAL, deadline);

        token.mint(alice, START_BALANCE);
        token.mint(bob, START_BALANCE);

        vm.prank(alice);
        token.approve(address(fund), type(uint256).max);
        vm.prank(bob);
        token.approve(address(fund), type(uint256).max);
    }

    // ---------------------------------------------------------------------
    // Хелперы
    // ---------------------------------------------------------------------
    function _contribute(address who, uint256 amount) internal {
        vm.prank(who);
        fund.contribute(amount);
    }

    /// Снимок учёта и балансов — для проверки «откат без изменений».
    struct Snapshot {
        uint256 total;
        uint256 contribAlice;
        uint256 contribCarol;
        uint256 balFund;
        uint256 balAlice;
        uint256 balCarol;
    }

    function _snap() internal view returns (Snapshot memory s) {
        s.total = fund.totalRaised();
        s.contribAlice = fund.contributions(alice);
        s.contribCarol = fund.contributions(carol);
        s.balFund = token.balanceOf(address(fund));
        s.balAlice = token.balanceOf(alice);
        s.balCarol = token.balanceOf(carol);
    }

    function _assertSame(Snapshot memory a, Snapshot memory b) internal pure {
        assertEq(a.total, b.total, "totalRaised changed");
        assertEq(a.contribAlice, b.contribAlice, "alice contribution changed");
        assertEq(a.contribCarol, b.contribCarol, "carol contribution changed");
        assertEq(a.balFund, b.balFund, "fund balance changed");
        assertEq(a.balAlice, b.balAlice, "alice balance changed");
        assertEq(a.balCarol, b.balCarol, "carol balance changed");
    }

    // ---------------------------------------------------------------------
    // 1. Конструктор
    // ---------------------------------------------------------------------
    function test_Constructor_SetsParams() public view {
        assertEq(address(fund.token()), address(token));
        assertEq(fund.organizer(), organizer);
        assertEq(fund.goal(), GOAL);
        assertEq(fund.deadline(), deadline);
        assertEq(fund.totalRaised(), 0);
        assertFalse(fund.withdrawn());
    }

    function test_Constructor_RevertZeroToken() public {
        vm.expectRevert(TripFund.ZeroAddress.selector);
        new TripFund(IERC20(address(0)), organizer, GOAL, deadline);
    }

    function test_Constructor_RevertZeroOrganizer() public {
        vm.expectRevert(TripFund.ZeroAddress.selector);
        new TripFund(IERC20(address(token)), address(0), GOAL, deadline);
    }

    function test_Constructor_RevertZeroGoal() public {
        vm.expectRevert(TripFund.ZeroGoal.selector);
        new TripFund(IERC20(address(token)), organizer, 0, deadline);
    }

    function test_Constructor_RevertDeadlineNow() public {
        vm.expectRevert(TripFund.DeadlineNotInFuture.selector);
        new TripFund(IERC20(address(token)), organizer, GOAL, block.timestamp);
    }

    function test_Constructor_RevertDeadlineInPast() public {
        vm.expectRevert(TripFund.DeadlineNotInFuture.selector);
        new TripFund(IERC20(address(token)), organizer, GOAL, block.timestamp - 1);
    }

    // ---------------------------------------------------------------------
    // 6. Два участника, повторные взносы, ошибочные взносы
    // ---------------------------------------------------------------------
    function test_TwoContributorsAndRepeatedContributions() public {
        _contribute(alice, 10 ether);
        _contribute(bob, 25 ether);
        _contribute(alice, 5 ether); // повторный взнос суммируется

        assertEq(fund.contributions(alice), 15 ether);
        assertEq(fund.contributions(bob), 25 ether);
        assertEq(fund.totalRaised(), 40 ether);

        assertEq(token.balanceOf(address(fund)), 40 ether);
        assertEq(token.balanceOf(alice), START_BALANCE - 15 ether);
        assertEq(token.balanceOf(bob), START_BALANCE - 25 ether);
    }

    function test_Contribute_EmitsEvent() public {
        vm.expectEmit(true, false, false, true, address(fund));
        emit Contributed(alice, 7 ether);
        _contribute(alice, 7 ether);
    }

    function test_Contribute_RevertZeroAmount() public {
        _contribute(alice, 1 ether);
        Snapshot memory before = _snap();

        vm.prank(alice);
        vm.expectRevert(TripFund.ZeroAmount.selector);
        fund.contribute(0);

        _assertSame(before, _snap());
    }

    function test_Contribute_RevertInsufficientBalance() public {
        // carol разрешила списание, но токенов у неё нет
        vm.prank(carol);
        token.approve(address(fund), 10 ether);
        Snapshot memory before = _snap();

        vm.prank(carol);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, carol, 0, 10 ether));
        fund.contribute(10 ether);

        _assertSame(before, _snap());
    }

    function test_Contribute_RevertInsufficientAllowance() public {
        // у carol есть токены, но approve меньше суммы
        token.mint(carol, 50 ether);
        vm.prank(carol);
        token.approve(address(fund), 5 ether);
        Snapshot memory before = _snap();

        vm.prank(carol);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(fund), 5 ether, 10 ether)
        );
        fund.contribute(10 ether);

        _assertSame(before, _snap());
    }

    function test_Contribute_RevertWithoutApprove() public {
        token.mint(carol, 50 ether);
        Snapshot memory before = _snap();

        vm.prank(carol);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(fund), 0, 1 ether)
        );
        fund.contribute(1 ether);

        _assertSame(before, _snap());
    }

    // ---------------------------------------------------------------------
    // 7. Граница дедлайна; выплаты до срока запрещены
    // ---------------------------------------------------------------------
    function test_Contribute_OneSecondBeforeDeadline() public {
        vm.warp(deadline - 1);
        _contribute(alice, 1 ether);
        assertEq(fund.totalRaised(), 1 ether);
    }

    function test_Contribute_RevertExactlyAtDeadline() public {
        vm.warp(deadline);
        vm.prank(alice);
        vm.expectRevert(TripFund.DeadlinePassed.selector);
        fund.contribute(1 ether);
    }

    function test_Contribute_RevertAfterDeadline() public {
        vm.warp(deadline + 1 days);
        vm.prank(alice);
        vm.expectRevert(TripFund.DeadlinePassed.selector);
        fund.contribute(1 ether);
    }

    function test_Withdraw_RevertBeforeDeadline_EvenIfGoalReached() public {
        _contribute(alice, GOAL);
        assertGe(fund.totalRaised(), fund.goal());

        vm.warp(deadline - 1);
        vm.prank(organizer);
        vm.expectRevert(TripFund.DeadlineNotReached.selector);
        fund.withdraw();
    }

    function test_Refund_RevertBeforeDeadline() public {
        _contribute(alice, 10 ether);

        vm.warp(deadline - 1);
        vm.prank(alice);
        vm.expectRevert(TripFund.DeadlineNotReached.selector);
        fund.refund();
    }

    // ---------------------------------------------------------------------
    // 8. Успех: вывод организатору
    // ---------------------------------------------------------------------
    function test_Withdraw_ExactlyGoal() public {
        _contribute(alice, 60 ether);
        _contribute(bob, 40 ether); // ровно GOAL

        vm.warp(deadline);
        vm.expectEmit(true, false, false, true, address(fund));
        emit Withdrawn(organizer, GOAL);
        vm.prank(organizer);
        fund.withdraw();

        assertEq(token.balanceOf(organizer), GOAL);
        assertEq(token.balanceOf(address(fund)), 0);
        assertTrue(fund.withdrawn());
        assertEq(fund.totalRaised(), GOAL, "totalRaised must not decrease");
    }

    function test_Withdraw_AboveGoal() public {
        _contribute(alice, 80 ether);
        _contribute(bob, 70 ether); // 150 > GOAL

        vm.warp(deadline + 1);
        vm.prank(organizer);
        fund.withdraw();

        assertEq(token.balanceOf(organizer), 150 ether);
        assertEq(token.balanceOf(address(fund)), 0);
        assertEq(fund.totalRaised(), 150 ether);
    }

    function test_Withdraw_RevertNotOrganizer() public {
        _contribute(alice, GOAL);
        vm.warp(deadline);

        vm.prank(stranger);
        vm.expectRevert(TripFund.NotOrganizer.selector);
        fund.withdraw();

        vm.prank(alice); // даже вкладчик
        vm.expectRevert(TripFund.NotOrganizer.selector);
        fund.withdraw();
    }

    function test_Withdraw_RevertTwice() public {
        _contribute(alice, GOAL);
        vm.warp(deadline);

        vm.prank(organizer);
        fund.withdraw();

        vm.prank(organizer);
        vm.expectRevert(TripFund.AlreadyWithdrawn.selector);
        fund.withdraw();

        assertEq(token.balanceOf(organizer), GOAL);
    }

    function test_Refund_RevertOnSuccess() public {
        _contribute(alice, 60 ether);
        _contribute(bob, 40 ether);
        vm.warp(deadline);

        vm.prank(alice);
        vm.expectRevert(TripFund.GoalReached.selector);
        fund.refund();

        // и после вывода тоже
        vm.prank(organizer);
        fund.withdraw();
        vm.prank(bob);
        vm.expectRevert(TripFund.GoalReached.selector);
        fund.refund();
    }

    // ---------------------------------------------------------------------
    // 8. Провал: независимые возвраты
    // ---------------------------------------------------------------------
    function test_Refund_BelowGoal_Independent() public {
        _contribute(alice, 30 ether);
        _contribute(bob, 20 ether);
        _contribute(alice, 10 ether); // alice = 40, bob = 20, total = 60 < GOAL

        vm.warp(deadline);

        vm.expectEmit(true, false, false, true, address(fund));
        emit Refunded(bob, 20 ether);
        vm.prank(bob);
        fund.refund();

        assertEq(token.balanceOf(bob), START_BALANCE);
        assertEq(fund.contributions(bob), 0);
        assertEq(fund.contributions(alice), 40 ether, "alice untouched");
        assertEq(token.balanceOf(address(fund)), 40 ether);

        vm.prank(alice);
        fund.refund();

        assertEq(token.balanceOf(alice), START_BALANCE);
        assertEq(fund.contributions(alice), 0);
        assertEq(token.balanceOf(address(fund)), 0);
        assertEq(fund.totalRaised(), 60 ether, "totalRaised must not decrease");
    }

    function test_Refund_RevertTwice() public {
        _contribute(alice, 10 ether);
        vm.warp(deadline);

        vm.prank(alice);
        fund.refund();

        vm.prank(alice);
        vm.expectRevert(TripFund.NothingToRefund.selector);
        fund.refund();

        assertEq(token.balanceOf(alice), START_BALANCE);
    }

    function test_Refund_RevertWithoutContribution() public {
        _contribute(alice, 10 ether);
        vm.warp(deadline);

        vm.prank(stranger);
        vm.expectRevert(TripFund.NothingToRefund.selector);
        fund.refund();
    }

    function test_Withdraw_RevertOnFailure() public {
        _contribute(alice, GOAL - 1);
        vm.warp(deadline);

        vm.prank(organizer);
        vm.expectRevert(TripFund.GoalNotReached.selector);
        fund.withdraw();
    }

    // ---------------------------------------------------------------------
    // 9. Прямой перевод не учитывается и остаётся в контракте
    // ---------------------------------------------------------------------
    function test_DirectTransfer_NotCounted_Success() public {
        uint256 extra = 33 ether;
        vm.prank(alice);
        assertTrue(token.transfer(address(fund), extra));
        assertEq(fund.totalRaised(), 0);

        _contribute(alice, 60 ether);
        _contribute(bob, 40 ether);
        assertEq(fund.totalRaised(), GOAL);
        assertEq(token.balanceOf(address(fund)), GOAL + extra);

        vm.warp(deadline);
        vm.prank(organizer);
        fund.withdraw();

        assertEq(token.balanceOf(organizer), GOAL, "only accounted amount is paid");
        assertEq(token.balanceOf(address(fund)), extra, "direct transfer stays");
    }

    function test_DirectTransfer_NotCounted_Failure() public {
        uint256 extra = 33 ether;
        _contribute(alice, 30 ether);
        _contribute(bob, 20 ether);

        vm.prank(bob);
        assertTrue(token.transfer(address(fund), extra));
        assertEq(fund.totalRaised(), 50 ether);

        // Даже если прямой перевод «дотягивает» баланс до цели, исход — провал.
        vm.prank(alice);
        assertTrue(token.transfer(address(fund), 100 ether));
        extra += 100 ether;
        assertGe(token.balanceOf(address(fund)), GOAL);

        vm.warp(deadline);
        vm.prank(organizer);
        vm.expectRevert(TripFund.GoalNotReached.selector);
        fund.withdraw();

        vm.prank(alice);
        fund.refund();
        vm.prank(bob);
        fund.refund();

        assertEq(token.balanceOf(address(fund)), extra, "direct transfers stay");
        assertEq(fund.totalRaised(), 50 ether);
    }

    // ---------------------------------------------------------------------
    // Fuzz: учёт = балансу контракта (без прямых переводов)
    // ---------------------------------------------------------------------
    function testFuzz_ContributionsSum(uint96 a, uint96 b) public {
        vm.assume(a > 0 && b > 0);
        token.mint(alice, a);
        token.mint(bob, b);
        _contribute(alice, a);
        _contribute(bob, b);

        assertEq(fund.totalRaised(), uint256(a) + b);
        assertEq(token.balanceOf(address(fund)), uint256(a) + b);
    }
}
