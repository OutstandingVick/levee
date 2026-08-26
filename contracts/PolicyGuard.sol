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
    error InvalidAssessmentSignature();

    MandateTypes.Mandate public mandate;
    uint64 public mandateVersion;
    mapping(address asset => bool approved) public approvedAssets;
    mapping(address target => bool approved) public approvedTargets;
    mapping(address target => mapping(bytes4 selector => bool approved)) public approvedSelectors;
    mapping(address executor => bool approved) public approvedExecutors;
    mapping(bytes32 digest => bool consumed) public consumedAssessments;
    address public riskAttestor;

    event MandateUpdated(uint64 indexed version, MandateTypes.Mandate mandate);
    event AssetApprovalChanged(address indexed asset, bool approved);
    event TargetApprovalChanged(address indexed target, bool approved);
    event SelectorApprovalChanged(address indexed target, bytes4 indexed selector, bool approved);
    event ExecutorApprovalChanged(address indexed executor, bool approved);
    event RiskAttestorChanged(address indexed previousAttestor, address indexed newAttestor);
    event AssessmentConsumed(bytes32 indexed digest);

    bytes32 public constant ACTION_TYPEHASH = keccak256(
        "RiskAssessment(address asset,address target,bytes4 selector,uint256 amount,uint256 existingPoolAllocation,uint256 totalManagedAssets,uint256 reserveBalanceAfter,uint256 projectedStressLossBps,uint64 mandateVersion,uint48 expiresAt)"
    );
    bytes32 private constant DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
    bytes32 private constant NAME_HASH = keccak256("Levee PolicyGuard");
    bytes32 private constant VERSION_HASH = keccak256("1");

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

    function assessmentDigest(MandateTypes.Action memory action, uint48 expiresAt)
        public
        view
        returns (bytes32)
    {
        bytes32 domainSeparator = keccak256(
            abi.encode(DOMAIN_TYPEHASH, NAME_HASH, VERSION_HASH, block.chainid, address(this))
        );
        bytes32 structHash = keccak256(
            abi.encode(
                ACTION_TYPEHASH,
                action.asset,
                action.target,
                action.selector,
                action.amount,
                action.existingPoolAllocation,
                action.totalManagedAssets,
                action.reserveBalanceAfter,
                action.projectedStressLossBps,
                mandateVersion,
                expiresAt
            )
        );
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    function consumeAssessment(
        MandateTypes.Action calldata action,
        uint48 expiresAt,
        bytes calldata signature
    ) external {
        if (!approvedExecutors[msg.sender]) revert NotExecutor();
        if (expiresAt < block.timestamp) revert AssessmentMissingOrExpired();
        bytes32 digest = assessmentDigest(action, expiresAt);
        if (consumedAssessments[digest]) revert AssessmentMissingOrExpired();
        if (_recover(digest, signature) != riskAttestor) revert InvalidAssessmentSignature();
        consumedAssessments[digest] = true;
        emit AssessmentConsumed(digest);
    }

    function _recover(bytes32 digest, bytes calldata signature)
        internal
        pure
        returns (address signer)
    {
        if (signature.length != 65) revert InvalidAssessmentSignature();
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 32))
            v := byte(0, calldataload(add(signature.offset, 64)))
        }
        if (uint256(s) > 0x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0) {
            revert InvalidAssessmentSignature();
        }
        if (v != 27 && v != 28) revert InvalidAssessmentSignature();
        signer = ecrecover(digest, v, r, s);
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
