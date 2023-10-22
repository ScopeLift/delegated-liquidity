// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20Votes} from "openzeppelin-flexible-voting/token/ERC20/extensions/ERC20Votes.sol";
import {GovernorFlexibleVotingMock} from "test/mocks/GovernorMock.sol";
import {GovernorTokenMock} from "test/mocks/GovernorTokenMock.sol";
import {MockToken} from "test/mocks/MockToken.sol"; // Should be renamed
import {DelegatedFlexClientHarness} from "test/harnesses/DelegatedFlexClientHarness.sol";
import {TickMath} from "@uniswap/v4-core/contracts/libraries/TickMath.sol";

import {TickMath} from "@uniswap/v4-core/contracts/libraries/TickMath.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {PoolKey, PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {DelegatedLiquidityHook, DelegatedFlexClient} from "src/DelegatedLiquidityHook.sol";
import {Deployers} from "@uniswap/v4-core/test/foundry-tests/utils/Deployers.sol";
import {PoolModifyPositionTest} from "@uniswap/v4-core/contracts/test/PoolModifyPositionTest.sol";
import {PoolSwapTest} from "@uniswap/v4-core/contracts/test/PoolSwapTest.sol";
import {IPoolManager} from "@uniswap/v4-core/contracts/interfaces/IPoolManager.sol";
import {HookTest} from "test/utils/HookTest.sol";
import {HookMiner} from "test/utils/HookMiner.sol";
import {IHooks} from "@uniswap/v4-core/contracts/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/contracts/libraries/Hooks.sol";
import {LiquidityAmounts} from "v4-periphery/libraries/LiquidityAmounts.sol";
import {Pool} from "v4-core/libraries/Pool.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {IERC20Minimal} from "v4-core/interfaces/external/IERC20Minimal.sol";
import {Math} from "openzeppelin-v4/contracts/utils/math/Math.sol";

contract DelegatedLiquidityHookTest is HookTest, Deployers {
  using PoolIdLibrary for PoolKey;
  using CurrencyLibrary for Currency;

  struct CallbackData {
    address sender;
    PoolKey key;
    IPoolManager.ModifyPositionParams params;
    bytes hookData;
  }

  MockToken erc20;
  GovernorTokenMock erc20Votes;
  GovernorFlexibleVotingMock gov;
  DelegatedLiquidityHook hook;
  PoolKey poolKey;
  PoolId poolId;
  DelegatedFlexClientHarness client;

  event VoteCast(
    address indexed voter,
    uint256 proposalId,
    uint256 voteAgainst,
    uint256 voteFor,
    uint256 voteAbstain
  );

  function setUp() public {
    // Helpers for interacting with the pool
    // creates the pool manager, test tokens, and other utility routers
    HookTest.initHookTestEnv();
    gov = new GovernorFlexibleVotingMock("Governor", ERC20Votes(address(govToken)));

    // Deploy the hook to an address with the correct flags
    uint160 flags = uint160(
      Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_MODIFY_POSITION_FLAG | Hooks.AFTER_INITIALIZE_FLAG
    );
    (address hookAddress, bytes32 salt) = HookMiner.find(
      address(this),
      flags,
      0,
      type(DelegatedFlexClientHarness).creationCode,
      abi.encode(address(gov), address(manager))
    );
    client =
      new DelegatedFlexClientHarness{salt: salt}(address(gov), IPoolManager(address(manager)));
    require(address(client) == hookAddress, "DelegatedTest: hook address mismatch");

    // Create the pool
    poolKey = PoolKey(
      Currency.wrap(address(token0)),
      Currency.wrap(address(token1)),
      3000,
      60,
      IHooks(address(client))
    );
    poolId = poolKey.toId();
    manager.initialize(poolKey, SQRT_RATIO_1_1, ZERO_BYTES);

    token0.mint(address(this), 100 ether);
    token1.mint(address(this), 100 ether);
    token0.approve(address(manager), type(uint256).max);
    token1.approve(address(manager), type(uint256).max);

    // Provide liquidity to the pool
    modifyPosition(poolKey, IPoolManager.ModifyPositionParams(-60, 60, 10 ether), ZERO_BYTES);
    modifyPosition(poolKey, IPoolManager.ModifyPositionParams(-120, 120, 10 ether), ZERO_BYTES);
    modifyPosition(
      poolKey,
      IPoolManager.ModifyPositionParams(
        TickMath.minUsableTick(60), TickMath.maxUsableTick(60), 10 ether
      ),
      ZERO_BYTES
    );
  }

  function modifyPosition(
    PoolKey memory key,
    IPoolManager.ModifyPositionParams memory params,
    bytes memory hookData
  ) internal returns (BalanceDelta delta) {
    delta = abi.decode(
      manager.lock(abi.encode(CallbackData(address(this), key, params, hookData))), (BalanceDelta)
    );

    uint256 ethBalance = address(this).balance;
    if (ethBalance > 0) CurrencyLibrary.NATIVE.transfer(msg.sender, ethBalance);
  }

  function lockAcquired(bytes calldata rawData) external returns (bytes memory) {
    require(msg.sender == address(manager));

    CallbackData memory data = abi.decode(rawData, (CallbackData));

    BalanceDelta delta = manager.modifyPosition(data.key, data.params, data.hookData);

    if (delta.amount0() > 0) {
      if (data.key.currency0.isNative()) {
        manager.settle{value: uint128(delta.amount0())}(data.key.currency0);
      } else {
        IERC20Minimal(Currency.unwrap(data.key.currency0)).transfer(
          // data.sender,
          address(manager),
          uint128(delta.amount0())
        );
        manager.settle(data.key.currency0);
      }
    }
    if (delta.amount1() > 0) {
      if (data.key.currency1.isNative()) {
        manager.settle{value: uint128(delta.amount1())}(data.key.currency1);
      } else {
        IERC20Minimal(Currency.unwrap(data.key.currency1)).transfer(
          // data.sender,
          address(manager),
          uint128(delta.amount1())
        );
        manager.settle(data.key.currency1);
      }
    }

    if (delta.amount0() < 0) {
      manager.take(data.key.currency0, data.sender, uint128(-delta.amount0()));
    }
    if (delta.amount1() < 0) {
      manager.take(data.key.currency1, data.sender, uint128(-delta.amount1()));
    }

    return abi.encode(delta);
  }
}

