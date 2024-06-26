// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^4.9.6
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract Oya is ERC20, Ownable, ERC20Permit {

  constructor() ERC20("Oya", "OYA") Ownable() ERC20Permit("Oya") {
    _mint(msg.sender, 1_000_000_000 * 10 ** decimals());
  }

  function mint(address to, uint256 amount) public onlyOwner {
    _mint(to, amount);
  }

}
