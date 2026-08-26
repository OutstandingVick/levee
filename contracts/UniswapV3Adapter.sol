// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "./interfaces/IERC20.sol";
import {IERC721Receiver} from "./interfaces/IERC721Receiver.sol";
import {INonfungiblePositionManager} from "./interfaces/INonfungiblePositionManager.sol";
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";
import {Owned} from "./security/Owned.sol";
import {ReentrancyGuard} from "./security/ReentrancyGuard.sol";

contract UniswapV3Adapter is Owned, ReentrancyGuard, IERC721Receiver {
    using SafeTransferLib for address;

    error NotVault();
    error PoolNotApproved();
    error InvalidRange();
    error InvalidDeadline();
    error UnknownPosition();
    error UnexpectedNft();

    struct OpenParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    struct Position {
        address token0;
        address token1;
        uint128 liquidity;
        bool active;
    }

    address public immutable vault;
    INonfungiblePositionManager public immutable positionManager;
    uint48 public immutable maximumDeadlineWindow;
    mapping(bytes32 poolKey => bool approved) public approvedPools;
    mapping(uint256 tokenId => Position position) public positions;

    event PoolApprovalChanged(
        address indexed token0, address indexed token1, uint24 fee, bool approved
    );
    event PositionOpened(
        uint256 indexed tokenId, uint128 liquidity, uint256 amount0, uint256 amount1
    );
    event PositionClosed(uint256 indexed tokenId, uint256 amount0, uint256 amount1);

    constructor(
        address initialOwner,
        address vaultAddress,
        INonfungiblePositionManager manager,
        uint48 deadlineWindow
    ) Owned(initialOwner) {
        if (vaultAddress == address(0) || address(manager) == address(0)) revert ZeroAddress();
        vault = vaultAddress;
        positionManager = manager;
        maximumDeadlineWindow = deadlineWindow;
    }

    modifier onlyVault() {
        if (msg.sender != vault) revert NotVault();
        _;
    }

    function setPoolApproval(address token0, address token1, uint24 fee, bool approved)
        external
        onlyOwner
    {
        approvedPools[_poolKey(token0, token1, fee)] = approved;
        emit PoolApprovalChanged(token0, token1, fee, approved);
    }

    function openPosition(OpenParams calldata params)
        external
        onlyVault
        nonReentrant
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        if (!approvedPools[_poolKey(params.token0, params.token1, params.fee)]) {
            revert PoolNotApproved();
        }
        if (params.token0 >= params.token1 || params.tickLower >= params.tickUpper) {
            revert InvalidRange();
        }
        if (
            params.deadline < block.timestamp
                || params.deadline > block.timestamp + maximumDeadlineWindow
        ) {
            revert InvalidDeadline();
        }
        params.token0.safeTransferFrom(vault, address(this), params.amount0Desired);
        params.token1.safeTransferFrom(vault, address(this), params.amount1Desired);
        params.token0.forceApprove(address(positionManager), params.amount0Desired);
        params.token1.forceApprove(address(positionManager), params.amount1Desired);
        (tokenId, liquidity, amount0, amount1) = positionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: params.token0,
                token1: params.token1,
                fee: params.fee,
                tickLower: params.tickLower,
                tickUpper: params.tickUpper,
                amount0Desired: params.amount0Desired,
                amount1Desired: params.amount1Desired,
                amount0Min: params.amount0Min,
                amount1Min: params.amount1Min,
                recipient: address(this),
                deadline: params.deadline
            })
        );
        params.token0.forceApprove(address(positionManager), 0);
        params.token1.forceApprove(address(positionManager), 0);
        if (params.amount0Desired > amount0) {
            params.token0.safeTransfer(vault, params.amount0Desired - amount0);
        }
        if (params.amount1Desired > amount1) {
            params.token1.safeTransfer(vault, params.amount1Desired - amount1);
        }
        positions[tokenId] = Position(params.token0, params.token1, liquidity, true);
        emit PositionOpened(tokenId, liquidity, amount0, amount1);
    }

    function closePosition(
        uint256 tokenId,
        uint256 amount0Min,
        uint256 amount1Min,
        uint256 deadline
    ) external onlyVault nonReentrant returns (uint256 amount0, uint256 amount1) {
        Position storage position = positions[tokenId];
        if (!position.active) revert UnknownPosition();
        if (deadline < block.timestamp || deadline > block.timestamp + maximumDeadlineWindow) {
            revert InvalidDeadline();
        }
        positionManager.decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: tokenId,
                liquidity: position.liquidity,
                amount0Min: amount0Min,
                amount1Min: amount1Min,
                deadline: deadline
            })
        );
        (amount0, amount1) = positionManager.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: tokenId,
                recipient: vault,
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );
        positionManager.burn(tokenId);
        position.active = false;
        emit PositionClosed(tokenId, amount0, amount1);
    }

    function onERC721Received(address, address, uint256, bytes calldata)
        external
        view
        returns (bytes4)
    {
        if (msg.sender != address(positionManager)) revert UnexpectedNft();
        return IERC721Receiver.onERC721Received.selector;
    }

    function _poolKey(address token0, address token1, uint24 fee) internal pure returns (bytes32) {
        return keccak256(abi.encode(token0, token1, fee));
    }
}
