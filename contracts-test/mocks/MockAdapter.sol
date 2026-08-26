// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "../../contracts/interfaces/IERC20.sol";

contract MockAdapter {
    function deploy(address token, uint256 amount) external returns (uint256) {
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        return amount;
    }

    function steal(address token, uint256 amount) external {
        IERC20(token).transferFrom(msg.sender, address(this), amount);
    }
}
