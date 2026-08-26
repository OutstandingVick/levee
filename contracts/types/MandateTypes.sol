// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

library MandateTypes {
    uint16 internal constant BPS = 10_000;

    struct Mandate {
        address reserveToken;
        uint256 reserveFloor;
        uint16 maximumStressLossBps;
        uint16 maximumPoolAllocationBps;
        uint48 rebalanceCooldown;
        uint48 validUntil;
    }

    struct Action {
        address asset;
        address target;
        bytes4 selector;
        uint256 amount;
        uint256 existingPoolAllocation;
        uint256 totalManagedAssets;
        uint256 reserveBalanceAfter;
        uint256 projectedStressLossBps;
    }
}
