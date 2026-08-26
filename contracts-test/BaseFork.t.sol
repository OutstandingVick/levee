// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {TestBase} from "./TestBase.sol";

contract BaseForkTest is TestBase {
    function testBaseSepoliaConfiguredContractsHaveCode() public {
        string memory rpcUrl = vm.envOr("BASE_SEPOLIA_RPC_URL", string(""));
        address manager = vm.envOr("UNISWAP_POSITION_MANAGER", address(0));
        if (bytes(rpcUrl).length == 0 || manager == address(0)) return;
        vm.createSelectFork(rpcUrl);
        assertTrue(manager.code.length > 0);
    }
}
