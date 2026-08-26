// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {UniswapV3Adapter} from "../contracts/UniswapV3Adapter.sol";
import {TestBase} from "./TestBase.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockPositionManager} from "./mocks/MockPositionManager.sol";

contract UniswapV3AdapterTest is TestBase {
    MockERC20 internal token0;
    MockERC20 internal token1;
    MockPositionManager internal manager;
    UniswapV3Adapter internal adapter;

    function setUp() public {
        MockERC20 a = new MockERC20("A", "A");
        MockERC20 b = new MockERC20("B", "B");
        (token0, token1) = address(a) < address(b) ? (a, b) : (b, a);
        manager = new MockPositionManager();
        adapter = new UniswapV3Adapter(address(this), address(this), manager, 15 minutes);
        adapter.setPoolApproval(address(token0), address(token1), 500, true);
        token0.mint(address(this), 1_000);
        token1.mint(address(this), 1_000);
        token0.approve(address(adapter), type(uint256).max);
        token1.approve(address(adapter), type(uint256).max);
    }

    function params() internal view returns (UniswapV3Adapter.OpenParams memory) {
        return UniswapV3Adapter.OpenParams({
            token0: address(token0),
            token1: address(token1),
            fee: 500,
            tickLower: -120,
            tickUpper: 120,
            amount0Desired: 400,
            amount1Desired: 600,
            amount0Min: 390,
            amount1Min: 590,
            deadline: block.timestamp + 5 minutes
        });
    }

    function testOpensAndClosesPositionReturningAssets() public {
        (uint256 tokenId, uint128 liquidity,,) = adapter.openPosition(params());
        assertEq(tokenId, 1);
        assertEq(uint256(liquidity), 1_000);
        assertEq(token0.balanceOf(address(this)), 600);
        adapter.closePosition(tokenId, 390, 590, block.timestamp + 5 minutes);
        assertEq(token0.balanceOf(address(this)), 1_000);
        assertEq(token1.balanceOf(address(this)), 1_000);
    }

    function testRejectsUnapprovedFeeTier() public {
        UniswapV3Adapter.OpenParams memory input = params();
        input.fee = 3_000;
        vm.expectRevert(UniswapV3Adapter.PoolNotApproved.selector);
        adapter.openPosition(input);
    }

    function testRejectsExcessiveDeadline() public {
        UniswapV3Adapter.OpenParams memory input = params();
        input.deadline = block.timestamp + 16 minutes;
        vm.expectRevert(UniswapV3Adapter.InvalidDeadline.selector);
        adapter.openPosition(input);
    }
}
