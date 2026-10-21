// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Токен, у которого transfer можно «сломать»: он вернёт false без перевода.
///         Нужен только для проверки, что SafeERC20 откатывает всю операцию.
contract FailingToken is ERC20 {
    bool public failTransfers;

    constructor() ERC20("Failing", "FAIL") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setFail(bool v) external {
        failTransfers = v;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (failTransfers) return false;
        return super.transfer(to, amount);
    }
}
