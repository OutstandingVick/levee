// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {MandateVault} from "../contracts/MandateVault.sol";
import {PolicyGuard} from "../contracts/PolicyGuard.sol";
import {MandateTypes} from "../contracts/types/MandateTypes.sol";
import {ValuationOracle} from "../contracts/ValuationOracle.sol";
import {IAggregatorV3} from "../contracts/interfaces/IAggregatorV3.sol";
import {TestBase} from "./TestBase.sol";
import {MockAdapter} from "./mocks/MockAdapter.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockAggregator} from "./mocks/MockAggregator.sol";
import {MockFeeToken} from "./mocks/MockFeeToken.sol";

contract MandateVaultTest is TestBase {
    address internal constant AGENT = address(0xA6E17);
    address internal constant ATTACKER = address(0xBAD);
    uint256 internal constant RISK_PRIVATE_KEY = 0xA11CE;
    MockERC20 internal token;
    MockAdapter internal adapter;
    PolicyGuard internal guard;
    MandateVault internal vault;
    ValuationOracle internal oracle;

    function setUp() public {
        token = new MockERC20("USD Coin", "USDC");
        adapter = new MockAdapter();
        oracle = new ValuationOracle(address(this));
        MockAggregator feed = new MockAggregator(8, 1e8);
        oracle.setFeed(address(token), IAggregatorV3(address(feed)), 0, 1 days);
        guard = new PolicyGuard(
            address(this),
            MandateTypes.Mandate({
                reserveToken: address(token),
                reserveFloor: 3_000e18,
                maximumStressLossBps: 700,
                maximumPoolAllocationBps: 5_000,
                rebalanceCooldown: 0,
                validUntil: 0
            })
        );
        vault = new MandateVault(address(this), guard, oracle);
        guard.setExecutorApproval(address(vault), true);
        guard.setRiskAttestor(vm.addr(RISK_PRIVATE_KEY));
        guard.setAssetApproval(address(token), true);
        guard.setTargetApproval(address(adapter), true);
        guard.setSelectorApproval(address(adapter), MockAdapter.deploy.selector, true);
        token.mint(address(this), 10_000);
        token.approve(address(vault), 10_000);
        vault.deposit(address(token), 10_000);
        vault.setAgent(AGENT);
    }

    function executeAsAgent(uint256 amount) internal {
        (uint48 expiry, bytes memory signature) = signAssessment(amount, 600);
        vm.prank(AGENT);
        vault.execute(
            address(token),
            address(adapter),
            amount,
            600,
            expiry,
            signature,
            abi.encodeCall(MockAdapter.deploy, (address(token), amount))
        );
    }

    function signAssessment(uint256 amount, uint256 riskBps)
        internal
        returns (uint48 expiry, bytes memory signature)
    {
        return signAssessmentWithKey(amount, riskBps, RISK_PRIVATE_KEY);
    }

    function signAssessmentWithKey(uint256 amount, uint256 riskBps, uint256 signingKey)
        internal
        returns (uint48 expiry, bytes memory signature)
    {
        expiry = uint48(block.timestamp + 5 minutes);
        MandateTypes.Action memory action = MandateTypes.Action({
            asset: address(token),
            target: address(adapter),
            selector: MockAdapter.deploy.selector,
            amount: amount * 1e18,
            existingPoolAllocation: vault.deployedCapital(address(adapter), address(token)) * 1e18,
            totalManagedAssets: vault.totalDeposited(address(token)) * 1e18,
            reserveBalanceAfter: (token.balanceOf(address(vault)) - amount) * 1e18,
            projectedStressLossBps: riskBps
        });
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(signingKey, guard.assessmentDigest(action, expiry));
        signature = abi.encodePacked(r, s, v);
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
            0,
            bytes(""),
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
            0,
            bytes(""),
            abi.encodeCall(MockAdapter.steal, (address(token), 100))
        );
    }

    function testRejectsAgentSuppliedRiskWithoutAttestation() public {
        vm.prank(AGENT);
        vm.expectRevert(PolicyGuard.InvalidAssessmentSignature.selector);
        vault.execute(
            address(token),
            address(adapter),
            100,
            0,
            uint48(block.timestamp + 5 minutes),
            bytes(""),
            abi.encodeCall(MockAdapter.deploy, (address(token), 100))
        );
    }

    function testAssessmentCannotBeReplayed() public {
        (uint48 expiry, bytes memory signature) = signAssessment(100, 600);
        vm.prank(AGENT);
        vault.execute(
            address(token),
            address(adapter),
            100,
            600,
            expiry,
            signature,
            abi.encodeCall(MockAdapter.deploy, (address(token), 100))
        );
        vm.prank(AGENT);
        vm.expectRevert(PolicyGuard.InvalidAssessmentSignature.selector);
        vault.execute(
            address(token),
            address(adapter),
            100,
            600,
            expiry,
            signature,
            abi.encodeCall(MockAdapter.deploy, (address(token), 100))
        );
    }

    function testRejectsExpiredAssessment() public {
        (uint48 expiry, bytes memory signature) = signAssessment(100, 600);
        vm.warp(uint256(expiry) + 1);
        vm.prank(AGENT);
        vm.expectRevert(PolicyGuard.AssessmentMissingOrExpired.selector);
        vault.execute(
            address(token),
            address(adapter),
            100,
            600,
            expiry,
            signature,
            abi.encodeCall(MockAdapter.deploy, (address(token), 100))
        );
    }

    function testRejectsAssessmentFromWrongSigner() public {
        (uint48 expiry, bytes memory signature) = signAssessmentWithKey(100, 600, 0xB0B);
        vm.prank(AGENT);
        vm.expectRevert(PolicyGuard.InvalidAssessmentSignature.selector);
        vault.execute(
            address(token),
            address(adapter),
            100,
            600,
            expiry,
            signature,
            abi.encodeCall(MockAdapter.deploy, (address(token), 100))
        );
    }

    function testMandateVersionInvalidatesPriorAssessment() public {
        (uint48 expiry, bytes memory signature) = signAssessment(100, 600);
        guard.setMandate(guard.currentMandate());
        vm.prank(AGENT);
        vm.expectRevert(PolicyGuard.InvalidAssessmentSignature.selector);
        vault.execute(
            address(token),
            address(adapter),
            100,
            600,
            expiry,
            signature,
            abi.encodeCall(MockAdapter.deploy, (address(token), 100))
        );
    }

    function testRejectsCumulativePoolConcentration() public {
        executeAsAgent(3_500);
        (uint48 expiry, bytes memory signature) = signAssessment(1_501, 600);
        vm.prank(AGENT);
        vm.expectRevert(PolicyGuard.PoolAllocationExceeded.selector);
        vault.execute(
            address(token),
            address(adapter),
            1_501,
            600,
            expiry,
            signature,
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

    function testDepositAccountsForFeeOnTransferAmount() public {
        MockFeeToken feeToken = new MockFeeToken(1_000);
        MockAggregator feed = new MockAggregator(8, 1e8);
        oracle.setFeed(address(feeToken), IAggregatorV3(address(feed)), 0, 1 days);
        feeToken.mint(address(this), 1_000);
        feeToken.approve(address(vault), 1_000);
        vault.deposit(address(feeToken), 1_000);
        assertEq(vault.totalDeposited(address(feeToken)), 900);
        assertEq(feeToken.balanceOf(address(vault)), 900);
    }

    function testFuzzOwnerCannotWithdrawThroughReserve(uint256 rawAmount) public {
        uint256 amount = 7_001 + (rawAmount % 3_000);
        vm.expectRevert();
        vault.withdraw(address(token), amount, address(this));
        assertEq(token.balanceOf(address(vault)), 10_000);
    }

    function invariantCustodyAccountingNeverExceedsBalancePlusDeployment() public view {
        uint256 accounted = token.balanceOf(address(vault))
            + vault.deployedCapital(address(adapter), address(token));
        assertTrue(accounted >= vault.totalDeposited(address(token)));
    }
}
