// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface Vm {
    function prank(address sender) external;
    function expectRevert(bytes4 selector) external;
    function expectRevert() external;
    function warp(uint256 timestamp) external;
    function addr(uint256 privateKey) external returns (address);
    function sign(uint256 privateKey, bytes32 digest)
        external
        returns (uint8 v, bytes32 r, bytes32 s);
}

abstract contract TestBase {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function assertEq(uint256 actual, uint256 expected) internal pure {
        require(actual == expected, "uint values differ");
    }

    function assertEq(address actual, address expected) internal pure {
        require(actual == expected, "address values differ");
    }

    function assertTrue(bool condition) internal pure {
        require(condition, "condition is false");
    }
}
