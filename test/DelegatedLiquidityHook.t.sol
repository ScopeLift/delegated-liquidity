// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20Votes} from "openzeppelin-flexible-voting/token/ERC20/extensions/ERC20Votes.sol";
import {GovernorFlexibleVotingMock} from "test/mocks/GovernorMock.sol";
import {GovernorTokenMock} from "test/mocks/GovernorTokenMock.sol";
import {MockToken} from "test/mocks/MockToken.sol"; // Should be renamed
import {DelegatedFlexClientHarness} from "test/harnesses/DelegatedFlexClientHarness.sol";
import {TickMath} from "@uniswap/v4-core/contracts/libraries/TickMath.sol";

import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {PoolKey, PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {FeeLibrary} from "v4-core/libraries/FeeLibrary.sol";
import {DelegatedLiquidityHook, DelegatedFlexClient} from "src/DelegatedLiquidityHook.sol";
import {Deployers} from "@uniswap/v4-core/test/foundry-tests/utils/Deployers.sol";
import {PoolModifyPositionTest} from "@uniswap/v4-core/contracts/test/PoolModifyPositionTest.sol";
import {PoolSwapTest} from "@uniswap/v4-core/contracts/test/PoolSwapTest.sol";
import {IPoolManager} from "@uniswap/v4-core/contracts/interfaces/IPoolManager.sol";
import {HookTest} from "test/utils/HookTest.sol";
import {HookMiner} from "test/utils/HookMiner.sol";
import {IHooks} from "@uniswap/v4-core/contracts/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/contracts/libraries/Hooks.sol";

// Test adding to a pool
// Once added then you should be able to vote on a proposal

/// Hooks and test are based off of
/// https://github.com/naddison36/uniswap-v4-hooks/blob/f47e5bd14a551b3a44b737123150ae8cf29e25a1/test/Counter.t.sol
contract DelegatedLiquidityHookTest is HookTest, Deployers {
  using PoolIdLibrary for PoolKey;
  using CurrencyLibrary for Currency;

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
    // Create the pool
    // poolKey = PoolKey(
    //   Currency.wrap(address(erc20Votes)),
    //   Currency.wrap(address(erc20)),
    //   FeeLibrary.HOOK_SWAP_FEE_FLAG | FeeLibrary.HOOK_WITHDRAW_FEE_FLAG | uint24(0),
    //   60,
    //   IHooks(hook)
    // );
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

    // // Provide liquidity to the pool
    modifyPositionRouter.modifyPosition(
      poolKey, IPoolManager.ModifyPositionParams(-60, 60, 10 ether), ZERO_BYTES
    );
    modifyPositionRouter.modifyPosition(
      poolKey, IPoolManager.ModifyPositionParams(-120, 120, 10 ether), ZERO_BYTES
    );
    modifyPositionRouter.modifyPosition(
      poolKey,
      IPoolManager.ModifyPositionParams(
        TickMath.minUsableTick(60), TickMath.maxUsableTick(60), 10 ether
      ),
      ZERO_BYTES
    );
  }
}

// Test adding liquidity to the pool
// Test swapping
// Then test voting

contract AddLiquidity is DelegatedLiquidityHookTest {
  function testFuzz_addLiquidity() public {}
}
