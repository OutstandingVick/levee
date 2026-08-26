// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {PolicyGuard} from "./PolicyGuard.sol";
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";
import {Owned} from "./security/Owned.sol";
import {Pausable} from "./security/Pausable.sol";
import {ReentrancyGuard} from "./security/ReentrancyGuard.sol";

contract MandateVault is Owned, Pausable, ReentrancyGuard {
    using SafeTransferLib for address;

    error ZeroAmount();

    PolicyGuard public immutable policyGuard;
    mapping(address token => uint256 amount) public totalDeposited;

    event Deposited(address indexed token, uint256 amount);

    constructor(address initialOwner, PolicyGuard guard) Owned(initialOwner) {
        if (address(guard) == address(0)) revert ZeroAddress();
        policyGuard = guard;
    }

    function deposit(address token, uint256 amount) external onlyOwner whenNotPaused nonReentrant {
        if (amount == 0) revert ZeroAmount();
        token.safeTransferFrom(msg.sender, address(this), amount);
        totalDeposited[token] += amount;
        emit Deposited(token, amount);
    }
}
