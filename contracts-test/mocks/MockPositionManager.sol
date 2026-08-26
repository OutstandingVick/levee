// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "../../contracts/interfaces/IERC20.sol";
import {
    INonfungiblePositionManager
} from "../../contracts/interfaces/INonfungiblePositionManager.sol";

contract MockPositionManager is INonfungiblePositionManager {
    struct Stored {
        address token0;
        address token1;
        uint256 amount0;
        uint256 amount1;
        uint128 liquidity;
    }
    uint256 public nextTokenId = 1;
    mapping(uint256 => Stored) public stored;

    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        tokenId = nextTokenId++;
        amount0 = params.amount0Desired;
        amount1 = params.amount1Desired;
        liquidity = uint128(amount0 + amount1);
        IERC20(params.token0).transferFrom(msg.sender, address(this), amount0);
        IERC20(params.token1).transferFrom(msg.sender, address(this), amount1);
        stored[tokenId] = Stored(params.token0, params.token1, amount0, amount1, liquidity);
    }

    function decreaseLiquidity(DecreaseLiquidityParams calldata params)
        external
        payable
        returns (uint256 amount0, uint256 amount1)
    {
        Stored storage item = stored[params.tokenId];
        item.liquidity = 0;
        return (item.amount0, item.amount1);
    }

    function collect(CollectParams calldata params)
        external
        payable
        returns (uint256 amount0, uint256 amount1)
    {
        Stored storage item = stored[params.tokenId];
        amount0 = item.amount0;
        amount1 = item.amount1;
        item.amount0 = 0;
        item.amount1 = 0;
        IERC20(item.token0).transfer(params.recipient, amount0);
        IERC20(item.token1).transfer(params.recipient, amount1);
    }

    function burn(uint256 tokenId) external payable {
        delete stored[tokenId];
    }
}
