// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {MandateVault} from "../contracts/MandateVault.sol";
import {PolicyGuard} from "../contracts/PolicyGuard.sol";
import {MandateTypes} from "../contracts/types/MandateTypes.sol";
import {TestBase} from "./TestBase.sol";
import {MockAdapter} from "./mocks/MockAdapter.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract MandateVaultTest is TestBase {
    address internal constant AGENT = address(0xA6E17);
    address internal constant ATTACKER = address(0xBAD);
    MockERC20 internal token;
    MockAdapter internal adapter;
    PolicyGuard internal guard;
    MandateVault internal vault;

    function setUp() public {
        token = new MockERC20("USD Coin", "USDC");
        adapter = new MockAdapter();
        guard = new PolicyGuard(
            address(this),
            MandateTypes.Mandate({
                reserveToken: address(token),
                reserveFloor: 3_000,
                maximumStressLossBps: 700,
                maximumPoolAllocationBps: 5_000,
                rebalanceCooldown: 0,
                validUntil: 0
            })
        );
        vault = new MandateVault(address(this), guard);
        guard.setAssetApproval(address(token), true);
        guard.setTargetApproval(address(adapter), true);
        guard.setSelectorApproval(address(adapter), MockAdapter.deploy.selector, true);
        token.mint(address(this), 10_000);
        token.approve(address(vault), 10_000);
        vault.deposit(address(token), 10_000);
        vault.setAgent(AGENT);
    }

    function executeAsAgent(uint256 amount) internal {
        vm.prank(AGENT);
        vault.execute(
            address(token),
            address(adapter),
            amount,
            600,
            abi.encodeCall(MockAdapter.deploy, (address(token), amount))
        );
    }

    function testAgentExecutesCompliantAllocationAndAllowanceResets() public {
        executeAsAgent(3_500);
        assertEq(token.balanceOf(address(vault)), 6_500);
        assertEq(token.balanceOf(address(adapter)), 3_500);
        assertEq(token.allowance(address(vault), address(adapter)), 0);
        assertEq(vault.deployedCapital(address(adapter), address(token)), 3_500);
    }

    function testRejectsUnauthorizedCaller() public {
        vm.prank(ATTACKER);
        vm.expectRevert(MandateVault.NotAgent.selector);
        vault.execute(
            address(token),
            address(adapter),
            1,
            0,
            abi.encodeCall(MockAdapter.deploy, (address(token), 1))
        );
    }

    function testRejectsUnapprovedStealSelector() public {
        vm.prank(AGENT);
        vm.expectRevert(PolicyGuard.SelectorNotApproved.selector);
        vault.execute(
            address(token),
            address(adapter),
            100,
            0,
            abi.encodeCall(MockAdapter.steal, (address(token), 100))
        );
    }

    function testRejectsCumulativePoolConcentration() public {
        executeAsAgent(3_500);
        vm.prank(AGENT);
        vm.expectRevert(PolicyGuard.PoolAllocationExceeded.selector);
        vault.execute(
            address(token),
            address(adapter),
            1_501,
            600,
            abi.encodeCall(MockAdapter.deploy, (address(token), 1_501))
        );
    }

    function testNormalWithdrawalCannotBreakReserve() public {
        vm.expectRevert(MandateVault.ReserveFloorBreached.selector);
        vault.withdraw(address(token), 7_001, address(this));
    }

    function testPauseRevokesAgentAndEmergencyWithdrawalStillWorks() public {
        vault.setPaused(true);
        assertEq(vault.agent(), address(0));
        vault.emergencyWithdraw(address(token), address(this));
        assertEq(token.balanceOf(address(vault)), 0);
        assertEq(token.balanceOf(address(this)), 10_000);
    }
}
