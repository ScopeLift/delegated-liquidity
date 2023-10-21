// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {PoolManager} from "@uniswap/v4-core/contracts/PoolManager.sol";
import {IPoolManager} from "@uniswap/v4-core/contracts/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/contracts/types/PoolKey.sol";
import {PoolModifyPositionTest} from "@uniswap/v4-core/contracts/test/PoolModifyPositionTest.sol";
import {PoolSwapTest} from "@uniswap/v4-core/contracts/test/PoolSwapTest.sol";
import {PoolDonateTest} from "@uniswap/v4-core/contracts/test/PoolDonateTest.sol";
import {MockToken} from "test/mocks/MockToken.sol"; // Should be renamed

import {TestERC20} from "@uniswap/v4-core/contracts/test/TestERC20.sol";
import {TickMath} from "@uniswap/v4-core/contracts/libraries/TickMath.sol";
import {GovernorTokenMock} from "test/mocks/GovernorTokenMock.sol";

/// @notice Contract to initialize some test helpers
/// @dev Minimal initialization. Inheriting contract should set up pools and provision liquidity
/// Source: https://github.com/saucepoint/v4-template/blob/d69c148cd12919f6a10eb880b22f530346b6be75/test/utils/HookTest.sol
contract HookTest is Test {
  PoolManager manager;
  PoolModifyPositionTest modifyPositionRouter;
  PoolSwapTest swapRouter;
  PoolDonateTest donateRouter;
  MockToken token0;
  MockToken token1;
  address govToken;

  uint160 public constant MIN_PRICE_LIMIT = TickMath.MIN_SQRT_RATIO + 1;
  uint160 public constant MAX_PRICE_LIMIT = TickMath.MAX_SQRT_RATIO - 1;

  function initHookTestEnv() public {
    uint256 amount = 2 ** 128;
    MockToken _tokenA = new MockToken("Hello", "WRLD", 1000e18);
    MockToken _tokenB = MockToken(address(new GovernorTokenMock("Governor token", "GOV")));
    govToken = address(_tokenB);

    // pools alphabetically sort tokens by address
    // so align `token0` with `pool.token0` for consistency
    if (address(_tokenA) < address(_tokenB)) {
      token0 = _tokenA;
      token1 = _tokenB;
    } else {
      token0 = _tokenB;
      token1 = _tokenA;
    }
    manager = new PoolManager(500000);

    // Helpers for interacting with the pool
    modifyPositionRouter = new PoolModifyPositionTest(IPoolManager(address(manager)));
    swapRouter = new PoolSwapTest(IPoolManager(address(manager)));
    donateRouter = new PoolDonateTest(IPoolManager(address(manager)));

    // Approve for liquidity provision
    token0.approve(address(modifyPositionRouter), amount);
    token1.approve(address(modifyPositionRouter), amount);

    token0.mint(address(this), amount);
    token1.mint(address(this), amount);

    // Approve for swapping
    token0.approve(address(swapRouter), amount);
    token1.approve(address(swapRouter), amount);
  }

  function swap(PoolKey memory key, int256 amountSpecified, bool zeroForOne, bytes memory hookData)
    internal
  {
    IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
      zeroForOne: zeroForOne,
      amountSpecified: amountSpecified,
      sqrtPriceLimitX96: zeroForOne ? MIN_PRICE_LIMIT : MAX_PRICE_LIMIT // unlimited impact
    });

    PoolSwapTest.TestSettings memory testSettings =
      PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true});

    swapRouter.swap(key, params, testSettings, hookData);
  }
}
