// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Owned} from "./security/Owned.sol";
import {MandateTypes} from "./types/MandateTypes.sol";

contract PolicyGuard is Owned {
    error InvalidMandate();
    error MandateExpired();
    error AssetNotApproved();
    error TargetNotApproved();
    error SelectorNotApproved();
    error ReserveFloorBreached();
    error PoolAllocationExceeded();
    error StressLossExceeded();
    error NotRiskAttestor();
    error NotExecutor();
    error AssessmentMissingOrExpired();

    MandateTypes.Mandate public mandate;
    uint64 public mandateVersion;
    mapping(address asset => bool approved) public approvedAssets;
    mapping(address target => bool approved) public approvedTargets;
    mapping(address target => mapping(bytes4 selector => bool approved)) public approvedSelectors;
    mapping(address executor => bool approved) public approvedExecutors;
    mapping(bytes32 actionHash => uint48 expiresAt) public assessments;
    address public riskAttestor;

    event MandateUpdated(uint64 indexed version, MandateTypes.Mandate mandate);
    event AssetApprovalChanged(address indexed asset, bool approved);
    event TargetApprovalChanged(address indexed target, bool approved);
    event SelectorApprovalChanged(address indexed target, bytes4 indexed selector, bool approved);
    event ExecutorApprovalChanged(address indexed executor, bool approved);
    event RiskAttestorChanged(address indexed previousAttestor, address indexed newAttestor);
    event AssessmentApproved(bytes32 indexed actionHash, uint48 expiresAt);
    event AssessmentConsumed(bytes32 indexed actionHash);

    constructor(address initialOwner, MandateTypes.Mandate memory initialMandate)
        Owned(initialOwner)
    {
        _setMandate(initialMandate);
    }

    function setMandate(MandateTypes.Mandate calldata nextMandate) external onlyOwner {
        _setMandate(nextMandate);
    }

    function currentMandate() external view returns (MandateTypes.Mandate memory) {
        return mandate;
    }

    function setAssetApproval(address asset, bool approved) external onlyOwner {
        if (asset == address(0)) revert ZeroAddress();
        approvedAssets[asset] = approved;
        emit AssetApprovalChanged(asset, approved);
    }

    function setExecutorApproval(address executor, bool approved) external onlyOwner {
        if (executor == address(0)) revert ZeroAddress();
        approvedExecutors[executor] = approved;
        emit ExecutorApprovalChanged(executor, approved);
    }

    function setRiskAttestor(address nextAttestor) external onlyOwner {
        emit RiskAttestorChanged(riskAttestor, nextAttestor);
        riskAttestor = nextAttestor;
    }

    function actionHash(MandateTypes.Action memory action) public view returns (bytes32) {
        return keccak256(abi.encode(block.chainid, address(this), mandateVersion, action));
    }

    function approveAssessment(MandateTypes.Action calldata action, uint48 expiresAt) external {
        if (msg.sender != riskAttestor) revert NotRiskAttestor();
        if (expiresAt <= block.timestamp) revert AssessmentMissingOrExpired();
        bytes32 digest = actionHash(action);
        assessments[digest] = expiresAt;
        emit AssessmentApproved(digest, expiresAt);
    }

    function consumeAssessment(MandateTypes.Action calldata action) external {
        if (!approvedExecutors[msg.sender]) revert NotExecutor();
        bytes32 digest = actionHash(action);
        if (assessments[digest] < block.timestamp) revert AssessmentMissingOrExpired();
        delete assessments[digest];
        emit AssessmentConsumed(digest);
    }

    function setTargetApproval(address target, bool approved) external onlyOwner {
        if (target == address(0)) revert ZeroAddress();
        approvedTargets[target] = approved;
        emit TargetApprovalChanged(target, approved);
    }

    function setSelectorApproval(address target, bytes4 selector, bool approved)
        external
        onlyOwner
    {
        if (target == address(0)) revert ZeroAddress();
        approvedSelectors[target][selector] = approved;
        emit SelectorApprovalChanged(target, selector, approved);
    }

    function validateAction(MandateTypes.Action calldata action) external view {
        MandateTypes.Mandate memory current = mandate;
        if (current.validUntil != 0 && block.timestamp > current.validUntil) {
            revert MandateExpired();
        }
        if (!approvedAssets[action.asset]) revert AssetNotApproved();
        if (!approvedTargets[action.target]) revert TargetNotApproved();
        if (!approvedSelectors[action.target][action.selector]) revert SelectorNotApproved();
        if (action.reserveBalanceAfter < current.reserveFloor) revert ReserveFloorBreached();
        if (
            action.totalManagedAssets == 0
                || (action.existingPoolAllocation + action.amount) * MandateTypes.BPS
                    > action.totalManagedAssets * current.maximumPoolAllocationBps
        ) revert PoolAllocationExceeded();
        if (action.projectedStressLossBps > current.maximumStressLossBps) {
            revert StressLossExceeded();
        }
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
