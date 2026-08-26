// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IAggregatorV3} from "./interfaces/IAggregatorV3.sol";
import {Owned} from "./security/Owned.sol";

contract ValuationOracle is Owned {
    error FeedNotConfigured();
    error InvalidPrice();
    error StalePrice();
    error UnsupportedDecimals();

    struct FeedConfig {
        IAggregatorV3 feed;
        uint8 tokenDecimals;
        uint48 maximumAge;
    }

    mapping(address token => FeedConfig config) public feeds;
    event FeedConfigured(
        address indexed token, address indexed feed, uint8 tokenDecimals, uint48 maximumAge
    );

    constructor(address initialOwner) Owned(initialOwner) {}

    function setFeed(address token, IAggregatorV3 feed, uint8 tokenDecimals, uint48 maximumAge)
        external
        onlyOwner
    {
        if (token == address(0) || address(feed) == address(0)) revert ZeroAddress();
        if (tokenDecimals > 18 || feed.decimals() > 18 || maximumAge == 0) {
            revert UnsupportedDecimals();
        }
        feeds[token] = FeedConfig(feed, tokenDecimals, maximumAge);
        emit FeedConfigured(token, address(feed), tokenDecimals, maximumAge);
    }

    function usdValue(address token, uint256 amount) external view returns (uint256 valueUsd18) {
        FeedConfig memory config = feeds[token];
        if (address(config.feed) == address(0)) revert FeedNotConfigured();
        (, int256 answer,, uint256 updatedAt,) = config.feed.latestRoundData();
        if (answer <= 0 || updatedAt == 0 || updatedAt > block.timestamp) revert InvalidPrice();
        if (block.timestamp - updatedAt > config.maximumAge) revert StalePrice();
        uint256 priceUsd18 = uint256(answer) * 10 ** (18 - config.feed.decimals());
        valueUsd18 = amount * priceUsd18 / 10 ** config.tokenDecimals;
    }
}
