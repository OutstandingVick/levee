// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Owned} from "./security/Owned.sol";
import {MandateTypes} from "./types/MandateTypes.sol";

contract PolicyGuard is Owned {
    error InvalidMandate();

    MandateTypes.Mandate public mandate;
    uint64 public mandateVersion;

    event MandateUpdated(uint64 indexed version, MandateTypes.Mandate mandate);

    constructor(address initialOwner, MandateTypes.Mandate memory initialMandate)
        Owned(initialOwner)
    {
        _setMandate(initialMandate);
    }

    function setMandate(MandateTypes.Mandate calldata nextMandate) external onlyOwner {
        _setMandate(nextMandate);
    }

    function _setMandate(MandateTypes.Mandate memory nextMandate) internal {
        if (
            nextMandate.reserveToken == address(0)
                || nextMandate.maximumStressLossBps > MandateTypes.BPS
                || nextMandate.maximumPoolAllocationBps > MandateTypes.BPS
                || (nextMandate.validUntil != 0 && nextMandate.validUntil <= block.timestamp)
        ) revert InvalidMandate();
        mandate = nextMandate;
        mandateVersion += 1;
        emit MandateUpdated(mandateVersion, nextMandate);
    }
}
