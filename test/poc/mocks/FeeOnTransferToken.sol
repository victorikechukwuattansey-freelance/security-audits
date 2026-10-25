// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev ERC-20 that charges a 1% fee on `transferFrom` (deposit path) but not
///      on `transfer` (redeem path). Models fee-on-transfer tokens where the
///      DEX pair is whitelisted and normal transfers are exempt — the class
///      that isolates the deposit-side accounting bug from redemption-side fees.
///      Used only for H-03 PoC.
contract FeeOnTransferToken is ERC20 {
    uint256 public constant FEE_BPS = 100; // 1%
    address public constant FEE_SINK = address(0xdEaD);

    constructor() ERC20("FeeOnTransferToken", "FOT") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        uint256 fee = (amount * FEE_BPS) / 10_000;
        if (fee > 0) {
            _transfer(from, FEE_SINK, fee);
        }
        _transfer(from, to, amount - fee);
        return true;
    }
}
