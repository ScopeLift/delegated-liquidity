// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "openzeppelin/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
  constructor(string memory name, string memory symbol, uint256 initAmount) ERC20(name, symbol) {
    _mint(msg.sender, initAmount);
  }

  function mint(address account, uint256 amount) public {
    _mint(account, amount);
  }
}
