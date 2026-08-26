// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Owned} from "./security/Owned.sol";

contract PositionRegistry is Owned {
    error NotOperator();
    error PositionAlreadyExists();
    error PositionNotActive();
    error ReturnedPrincipalExceeded();

    struct Position {
        address adapter;
        address asset;
        uint256 externalId;
        uint256 principal;
        uint256 returnedPrincipal;
        uint48 openedAt;
        uint48 closedAt;
        bool active;
    }

    address public operator;
    mapping(bytes32 positionKey => Position position) public positions;

    event OperatorChanged(address indexed previousOperator, address indexed newOperator);
    event PositionOpened(
        bytes32 indexed key, address indexed adapter, uint256 externalId, uint256 principal
    );
    event PositionClosed(bytes32 indexed key, uint256 returnedPrincipal, int256 realizedPnl);

    constructor(address initialOwner) Owned(initialOwner) {}

    modifier onlyOperator() {
        if (msg.sender != operator) revert NotOperator();
        _;
    }

    function setOperator(address nextOperator) external onlyOwner {
        emit OperatorChanged(operator, nextOperator);
        operator = nextOperator;
    }

    function openPosition(
        bytes32 key,
        address adapter,
        address asset,
        uint256 externalId,
        uint256 principal
    ) external onlyOperator {
        if (positions[key].openedAt != 0) revert PositionAlreadyExists();
        positions[key] =
            Position(adapter, asset, externalId, principal, 0, uint48(block.timestamp), 0, true);
        emit PositionOpened(key, adapter, externalId, principal);
    }

    function closePosition(bytes32 key, uint256 returnedPrincipal) external onlyOperator {
        Position storage position = positions[key];
        if (!position.active) revert PositionNotActive();
        if (returnedPrincipal > type(uint256).max - position.returnedPrincipal) {
            revert ReturnedPrincipalExceeded();
        }
        position.returnedPrincipal += returnedPrincipal;
        position.closedAt = uint48(block.timestamp);
        position.active = false;
        int256 pnl = returnedPrincipal >= position.principal
            ? int256(returnedPrincipal - position.principal)
            : -int256(position.principal - returnedPrincipal);
        emit PositionClosed(key, returnedPrincipal, pnl);
    }
}
