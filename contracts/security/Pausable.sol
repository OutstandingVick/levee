// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

abstract contract Pausable {
    error ContractPaused();

    bool public paused;

    event PauseStateChanged(bool paused);

    modifier whenNotPaused() {
        if (paused) revert ContractPaused();
        _;
    }

    function _setPaused(bool value) internal {
        paused = value;
        emit PauseStateChanged(value);
    }
}
