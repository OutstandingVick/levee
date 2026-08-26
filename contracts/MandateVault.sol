// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {PolicyGuard} from "./PolicyGuard.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";
import {Owned} from "./security/Owned.sol";
import {Pausable} from "./security/Pausable.sol";
import {ReentrancyGuard} from "./security/ReentrancyGuard.sol";
import {MandateTypes} from "./types/MandateTypes.sol";

contract MandateVault is Owned, Pausable, ReentrancyGuard {
    using SafeTransferLib for address;

    error ZeroAmount();
    error ReserveFloorBreached();

    PolicyGuard public immutable policyGuard;
    mapping(address token => uint256 amount) public totalDeposited;

    event Deposited(address indexed token, uint256 amount);
    event Withdrawn(address indexed token, uint256 amount, address indexed recipient);

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

    function withdraw(address token, uint256 amount, address recipient)
        external
        onlyOwner
        whenNotPaused
        nonReentrant
    {
        if (amount == 0) revert ZeroAmount();
        if (recipient == address(0)) revert ZeroAddress();
        MandateTypes.Mandate memory current = policyGuard.currentMandate();
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (token == current.reserveToken && balance - amount < current.reserveFloor) {
            revert ReserveFloorBreached();
        }
        totalDeposited[token] = totalDeposited[token] > amount ? totalDeposited[token] - amount : 0;
        token.safeTransfer(recipient, amount);
        emit Withdrawn(token, amount, recipient);
    }
}
