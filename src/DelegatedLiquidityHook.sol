// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Hooks} from "@uniswap/v4-core/contracts/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/contracts/interfaces/IPoolManager.sol";
import {BaseHook} from "v4-periphery/BaseHook.sol";
import {LiquidityAmounts} from "v4-periphery/libraries/LiquidityAmounts.sol";
import {BalanceDelta} from "@uniswap/v4-core/contracts/types/BalanceDelta.sol";
import {PoolKey, PoolIdLibrary} from "@uniswap/v4-core/contracts/types/PoolId.sol";
import {Checkpoints} from "openzeppelin-v4/contracts/utils/Checkpoints.sol";
import {SafeCast} from "openzeppelin-v4/contracts/utils/math/SafeCast.sol";
import {Currency} from "@uniswap/v4-core/contracts/types/Currency.sol";
import {TickMath} from "@uniswap/v4-core/contracts/libraries/TickMath.sol";
import {IFractionalGovernor} from "flexible-voting/interfaces/IFractionalGovernor.sol";
import {FlexVotingClient} from "flexible-voting/FlexVotingClient.sol";

contract DelegatedLiquidityHook is BaseHook {
  using PoolIdLibrary for PoolKey;
  using Checkpoints for Checkpoints.History;

  mapping(bytes32 positionId => Checkpoints.History) internal positionLiquidityCheckpoints;
  Checkpoints.History internal priceCheckpoints;
  mapping(bytes32 positionId => int24[2]) internal positionTicks;

  mapping(address => bytes32[]) internal positionsByAddress;
  mapping(bytes32 => bool) internal seenPosition;

  bool public isGovToken0;
  address immutable GOV_TOKEN;

  constructor(IPoolManager _poolManager, address _governor) BaseHook(_poolManager) {
    GOV_TOKEN = IFractionalGovernor(_governor).token();
  }

  function getHooksCalls() public pure override returns (Hooks.Calls memory) {
    return Hooks.Calls({
      beforeInitialize: false,
      afterInitialize: true,
      beforeModifyPosition: false,
      afterModifyPosition: true,
      beforeSwap: false,
      afterSwap: true,
      beforeDonate: false,
      afterDonate: false
    });
  }

  /**
   * @notice Callback after a pool is initialized. Record which token (token0 or token1) is the gov
   * token, to return appropriate values in other methods
   */
  function afterInitialize(
    address, // sender
    PoolKey calldata key,
    uint160, // sqrtPriceX96
    int24, // tick
    bytes calldata // hookData
  ) external override returns (bytes4 selector) {
    //
    isGovToken0 = Currency.unwrap(key.currency0) == GOV_TOKEN;
    // If neither token in the pair is the gov token, revert
    if (!isGovToken0 && Currency.unwrap(key.currency1) != GOV_TOKEN) {
      revert("Currency pair does not include governor token");
    }
    selector = BaseHook.afterInitialize.selector;
  }

  function afterModifyPosition(
    address sender,
    PoolKey calldata key,
    IPoolManager.ModifyPositionParams calldata modifyParams,
    BalanceDelta,
    bytes calldata
  ) external override returns (bytes4 selector) {
    bytes32 positionId =
      keccak256(abi.encodePacked(sender, modifyParams.tickLower, modifyParams.tickUpper));

    // Save tickLower & tickUpper into a mapping for this position id
    positionTicks[positionId] = [modifyParams.tickLower, modifyParams.tickUpper];

    // get current liquidity
    uint256 liquidity = positionLiquidityCheckpoints[positionId].latest();
    uint256 liquidityNext = modifyParams.liquidityDelta < 0
      ? liquidity - uint256(-modifyParams.liquidityDelta)
      : liquidity + uint256(modifyParams.liquidityDelta);

    // checkpoint position liquidity
    positionLiquidityCheckpoints[positionId].push(liquidityNext);

    // Checkpoint pool price
    (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(key.toId());
    priceCheckpoints.push(sqrtPriceX96);

    // Record position for address
    if (seenPosition[positionId] == false) {
      seenPosition[positionId] = true;
      positionsByAddress[sender].push(positionId);
    }

    selector = BaseHook.afterModifyPosition.selector;
  }

  function afterSwap(
    address,
    PoolKey calldata key,
    IPoolManager.SwapParams calldata,
    BalanceDelta,
    bytes calldata
  ) external override returns (bytes4 selector) {
    (uint160 price,,,) = poolManager.getSlot0(key.toId());
    priceCheckpoints.push(price);
    selector = BaseHook.afterSwap.selector;
  }
}

contract DelegatedFlexClient is DelegatedLiquidityHook, FlexVotingClient {
  using Checkpoints for Checkpoints.History;

  /// @param _governor The address of the flex-voting-compatible governance contract.
  /// @param _poolManager The address of the pool manager contract.
  constructor(address _governor, IPoolManager _poolManager)
    DelegatedLiquidityHook(_poolManager, _governor)
    FlexVotingClient(_governor)
  {}

  function _rawBalanceOf(address _user) internal view override returns (uint256) {
    uint256 _rawBalance;
    for (uint256 i = 0; i < positionsByAddress[_user].length; i++) {
      _rawBalance += getPastBalance(positionsByAddress[_user][i], block.number);
    }
    return _rawBalance;
  }

  function getPastBalance(bytes32 positionId, uint256 blockNumber) public view returns (uint256) {
    // TODO: make sure these unchecked casts are safe
    uint160 price = uint160(priceCheckpoints.getAtProbablyRecentBlock(blockNumber));
    uint128 liquidity =
      uint128(positionLiquidityCheckpoints[positionId].getAtProbablyRecentBlock(blockNumber));
    (uint256 token0, uint256 token1) = LiquidityAmounts.getAmountsForLiquidity(
      price,
      TickMath.getSqrtRatioAtTick(positionTicks[positionId][0]),
      TickMath.getSqrtRatioAtTick(positionTicks[positionId][1]),
      liquidity
    );
    return isGovToken0 ? token0 : token1;
  }
}
