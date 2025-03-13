// SPDX-License-Identifier: MIT
pragma solidity >=0.8.9 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol"; 
import "@openzeppelin/contracts/interfaces/IERC20.sol"; 

contract PhoenixBank is ERC20, Ownable {
    IERC20 public phoenix;

    event Mint(address indexed sender, address indexed to, uint256 amount);
    event Burn(address indexed sender, address indexed from, uint256 amount);

    constructor(address _phoenix) ERC20("PhoenixBank Token", "xPHNX") Ownable(msg.sender) { 
        phoenix = IERC20(_phoenix);
    }

    /// @notice Must only be called by the owner (MasterFarmer).
    function mint(address _to, uint256 _amount) public onlyOwner {
        _mint(_to, _amount); // Mint xPhoenix tokens
        emit Mint(msg.sender, _to, _amount);
    }

    /// @notice Must only be called by the owner (MasterFarmer).
    function burn(address _from, uint256 _amount) public onlyOwner {
        _burn(_from, _amount); // Burn xPhoenix tokens
        emit Burn(msg.sender, _from, _amount);
    }

    /// @notice Safe transfer function for Phoenix tokens.
    function safePhoenixTransfer(address _to, uint256 _amount) public onlyOwner {
        uint256 phoenixBal = phoenix.balanceOf(address(this)); // Get Phoenix balance
        if (_amount > phoenixBal) {
            phoenix.transfer(_to, phoenixBal); // Transfer full balance if amount exceeds
        } else {
            phoenix.transfer(_to, _amount); // Transfer specified amount
        }
    }
}