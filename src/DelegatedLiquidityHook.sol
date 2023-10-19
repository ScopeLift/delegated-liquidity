// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Hooks} from "@uniswap/v4-core/contracts/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/contracts/interfaces/IPoolManager.sol";
import {BaseHook} from "v4-periphery/BaseHook.sol";
import {BalanceDelta} from "@uniswap/v4-core/contracts/types/BalanceDelta.sol";
import {PoolKey, PoolIdLibrary} from "@uniswap/v4-core/contracts/types/PoolId.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";

contract DelegatedLiquidityHook is BaseHook {
  using PoolIdLibrary for PoolKey;
  using Checkpoints for Checkpoints.Trace224;

  mapping(bytes32 positionId => Checkpoints.Trace224) private positionCheckpoints;
  Checkpoints.Trace224 private poolCheckpoints;

  constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

  function getHooksCalls() public pure override returns (Hooks.Calls memory) {
    return Hooks.Calls({
      beforeInitialize: false,
      afterInitialize: false,
      beforeModifyPosition: true,
      afterModifyPosition: true,
      beforeSwap: true,
      afterSwap: true,
      beforeDonate: false,
      afterDonate: false
    });
  }

  function afterModifyPosition(
    address sender,
    PoolKey calldata,
    IPoolManager.ModifyPositionParams calldata modifyParams,
    BalanceDelta,
    bytes calldata
  ) external override returns (bytes4 selector) {

    selector = BaseHook.afterModifyPosition.selector;
	// checkpoint position
	bytes32 positionKey = keccak256(abi.encodePacked(sender, modifyParams.tickLower, modifyParams.tickUpper));
	// get current liquidity
	uint256 liquidity = positionCheckpoints[positionKey].latest();
	// Do we track the liquidity or use the balance delta
	uint256 liquidityNext = modifyParams.liquidityDelta < 0
    ? liquidity - uint256(-modifyParams.liquidityDelta)
    : liquidity + uint256(modifyParams.liquidityDelta);

	positionCheckpoints[positionKey].push(liquidityNext);
	// checkpoint liquidity and price
  }
}

// Checkpoint Liquidity, Price
// Separate map for position checkpointing

