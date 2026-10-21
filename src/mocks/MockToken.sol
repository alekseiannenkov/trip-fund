// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Обычный ERC-20 для локальных тестов: без комиссии за перевод и без rebasing.
contract MockToken is ERC20 {
    constructor() ERC20("Trip Token", "TRIP") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
