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

import {IFractionalGovernor} from "flexible-voting/interfaces/IFractionalGovernor.sol";

contract DelegatedLiquidityHook is BaseHook {
  using PoolIdLibrary for PoolKey;
  using Checkpoints for Checkpoints.History;

  mapping(bytes32 positionId => Checkpoints.History) internal positionCheckpoints;
  Checkpoints.History internal poolCheckpoints;

  constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

  /*
    Our contract stores the gov token address (part of constructor)
    Receives the afterInitialize callback and records which token (token0 or token1) is the gov token
    Uses this to return appropriate values in other methods
   */

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
    PoolKey calldata key,
    IPoolManager.ModifyPositionParams calldata modifyParams,
    BalanceDelta,
    bytes calldata
  ) external override returns (bytes4 selector) {
    /*
     1. Save tickLower & tickUpper into a mapping for this position id
     2. Checkpoint position liquidity
     3. Checkpoint pool price
    */
    // checkpoint position
    bytes32 positionKey =
      keccak256(abi.encodePacked(sender, modifyParams.tickLower, modifyParams.tickUpper));
    // get current liquidity
    uint256 liquidity = positionCheckpoints[positionKey].latest();
    // Do we track the liquidity or use the balance delta
    uint256 liquidityNext = modifyParams.liquidityDelta < 0
      ? liquidity - uint256(-modifyParams.liquidityDelta)
      : liquidity + uint256(modifyParams.liquidityDelta);

    positionCheckpoints[positionKey].push(liquidityNext);

    (uint160 price,,,) = poolManager.getSlot0(key.toId());
    poolCheckpoints.push(price);

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
    poolCheckpoints.push(price);
    selector = BaseHook.afterSwap.selector;
  }
}

contract DelegatedFlexClient is DelegatedLiquidityHook {
  using Checkpoints for Checkpoints.History;
  /// @dev Data structure to store vote preferences expressed by depositors.
  // TODO: Does it matter if we use a uint128 vs a uint256?

  struct ProposalVote {
    uint128 againstVotes;
    uint128 forVotes;
    uint128 abstainVotes;
  }

  /// @dev The voting options corresponding to those used in the Governor.
  enum VoteType {
    Against,
    For,
    Abstain
  }

  /// @dev Thrown when an address has no voting weight on a proposal.
  error NoWeight();

  /// @dev Thrown when an address has already voted.
  error AlreadyVoted();

  /// @dev Thrown when an invalid vote is cast.
  error InvalidVoteType();

  /// @dev Thrown when proposal is inactive.
  error ProposalInactive();

  /// @notice The governor contract associated with this governance token. It
  /// must be one that supports fractional voting, e.g. GovernorCountingFractional.
  IFractionalGovernor public immutable GOVERNOR;

  /// @notice A mapping of proposal to a mapping of voter address to boolean indicating whether a
  /// voter has voted or not.
  mapping(uint256 proposalId => mapping(bytes32 positionKey => bool)) private
    _proposalVotersHasVoted;

  /// @notice A mapping of proposal id to proposal vote totals.
  mapping(uint256 proposalId => ProposalVote) public proposalVotes;

  /// @param _governor The address of the flex-voting-compatible governance contract.
  constructor(address _governor, IPoolManager _poolManager) DelegatedLiquidityHook(_poolManager) {
    GOVERNOR = IFractionalGovernor(_governor);
  }

  function getPastBalance(bytes32 positionId, uint256 blockNumber)
    public
    returns (uint256, uint256)
  {
    /*
     1. Lookup the tick boundries for this position Id
     2. Lookup checkpointed liquidity for this position Id
     3. Lookup checkpointed price for total pool
     4. Pass all 4 params to LiquidityAmounts.getAmountsForLiquidity to get the amount of Gov tokens the user is entitled to vote with
     5. Return either amount0 or amount1 from step 4 based on which token was recorded as Gov token during initialize callback
    */
    uint160 price = poolCheckpoints.getAtProbablyRecentBlock(blockNumber);
    uint256 liquidity = positionCheckpoints[positionId].getAtProbablyRecentBlock(blockNumber);
    return LiquidityAmounts.getAmountsForLiquidity(
      price, positionId[21:24], positionId[24:27], liquidity
    ); // Slice these using bit operations
  }

  /// @notice Where a user can express their vote based on their L2 token voting power.
  /// @param proposalId The id of the proposal to vote on.
  /// @param support The type of vote to cast.
  function castVote(uint256 proposalId, bytes32 positionId, VoteType support)
    public
    returns (uint256)
  {
    if (!proposalVoteActive(proposalId)) revert ProposalInactive();
    if (_proposalVotersHasVoted[proposalId][positionId]) revert AlreadyVoted();
    _proposalVotersHasVoted[proposalId][positionId] = true;

    uint256 weight = 1; // Get weight from the pool
    if (weight == 0) revert NoWeight();

    if (support == VoteType.Against) {
      proposalVotes[proposalId].againstVotes += SafeCast.toUint128(weight);
    } else if (support == VoteType.For) {
      proposalVotes[proposalId].forVotes += SafeCast.toUint128(weight);
    } else if (support == VoteType.Abstain) {
      proposalVotes[proposalId].abstainVotes += SafeCast.toUint128(weight);
    } else {
      revert InvalidVoteType();
    }
    // emit VoteCast(msg.sender, proposalId, support, weight);
    return weight;
  }

  /// @notice Method which returns the deadline for token holders to express their voting
  /// preferences to this Aggregator contract. Will always be before the Governor's corresponding
  /// proposal deadline.
  /// @param proposalId The ID of the proposal.
  /// @return _lastVotingBlock the voting block where L2 voting ends.
  function internalVotingPeriodEnd(uint256 proposalId)
    public
    view
    returns (uint256 _lastVotingBlock)
  {
    return GOVERNOR.proposalSnapshot(proposalId);
  }

  function proposalVoteActive(uint256 proposalId) public view returns (bool active) {
    uint256 deadline = GOVERNOR.proposalSnapshot(proposalId);
    return block.number <= internalVotingPeriodEnd(proposalId) && block.number >= deadline; // should
      // be changed to clock
  }
}
