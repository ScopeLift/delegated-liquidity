// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PoolManager} from "v4-core/PoolManager.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";

import {MockToken} from "test/mocks/MockToken.sol";
import {UniswapV4Router} from "src/router/UniswapV4Router.sol";
import {UniswapV4Caller} from "src/router/UniswapV4Caller.sol";

/// @notice Deploys a pool manager, test tokens and a generic router.
/// @dev Minimal initialization. Inheriting contract should set up pools and provision liquidity
contract TestPoolManager {
  uint160 public constant MIN_PRICE_LIMIT = TickMath.MIN_SQRT_RATIO + 1;
  uint160 public constant MAX_PRICE_LIMIT = TickMath.MAX_SQRT_RATIO - 1;
  uint160 public constant SQRT_RATIO_1_TO_1 = 79_228_162_514_264_337_593_543_950_336;
  bytes constant EMPTY_RESULTS = hex"";
  uint256 constant MAX_AMOUNT = type(uint128).max;

  PoolManager manager;
  MockToken tokenA;
  MockToken tokenB;
  UniswapV4Router router;
  UniswapV4Caller caller;

  function poolInitialize() public {
    MockToken _tokenA = new MockToken("Token A", "TOKA", MAX_AMOUNT);
    MockToken _tokenB = new MockToken("Token B", "TOKB", MAX_AMOUNT);

    // pools alphabetically sort tokens by address
    // so align `token0` with `pool.token0` for consistency
    if (address(_tokenA) < address(_tokenB)) {
      tokenA = _tokenA;
      tokenB = _tokenB;
    } else {
      tokenA = _tokenB;
      tokenB = _tokenA;
    }

    manager = new PoolManager(500000);

    // Deploy a generic router
    router = new UniswapV4Router(manager);
    caller = new UniswapV4Caller(router, manager);

    tokenA.approve(address(router), MAX_AMOUNT);
    tokenB.approve(address(router), MAX_AMOUNT);
  }

  function onERC1155Received(address, address, uint256, uint256, bytes memory)
    public
    virtual
    returns (bytes4)
  {
    return this.onERC1155Received.selector;
  }

  function onERC1155BatchReceived(
    address,
    address,
    uint256[] memory,
    uint256[] memory,
    bytes memory
  ) public virtual returns (bytes4) {
    return this.onERC1155BatchReceived.selector;
  }
}
