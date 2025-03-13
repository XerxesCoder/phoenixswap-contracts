// SPDX-License-Identifier: MIT
pragma solidity >=0.8.9 <0.9.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IPhoenixWorld {
    function updateAchievements(
        address _user,
        uint256 _achievements,
        uint256 _points
    ) external;

    function isUserActive(address _user) external view returns (bool);

    function getUserReferralLength(address _user)
        external
        view
        returns (uint256);
}

interface IPhoenixVault {
    function getUserShares(address user) external view returns (uint256);
}

contract EternalStaker is Ownable {
    using SafeMath for uint256;
    IPhoenixWorld public immutable phoenixWorld;
    IPhoenixVault public immutable phoenixVault;
    bool public isQuestActive = true;
    uint256 public numberPoints = 20;
    uint256 public questId = 8;
    mapping(address => bool) public hasClaimed;

    constructor(address _world, address _vault) Ownable(msg.sender) {
        phoenixWorld = IPhoenixWorld(_world);
        phoenixVault = IPhoenixVault(_vault);
    }

    function isActiveUser(address _user) internal view returns (bool) {
        return phoenixWorld.isUserActive(_user);
    }

    function claimAchivment() external {
        require(isQuestActive, "Quest Not Active");
        require(!hasClaimed[msg.sender], "Already Claimed");
        require(isActiveUser(msg.sender), "You are not Join a tribe yet");

        bool isUserEligible = _canClaim(msg.sender);
        require(isUserEligible, "Not Eligible");
        hasClaimed[msg.sender] = true;
        phoenixWorld.updateAchievements(msg.sender, questId, numberPoints);
    }

    function setQuestState(bool _state) public onlyOwner {
        isQuestActive = _state;
    }

    /**
     * @notice Check if a user can claim.
     */
    function canClaim(address _userAddress) external view returns (bool) {
        return _canClaim(_userAddress);
    }

    /**
     * @notice Check if a user can claim.
     */
    function _canClaim(address _userAddress) internal view returns (bool) {
        if (hasClaimed[_userAddress] || !isQuestActive) {
            return false;
        } else {
            if (!isActiveUser(_userAddress)) {
                return false;
            } else if (
                phoenixVault.getUserShares(_userAddress) >=
                1000000000000000000000000
            ) {
                return true;
            } else {
                return false;
            }
        }
    }
}
