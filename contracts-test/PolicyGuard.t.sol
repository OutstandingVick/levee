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
                reserveFloor: 3_000e18,
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
            amount: 3_500e18,
            existingPoolAllocation: 0,
            totalManagedAssets: 7_000e18,
            reserveBalanceAfter: 3_000e18,
            projectedStressLossBps: 650
        });
    }

    function testAcceptsCompliantAction() public view {
        guard.validateAction(validAction());
    }

    function testRejectsReserveFloorBreach() public {
        MandateTypes.Action memory action = validAction();
        action.reserveBalanceAfter = 2_999e18;
        vm.expectRevert(PolicyGuard.ReserveFloorBreached.selector);
        guard.validateAction(action);
    }

    function testRejectsConcentrationBreach() public {
        MandateTypes.Action memory action = validAction();
        action.amount = 3_501e18;
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

    function testFuzzAcceptsAllocationWithinMandate(uint256 rawAmount, uint256 rawRisk)
        public
        view
    {
        MandateTypes.Action memory action = validAction();
        action.amount = 1 + (rawAmount % 3_500e18);
        action.projectedStressLossBps = rawRisk % 701;
        guard.validateAction(action);
    }

    function testFuzzRejectsAnyStressAboveMandate(uint256 rawRisk) public {
        MandateTypes.Action memory action = validAction();
        action.projectedStressLossBps = 701 + (rawRisk % (type(uint32).max - 701));
        vm.expectRevert(PolicyGuard.StressLossExceeded.selector);
        guard.validateAction(action);
    }

    function testFuzzRejectsAnyReserveBelowFloor(uint256 rawReserve) public {
        MandateTypes.Action memory action = validAction();
        action.reserveBalanceAfter = rawReserve % 3_000e18;
        vm.expectRevert(PolicyGuard.ReserveFloorBreached.selector);
        guard.validateAction(action);
    }
}
