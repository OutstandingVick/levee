// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {PolicyGuard} from "./PolicyGuard.sol";
import {ValuationOracle} from "./ValuationOracle.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";
import {Owned} from "./security/Owned.sol";
import {Pausable} from "./security/Pausable.sol";
import {ReentrancyGuard} from "./security/ReentrancyGuard.sol";
import {MandateTypes} from "./types/MandateTypes.sol";

contract MandateVault is Owned, Pausable, ReentrancyGuard {
    using SafeTransferLib for address;

    error ZeroAmount();
    error ReserveFloorBreached();
    error NotAgent();
    error InvalidCallData();
    error ExternalCallFailed(bytes reason);
    error OverspentToken();
    error RebalanceCooldownActive();

    PolicyGuard public immutable policyGuard;
    ValuationOracle public immutable valuationOracle;
    address public agent;
    mapping(address token => uint256 amount) public totalDeposited;
    mapping(address target => mapping(address asset => uint256 amount)) public deployedCapital;
    uint48 public lastExecutionAt;

    event Deposited(address indexed token, uint256 amount);
    event Withdrawn(address indexed token, uint256 amount, address indexed recipient);
    event AgentChanged(address indexed previousAgent, address indexed newAgent);
    event ActionExecuted(
        address indexed agent,
        address indexed target,
        address indexed asset,
        bytes4 selector,
        uint256 amount,
        uint256 projectedStressLossBps
    );
    event EmergencyWithdrawal(address indexed token, uint256 amount, address indexed recipient);

    constructor(address initialOwner, PolicyGuard guard, ValuationOracle oracle)
        Owned(initialOwner)
    {
        if (address(guard) == address(0) || address(oracle) == address(0)) {
            revert ZeroAddress();
        }
        policyGuard = guard;
        valuationOracle = oracle;
    }

    modifier onlyAgent() {
        if (msg.sender != agent) revert NotAgent();
        _;
    }

    function setAgent(address newAgent) external onlyOwner {
        emit AgentChanged(agent, newAgent);
        agent = newAgent;
    }

    function setPaused(bool value) external onlyOwner {
        _setPaused(value);
        if (value && agent != address(0)) {
            emit AgentChanged(agent, address(0));
            agent = address(0);
        }
    }

    function deposit(address token, uint256 amount) external onlyOwner whenNotPaused nonReentrant {
        if (amount == 0) revert ZeroAmount();
        token.safeTransferFrom(msg.sender, address(this), amount);
        totalDeposited[token] += amount;
        emit Deposited(token, amount);
    }

    function execute(
        address asset,
        address target,
        uint256 amount,
        uint256 projectedStressLossBps,
        uint48 assessmentExpiry,
        bytes calldata assessmentSignature,
        bytes calldata data
    ) external onlyAgent whenNotPaused nonReentrant returns (bytes memory result) {
        if (amount == 0) revert ZeroAmount();
        if (data.length < 4) revert InvalidCallData();
        bytes4 selector = bytes4(data[:4]);
        MandateTypes.Mandate memory current = policyGuard.currentMandate();
        if (block.timestamp < uint256(lastExecutionAt) + current.rebalanceCooldown) {
            revert RebalanceCooldownActive();
        }
        uint256 balanceBefore = IERC20(asset).balanceOf(address(this));
        uint256 reserveAfter = IERC20(current.reserveToken).balanceOf(address(this));
        if (asset == current.reserveToken) reserveAfter = balanceBefore - amount;
        uint256 amountUsd = valuationOracle.usdValue(asset, amount);
        uint256 managedUsd = valuationOracle.usdValue(asset, totalDeposited[asset]);
        uint256 existingPoolAllocationUsd =
            valuationOracle.usdValue(asset, deployedCapital[target][asset]);

        MandateTypes.Action memory action = MandateTypes.Action({
            asset: asset,
            target: target,
            selector: selector,
            amount: amountUsd,
            existingPoolAllocation: existingPoolAllocationUsd,
            totalManagedAssets: managedUsd,
            reserveBalanceAfter: valuationOracle.usdValue(current.reserveToken, reserveAfter),
            projectedStressLossBps: projectedStressLossBps
        });
        policyGuard.validateAction(action);
        policyGuard.consumeAssessment(action, assessmentExpiry, assessmentSignature);

        asset.forceApprove(target, amount);
        (bool success, bytes memory returnData) = target.call(data);
        asset.forceApprove(target, 0);
        if (!success) revert ExternalCallFailed(returnData);
        uint256 balanceAfter = IERC20(asset).balanceOf(address(this));
        if (balanceBefore > balanceAfter && balanceBefore - balanceAfter > amount) {
            revert OverspentToken();
        }
        uint256 spent = balanceBefore > balanceAfter ? balanceBefore - balanceAfter : 0;
        deployedCapital[target][asset] += spent;
        lastExecutionAt = uint48(block.timestamp);
        emit ActionExecuted(msg.sender, target, asset, selector, amount, projectedStressLossBps);
        return returnData;
    }

    function withdraw(address token, uint256 amount, address recipient)
        external
        onlyOwner
        whenNotPaused
        nonReentrant
    {
        if (amount == 0) revert ZeroAmount();
        if (recipient == address(0)) revert ZeroAddress();
        MandateTypes.Mandate memory current = policyGuard.currentMandate();
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (
            token == current.reserveToken
                && valuationOracle.usdValue(token, balance - amount) < current.reserveFloor
        ) {
            revert ReserveFloorBreached();
        }
        totalDeposited[token] = totalDeposited[token] > amount ? totalDeposited[token] - amount : 0;
        token.safeTransfer(recipient, amount);
        emit Withdrawn(token, amount, recipient);
    }

    function emergencyWithdraw(address token, address recipient) external onlyOwner nonReentrant {
        if (recipient == address(0)) revert ZeroAddress();
        uint256 amount = IERC20(token).balanceOf(address(this));
        totalDeposited[token] = 0;
        token.safeTransfer(recipient, amount);
        emit EmergencyWithdrawal(token, amount, recipient);
    }
}
