// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

library SafeTransferLib {
    error TokenCallFailed();

    function safeTransfer(address token, address to, uint256 amount) internal {
        (bool success, bytes memory result) =
            token.call(abi.encodeWithSignature("transfer(address,uint256)", to, amount));
        if (!success || (result.length != 0 && !abi.decode(result, (bool)))) {
            revert TokenCallFailed();
        }
    }

    function safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        (bool success, bytes memory result) = token.call(
            abi.encodeWithSignature("transferFrom(address,address,uint256)", from, to, amount)
        );
        if (!success || (result.length != 0 && !abi.decode(result, (bool)))) {
            revert TokenCallFailed();
        }
    }

    function forceApprove(address token, address spender, uint256 amount) internal {
        (bool success, bytes memory result) =
            token.call(abi.encodeWithSignature("approve(address,uint256)", spender, amount));
        if (success && (result.length == 0 || abi.decode(result, (bool)))) return;
        (success,) = token.call(abi.encodeWithSignature("approve(address,uint256)", spender, 0));
        if (!success) revert TokenCallFailed();
        (success, result) =
            token.call(abi.encodeWithSignature("approve(address,uint256)", spender, amount));
        if (!success || (result.length != 0 && !abi.decode(result, (bool)))) {
            revert TokenCallFailed();
        }
    }
}
