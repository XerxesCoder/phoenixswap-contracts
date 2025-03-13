// SPDX-License-Identifier: MIT

pragma solidity >=0.8.9 <0.9.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract PhoniexSwapToken is ERC20, Ownable {
    uint256 private constant MAX_SUPPLY = 2000000000 ether;
    uint256 public _totalMinted = 0;
    uint256 public _totalBurned = 0;
    address public treasuryAddr;
    event Mint(address indexed sender, address indexed to, uint256 amount);
    event Burn(address indexed sender, address indexed from, uint256 amount);

    constructor(address _trasury) ERC20("PhoenixSwap Token", "PHNX") Ownable(msg.sender)  {
        treasuryAddr = _trasury;
        _mint(_trasury, 200000000 ether); // mint 10% - 7% for ido and 3% for team 
        _totalMinted += 200000000 ether;
        emit Mint(msg.sender, _trasury, 200000000 ether); 

    }

    function maxSupply() public pure returns (uint256) {
        return MAX_SUPPLY;
    }

    function totalMinted() public view returns (uint256) {
        return _totalMinted;
    }

    function totalBurned() public view returns (uint256) {
        return _totalBurned;
    }


    /// @notice Must only be called by MasterFarmer.
    function mint(address _to, uint256 _amount) public onlyOwner {
        require(
            totalSupply() + _amount <= MAX_SUPPLY,
            "ERC20: minting more than maxSupply"
        );
        _mint(_to, _amount);
        _totalMinted += _amount;
        emit Mint(msg.sender, _to, _amount);
    }

    /// @notice Burns only from treasury address. Must only be called by MasterFarmer.
    function burn(address _from, uint256 _amount) public onlyOwner {
        _burn(_from, _amount);
        _totalBurned += _amount;
        emit Burn(msg.sender, _from, _amount);
    }
}
