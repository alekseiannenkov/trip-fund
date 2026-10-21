// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

/// @title TripFundV1 — обновляемая версия TripFund (бонус, п. 10)
/// @notice Разворачивается за TransparentUpgradeableProxy (OpenZeppelin 5.x).
///         Параметры лежат в storage и задаются один раз через initialize().
contract TripFundV1 is Initializable {
    using SafeERC20 for IERC20;

    // ---------------------------------------------------------------------
    // Storage. ВАЖНО для будущих версий: порядок не менять, новые
    // переменные добавлять только в конец.
    // ---------------------------------------------------------------------
    IERC20 public token; // slot 0
    address public organizer; // slot 1
    uint256 public goal; // slot 2
    uint256 public deadline; // slot 3
    mapping(address => uint256) public contributions; // slot 4
    uint256 public totalRaised; // slot 5
    bool public withdrawn; // slot 6

    event Contributed(address indexed contributor, uint256 amount);
    event Refunded(address indexed contributor, uint256 amount);
    event Withdrawn(address indexed organizer, uint256 amount);

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

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        // Запрещаем прямую инициализацию самой реализации.
        _disableInitializers();
    }

    /// @notice Вызывается один раз при создании прокси.
    function initialize(IERC20 token_, address organizer_, uint256 goal_, uint256 deadline_) external initializer {
        if (address(token_) == address(0) || organizer_ == address(0)) revert ZeroAddress();
        if (goal_ == 0) revert ZeroGoal();
        if (deadline_ <= block.timestamp) revert DeadlineNotInFuture();

        token = token_;
        organizer = organizer_;
        goal = goal_;
        deadline = deadline_;
    }

    function version() external pure virtual returns (string memory) {
        return "1";
    }

    function contribute(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        if (block.timestamp >= deadline) revert DeadlinePassed();

        contributions[msg.sender] += amount;
        totalRaised += amount;

        token.safeTransferFrom(msg.sender, address(this), amount);

        emit Contributed(msg.sender, amount);
    }

    function withdraw() external {
        if (msg.sender != organizer) revert NotOrganizer();
        if (block.timestamp < deadline) revert DeadlineNotReached();
        if (totalRaised < goal) revert GoalNotReached();
        if (withdrawn) revert AlreadyWithdrawn();

        withdrawn = true;
        uint256 amount = totalRaised;

        token.safeTransfer(organizer, amount);

        emit Withdrawn(organizer, amount);
    }

    function refund() external {
        if (block.timestamp < deadline) revert DeadlineNotReached();
        if (totalRaised >= goal) revert GoalReached();

        uint256 amount = contributions[msg.sender];
        if (amount == 0) revert NothingToRefund();

        contributions[msg.sender] = 0;

        token.safeTransfer(msg.sender, amount);

        emit Refunded(msg.sender, amount);
    }
}
