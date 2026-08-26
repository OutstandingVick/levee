// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {MandateVault} from "../contracts/MandateVault.sol";
import {PolicyGuard} from "../contracts/PolicyGuard.sol";
import {PositionRegistry} from "../contracts/PositionRegistry.sol";
import {UniswapV3Adapter} from "../contracts/UniswapV3Adapter.sol";
import {ValuationOracle} from "../contracts/ValuationOracle.sol";
import {IAggregatorV3} from "../contracts/interfaces/IAggregatorV3.sol";
import {INonfungiblePositionManager} from "../contracts/interfaces/INonfungiblePositionManager.sol";
import {MandateTypes} from "../contracts/types/MandateTypes.sol";

interface VmScript {
    function envAddress(string calldata name) external view returns (address);
    function envUint(string calldata name) external view returns (uint256);
    function addr(uint256 privateKey) external returns (address);
    function startBroadcast(uint256 privateKey) external;
    function stopBroadcast() external;
}

contract DeployBaseSepolia {
    VmScript internal constant vm =
        VmScript(address(uint160(uint256(keccak256("hevm cheat code")))));

    function run()
        external
        returns (
            ValuationOracle oracle,
            PolicyGuard guard,
            PositionRegistry registry,
            MandateVault vault,
            UniswapV3Adapter adapter
        )
    {
        address owner = vm.envAddress("OWNER_ADDRESS");
        address reserveToken = vm.envAddress("RESERVE_TOKEN");
        address riskAttestor = vm.envAddress("RISK_ATTESTOR");
        address agent = vm.envAddress("AGENT_ADDRESS");
        address priceFeed = vm.envAddress("RESERVE_USD_FEED");
        address positionManager = vm.envAddress("UNISWAP_POSITION_MANAGER");
        uint256 reserveFloorUsd18 = vm.envUint("RESERVE_FLOOR_USD18");
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);
        oracle = new ValuationOracle(deployer);
        guard = new PolicyGuard(
            deployer,
            MandateTypes.Mandate({
                reserveToken: reserveToken,
                reserveFloor: reserveFloorUsd18,
                maximumStressLossBps: 700,
                maximumPoolAllocationBps: 5_000,
                rebalanceCooldown: 6 hours,
                validUntil: 0
            })
        );
        registry = new PositionRegistry(deployer);
        vault = new MandateVault(deployer, guard, oracle);
        adapter = new UniswapV3Adapter(
            deployer, address(vault), INonfungiblePositionManager(positionManager), 15 minutes
        );

        oracle.setFeed(reserveToken, IAggregatorV3(priceFeed), 6, 1 hours);
        guard.setRiskAttestor(riskAttestor);
        guard.setExecutorApproval(address(vault), true);
        guard.setAssetApproval(reserveToken, true);
        guard.setTargetApproval(address(adapter), true);
        guard.setSelectorApproval(address(adapter), UniswapV3Adapter.openPosition.selector, true);
        registry.setOperator(address(vault));
        vault.setAgent(agent);
        oracle.transferOwnership(owner);
        guard.transferOwnership(owner);
        registry.transferOwnership(owner);
        vault.transferOwnership(owner);
        adapter.transferOwnership(owner);
        vm.stopBroadcast();
    }
}
