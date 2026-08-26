// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {PolicyGuard} from "../contracts/PolicyGuard.sol";
import {MandateTypes} from "../contracts/types/MandateTypes.sol";
import {TestBase} from "./TestBase.sol";

contract PolicyGuardTest is TestBase {
    address internal constant TOKEN = address(0x100);
    address internal constant TARGET = address(0x200);
    bytes4 internal constant SELECTOR = bytes4(keccak256("deploy(address,uint256)"));
    PolicyGuard internal guard;

    function setUp() public {
        guard = new PolicyGuard(
            address(this),
            MandateTypes.Mandate({
                reserveToken: TOKEN,
                reserveFloor: 3_000,
                maximumStressLossBps: 700,
                maximumPoolAllocationBps: 5_000,
                rebalanceCooldown: 0,
                validUntil: 0
            })
        );
        guard.setAssetApproval(TOKEN, true);
        guard.setTargetApproval(TARGET, true);
        guard.setSelectorApproval(TARGET, SELECTOR, true);
    }

    function validAction() internal pure returns (MandateTypes.Action memory) {
        return MandateTypes.Action({
            asset: TOKEN,
            target: TARGET,
            selector: SELECTOR,
            amount: 3_500,
            totalManagedAssets: 7_000,
            reserveBalanceAfter: 3_000,
            projectedStressLossBps: 650
        });
    }

    function testAcceptsCompliantAction() public view {
        guard.validateAction(validAction());
    }

    function testRejectsReserveFloorBreach() public {
        MandateTypes.Action memory action = validAction();
        action.reserveBalanceAfter = 2_999;
        vm.expectRevert(PolicyGuard.ReserveFloorBreached.selector);
        guard.validateAction(action);
    }

    function testRejectsConcentrationBreach() public {
        MandateTypes.Action memory action = validAction();
        action.amount = 3_501;
        vm.expectRevert(PolicyGuard.PoolAllocationExceeded.selector);
        guard.validateAction(action);
    }

    function testRejectsStressBreach() public {
        MandateTypes.Action memory action = validAction();
        action.projectedStressLossBps = 701;
        vm.expectRevert(PolicyGuard.StressLossExceeded.selector);
        guard.validateAction(action);
    }

    function testRejectsUnapprovedSelector() public {
        MandateTypes.Action memory action = validAction();
        action.selector = bytes4(keccak256("steal(address,uint256)"));
        vm.expectRevert(PolicyGuard.SelectorNotApproved.selector);
        guard.validateAction(action);
    }
}
