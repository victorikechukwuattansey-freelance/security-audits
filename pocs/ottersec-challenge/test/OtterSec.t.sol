// test/OtterSec.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

contract OtterSecTest is Test {
    address constant CHALLENGE = 0xa60Fa8391625163b1760f89DAc94bac2C448f897;
    uint256 constant V = 0x66de8ffda797e3de9c05e8fc57b3bf0ec28a930d40b0d285d93c06501cf6a090;
    bytes32 constant C = 0xd135e49a5b56186fed6c69c6451f8bb83bb42e84b7a3fde2fa8fa4ee0a494636;

    function setUp() public {
        vm.createSelectFork("https://polygon-amoy-bor-rpc.publicnode.com");
    }

    function test_challenge() public {
        address caller = address(0xBEEF);
        vm.deal(caller, V);
        vm.prank(caller);
        (bool ok, ) = CHALLENGE.call{value: V}(abi.encode(C));
        assertTrue(ok, "challenge call reverted");
    }
}
