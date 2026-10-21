// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title TripFund — сбор на поездку команды в одном ERC-20
/// @notice Взносы до дедлайна; после дедлайна — либо один вывод организатору (цель достигнута),
///         либо индивидуальные возвраты вкладчикам (цель не достигнута).
contract TripFund {
    using SafeERC20 for IERC20;

    // ---------------------------------------------------------------------
    // Неизменяемые параметры (сеттеров нет)
    // ---------------------------------------------------------------------
    IERC20 public immutable token;
    address public immutable organizer;
    uint256 public immutable goal; // в минимальных единицах токена
    uint256 public immutable deadline; // Unix-время в секундах

    // ---------------------------------------------------------------------
    // Учёт
    // ---------------------------------------------------------------------
    /// @notice Текущий (ещё не возвращённый) вклад участника
    mapping(address => uint256) public contributions;
    /// @notice Сумма всех принятых взносов; после выплат не уменьшается
    uint256 public totalRaised;
    /// @notice Отметка, что организатор уже получил выплату
    bool public withdrawn;

    // ---------------------------------------------------------------------
    // События
    // ---------------------------------------------------------------------
    event Contributed(address indexed contributor, uint256 amount);
    event Refunded(address indexed contributor, uint256 amount);
    event Withdrawn(address indexed organizer, uint256 amount);

    // ---------------------------------------------------------------------
    // Ошибки
    // ---------------------------------------------------------------------
    error ZeroAddress();
    error ZeroGoal();
    error DeadlineNotInFuture();
    error ZeroAmount();
    error DeadlinePassed();
    error DeadlineNotReached();
    error NotOrganizer();
    error GoalNotReached();
    error GoalReached();
    error AlreadyWithdrawn();
    error NothingToRefund();

    constructor(IERC20 token_, address organizer_, uint256 goal_, uint256 deadline_) {
        if (address(token_) == address(0) || organizer_ == address(0)) revert ZeroAddress();
        if (goal_ == 0) revert ZeroGoal();
        if (deadline_ <= block.timestamp) revert DeadlineNotInFuture();

        token = token_;
        organizer = organizer_;
        goal = goal_;
        deadline = deadline_;
    }

    /// @notice Внести `amount` токенов. Перед вызовом нужен token.approve(address(this), amount).
    function contribute(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        if (block.timestamp >= deadline) revert DeadlinePassed();

        // Эффекты до взаимодействия: при неудачном переводе весь вызов откатится.
        contributions[msg.sender] += amount;
        totalRaised += amount;

        token.safeTransferFrom(msg.sender, address(this), amount);

        emit Contributed(msg.sender, amount);
    }

    /// @notice Вывод всей учтённой суммы организатору — один раз, после дедлайна, при успехе.
    function withdraw() external {
        if (msg.sender != organizer) revert NotOrganizer();
        if (block.timestamp < deadline) revert DeadlineNotReached();
        if (totalRaised < goal) revert GoalNotReached();
        if (withdrawn) revert AlreadyWithdrawn();

        withdrawn = true; // отмечаем выплату до внешнего вызова
        uint256 amount = totalRaised;

        token.safeTransfer(organizer, amount);

        emit Withdrawn(organizer, amount);
    }

    /// @notice Возврат своего полного вклада — после дедлайна, если цель не достигнута.
    function refund() external {
        if (block.timestamp < deadline) revert DeadlineNotReached();
        if (totalRaised >= goal) revert GoalReached();

        uint256 amount = contributions[msg.sender];
        if (amount == 0) revert NothingToRefund();

        contributions[msg.sender] = 0; // обнуляем вклад до внешнего вызова

        token.safeTransfer(msg.sender, amount);

        emit Refunded(msg.sender, amount);
    }
}
