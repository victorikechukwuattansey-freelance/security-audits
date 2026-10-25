// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/// @dev Pool whose price is settable by anyone — models an AMM spot price
///      that can be moved within a single transaction. Used only for M-02.
contract ManipulablePool {
    uint256 public price = 1e18;

    function setPrice(uint256 newPrice) external {
        price = newPrice;
    }

    function getPriceOfOnePoolTokenInWeth() external view returns (uint256) {
        return price;
    }
}

/// @dev Factory returning the manipulable pool for any registered token.
contract ManipulableFactory {
    mapping(address => address) public poolOf;

    function setPool(address token, address pool) external {
        poolOf[token] = pool;
    }

    function getPool(address token) external view returns (address) {
        return poolOf[token];
    }
}