contract AddLiquidity is DelegatedLiquidityHookTest {
  using PoolIdLibrary for PoolKey;

  function test_castVoteAbstain(address owner, int128 amount0, int128 amount1) public {
    // vm.assume(address(0) != owner);
    owner = address(this);
    vm.assume(int256(amount0) + amount1 != 0);
    amount0 = int128(bound(amount0, 100, type(int64).max)); // greater causes a revert
    amount1 = int128(bound(amount1, 100, type(int64).max)); // greater causes a revert
    uint128 posAmount0 = uint128(amount0);
    uint128 posAmount1 = uint128(amount1);
    (uint160 sqrtPriceX96,,,) = manager.getSlot0(poolKey.toId());
    uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
      sqrtPriceX96,
      TickMath.getSqrtRatioAtTick(int24(-60)),
      TickMath.getSqrtRatioAtTick(int24(60)),
      uint256(posAmount0),
      uint256(posAmount1)
    );

    vm.startPrank(owner);
    token0.mint(owner, posAmount0);
    token1.mint(owner, posAmount1);
    token0.approve(address(manager), posAmount0);
    token1.approve(address(manager), posAmount1);
    modifyPosition(
      poolKey,
      IPoolManager.ModifyPositionParams(int24(-60), int24(60), int256(uint256(liquidity))),
      ZERO_BYTES
    );
    vm.stopPrank();

    bytes32 positionId = keccak256(abi.encodePacked(address(owner), int24(-60), int24(60)));

    uint256 blockNumber = block.number;
    vm.roll(block.number + 5);
    uint256 amount = client.getPastBalance(positionId, blockNumber + 4);
    (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
      sqrtPriceX96,
      TickMath.getSqrtRatioAtTick(int24(-60)),
      TickMath.getSqrtRatioAtTick(int24(60)),
      liquidity
    );
    // TODO: tighten the following assertion so that voting power (amount) exactly equals the amount
    // due to the LP
    // assertEq(amount, govToken == address(token1) ? amount1 : amount0);
  }
}
