// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

abstract contract ReentrancyGuard {
    error ReentrantCall();

    uint256 private locked = 1;

    modifier nonReentrant() {
        if (locked != 1) revert ReentrantCall();
        locked = 2;
        _;
        locked = 1;
    }
}
