// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev Minimal ERC-20 for PoC tests. Inherits OZ ERC20 so it's
///      ABI-compatible with the `IERC20` parameters in ThunderLoan.
///      Not production — anyone can mint.
contract MockToken is ERC20 {
    constructor() ERC20("MockToken", "MCK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
