// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {ThunderLoan} from "./vendor/protocol/ThunderLoan.sol";
import {AssetToken} from "./vendor/protocol/AssetToken.sol";
import {MockToken} from "./mocks/MockToken.sol";
import {ManipulablePool, ManipulableFactory} from "./mocks/ManipulablePool.sol";

/// @notice M-02: getCalculatedFee prices the loan using the AMM spot price
///         (IPoolFactory.getPool(token).getPriceOfOnePoolTokenInWeth()).
///         Spot prices are manipulable within a single transaction — a swap
///         that drops the price before flashloan cuts the fee proportionally.
///         The attacker pays for the swap, but for large loans the fee
///         reduction dominates the swap cost.
contract M02OracleManipulation is Test {
    ThunderLoan internal tl;
    AssetToken internal assetToken;
    MockToken internal token;
    ManipulableFactory internal factory;
    ManipulablePool internal pool;

    function setUp() public {
        factory = new ManipulableFactory();
        token = new MockToken();
        pool = new ManipulablePool();
        factory.setPool(address(token), address(pool));

        ThunderLoan impl = new ThunderLoan();
        ERC1967Proxy proxy =
            new ERC1967Proxy(address(impl), abi.encodeWithSignature("initialize(address)", address(factory)));
        tl = ThunderLoan(address(proxy));
        assetToken = tl.setAllowedToken(token, true);
    }

    function test_ManipulatedSpotPriceReducesFlashLoanFee() public {
        uint256 amount = 1_000 ether;

        // Baseline fee at the honest price (1e18)
        uint256 feeAtPar = tl.getCalculatedFee(token, amount);
        assertEq(feeAtPar, 3 ether, "0.3% fee at price 1e18");

        // Attacker swaps in the pool to push price down 10x (simulated via
        // the mock's setPrice — a real pool would get this from an AMM swap
        // in the same transaction).
        pool.setPrice(1e17);

        uint256 feeManipulated = tl.getCalculatedFee(token, amount);
        assertEq(feeManipulated, 0.3 ether, "fee dropped 10x with manipulated price");
        assertLt(feeManipulated, feeAtPar, "attacker reduced the fee by manipulating the oracle");
    }
}
