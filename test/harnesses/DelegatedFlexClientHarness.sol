// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {CommonBase} from "forge-std/Base.sol";
import {DelegatedFlexClient} from "src/DelegatedLiquidityHook.sol";
import {MockToken} from "test/mocks/MockToken.sol";
import {Governor} from "openzeppelin-flexible-voting/governance/Governor.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {IGovernor} from "openzeppelin-flexible-voting/governance/Governor.sol";
import {IPoolManager} from "@uniswap/v4-core/contracts/interfaces/IPoolManager.sol";

contract DelegatedFlexClientHarness is DelegatedFlexClient, CommonBase {
  Governor gov;

  constructor(address _governor, IPoolManager _poolManager)
    DelegatedFlexClient(_governor, _poolManager)
  {
    gov = Governor(payable(_governor));
  }

  function _createExampleProposal(address l1Erc20) internal returns (uint256) {
    bytes memory proposalCalldata = abi.encode(MockToken.mint.selector, address(GOVERNOR), 100_000);

    address[] memory targets = new address[](1);
    bytes[] memory calldatas = new bytes[](1);
    uint256[] memory values = new uint256[](1);

    targets[0] = address(l1Erc20);
    calldatas[0] = proposalCalldata;
    values[0] = 0;

    return
      IGovernor(address(GOVERNOR)).propose(targets, values, calldatas, "Proposal: To inflate token");
  }

  function createProposalVote(address l1Erc20) public returns (uint256) {
    uint256 _proposalId = _createExampleProposal(l1Erc20);
    return _proposalId;
  }

  function _jumpToActiveProposal(uint256 proposalId) public {
    uint256 _deadline = GOVERNOR.proposalDeadline(proposalId);
    vm.roll(_deadline - 1);
  }
}
