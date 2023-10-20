// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {FeeLibrary} from "v4-core/libraries/FeeLibrary.sol";
import {Pool} from "v4-core/libraries/Pool.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey, PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Deployers} from "@uniswap/v4-core/test/foundry-tests/utils/Deployers.sol";
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";

import {TestPoolManager} from "test/utils/TestPoolManager.sol";
import {CounterHook, CounterFactory} from "src/CounterHook.sol";
import {CallType} from "src/router/UniswapV4Router.sol";

/// Hooks and test are based off of
/// https://github.com/naddison36/uniswap-v4-hooks/blob/f47e5bd14a551b3a44b737123150ae8cf29e25a1/test/Counter.t.sol
contract CounterTest is Test, TestPoolManager, Deployers, GasSnapshot {
  using PoolIdLibrary for PoolKey;
  using CurrencyLibrary for Currency;

  CounterHook hook;
  PoolKey poolKey;

  function setUp() public {
    // creates the pool manager, test tokens and generic routers
    TestPoolManager.poolInitialize();

    // Deploy the CounterHook factory
    CounterFactory factory = new CounterFactory();
    // Use the factory to create a new CounterHook contract
    hook = CounterHook(factory.mineDeploy(manager));

    // Create the pool
    poolKey = PoolKey(
      Currency.wrap(address(tokenA)),
      Currency.wrap(address(tokenB)),
      FeeLibrary.HOOK_SWAP_FEE_FLAG | FeeLibrary.HOOK_WITHDRAW_FEE_FLAG | uint24(3000),
      60,
      IHooks(hook)
    );
    manager.initialize(poolKey, SQRT_RATIO_1_1, "");

    // Provide liquidity over different ranges to the pool
    caller.addLiquidity(poolKey, address(this), -60, 60, 10 ether);
    caller.addLiquidity(poolKey, address(this), -120, 120, 10 ether);
    caller.addLiquidity(
      poolKey, address(this), TickMath.minUsableTick(60), TickMath.maxUsableTick(60), 10 ether
    );
  }

  function test_AddLiquidity() public {
    caller.addLiquidity(poolKey, address(this), -60, 60, 10 ether);
  }

  function test_CounterHookFees() public {
    // Check the hook fee
    (Pool.Slot0 memory slot0,,,) = manager.pools(poolKey.toId());
    assertEq(slot0.hookFees, 0x5533);

    assertEq(manager.hookFeesAccrued(address(hook), poolKey.currency0), 0);
    assertEq(manager.hookFeesAccrued(address(hook), poolKey.currency1), 0);
  }

  function test_CounterSwap() public {
    assertEq(hook.beforeSwapCounter(), 100);
    assertEq(hook.afterSwapCounter(), 200);

    // Perform a test swap
    caller.swap(poolKey, address(this), address(this), poolKey.currency0, 1e18);

    assertEq(hook.beforeSwapCounter(), 101);
    assertEq(hook.afterSwapCounter(), 201);

    assertGt(manager.hookFeesAccrued(address(hook), poolKey.currency0), 0);
    assertEq(manager.hookFeesAccrued(address(hook), poolKey.currency1), 0);
  }

  function test_CounterSwapFromPoolManager() public {
    // Perform a deposit to the pool manager
    caller.deposit(address(tokenB), address(this), address(this), 2e18);

    // The tester needs to approve the router to spend their tokens in the Pool Manager
    manager.setApprovalForAll(address(caller), true);
    assertTrue(manager.isApprovedForAll(address(this), address(caller)));

    // Perform a test swap of ERC1155 tokens
    caller.swapManagerTokens(poolKey, poolKey.currency1, 2e18, address(this));

    // Revoke the tester's approval of the router as anyone can send calls to the router
    manager.setApprovalForAll(address(caller), false);
  }

  function test_DepositTokenA() public {
    assertEq(manager.balanceOf(address(this), uint160(address(tokenA))), 0);
    assertEq(manager.balanceOf(address(this), uint160(address(tokenB))), 0);

    // Perform a deposit to the pool manager
    caller.deposit(address(tokenA), address(this), address(this), 1e18);

    // Check tester's balance has been updated
    assertEq(manager.balanceOf(address(this), uint160(address(tokenA))), 1e18);
    assertEq(manager.balanceOf(address(this), uint160(address(tokenB))), 0);
  }

  function test_WithdrawTokenA() public {
    // Perform a deposit to the pool manager
    caller.deposit(address(tokenA), address(this), address(this), 10e18);
    assertEq(manager.balanceOf(address(this), uint160(address(tokenA))), 10e18);
    assertEq(manager.balanceOf(address(this), uint160(address(tokenB))), 0);

    // The tester needs to approve the caller contract to spend their tokens in the Pool Manager
    manager.setApprovalForAll(address(caller), true);

    caller.withdraw(address(tokenA), address(this), 6e18);

    assertEq(manager.balanceOf(address(this), uint160(address(tokenA))), 4e18);
    assertEq(manager.balanceOf(address(this), uint160(address(tokenB))), 0);
  }

  function test_FlashLoan() public {
    // Perform a flash loan
    bytes memory callbackData = abi.encodeWithSelector(tokenA.balanceOf.selector, router);
    caller.flashLoan(address(tokenA), 1e6, address(tokenA), CallType.Call, callbackData);
  }
}

/**
 * Test harness setup needed (in another file) for the hook:
 * 1. Deploy an ERC20Votes token that will be used in the pool
 * 2. Deploy a non-ERC20Votes mock token that will be the other side of the pool
 * 3. Mint quantities of both and deposit them
 * 4. ERC20Votes token should be connected to a GovernorCountingFractional Governor which must
 * also be deployed
 * 5. Set up a proposal in the Governor and move it to the state of being ready to be voted on
 * 6. Finally, demonstrate the LP to the pool can vote (through the pool) on the proposal in the Governor
 */
