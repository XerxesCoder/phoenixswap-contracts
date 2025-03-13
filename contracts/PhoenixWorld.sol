// SPDX-License-Identifier: MIT
pragma solidity >=0.8.9 <0.9.0;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "contracts/X2E.sol";

contract PhoenixWorld is Ownable, AccessControl {
    bytes32 public constant QUEST_CONTRACT_ROLE =
        keccak256("QUEST_CONTRACT_ROLE");
    // phoniex token contract
    IERC20 public constant phoenixToken =
        IERC20(0xB1A37b833fAFb705b0c90df0456eecB23937e976);
    // trasury address
    address public constant treasuryAddress =
        0x1F1d26ed9dF0E080ce576707f536bAad3D31CDDa;
    // X2E Pool address
    IX2EarnRewardsPool public constant x2EarnRewardsPool =
        IX2EarnRewardsPool(0x5F8f86B8D0Fa93cdaE20936d150175dF0205fB38);
    // X2E App id
    bytes32 public VBD_APP_ID =
        0x054720eddbf9b5e980255e6ffe32cd7781ef4fb4e542fef8dae7767dfe514531;

    uint256 public joinPrice = 500 ether;
    uint256 public referralShare = 50;
    uint256 public referralPoint = 2;
    uint256 private nextTribeId = 6;
    uint256 public registeredUsers;
    uint256 public rewardRate = 100;
    bool public isRewardsActive = true;

    struct UserProfile {
        string name;
        uint256 tribe;
        uint256 points;
        uint256[] achievements;
        address referrer;
        address[] referredUsers;
        bool isActive;
        uint256 rewards;
    }

    struct Tribe {
        string tribeName;
        string tribeDescription;
        uint256 numberMembers;
        bool isJoinable;
    }

    mapping(address => UserProfile) private userProfiles;
    mapping(uint256 => Tribe) private tribes;
    mapping(address => uint256) public totalRewardsClaimed;

    event ProfileActivated(address indexed user, string name, uint256 tribe);
    event Referral(
        address indexed user,
        address indexed referrer,
        uint256 referrerReward,
        uint256 treasuryAmount
    );
    event PointsUpdated(address indexed user, uint256 points);
    event AchievementUpdated(address indexed user, uint256 achievements);
    event TreasuryUpdated(address indexed newTreasury);
    event TribeAdded(
        uint256 tribeId,
        string tribeName,
        string tribeDescription
    );
    event TribeEdited(
        uint256 tribeId,
        string tribeName,
        string tribeDescription
    );
    event TribeJoinable(uint256 tribeId, bool isJoinable);
    event JoinPriceUpdated(uint256 newJoinPrice);
    event ReferralShareUpdated(uint256 newReferralShare);
    event ReferralPointUpdated(uint256 newReferralPoint);
    event RewardsUpdated(uint256 achivmentId, address user, uint256 reward);
    event RewardsClaimed(address user, uint256 reward);

    constructor() Ownable(msg.sender) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        tribes[0] = Tribe({
            tribeName: "Phoenix Flame",
            tribeDescription: "Rising from the ashes, focusing on long-term growth and resilience.",
            numberMembers: 0,
            isJoinable: true
        });
        tribes[1] = Tribe({
            tribeName: "Eclipse Traders",
            tribeDescription: "Masters of timing, specializing in arbitrage and high-frequency trading.",
            numberMembers: 0,
            isJoinable: true
        });
        tribes[2] = Tribe({
            tribeName: "Solar Stakers",
            tribeDescription: "Harnessing the power of passive income through staking and yield farming.",
            numberMembers: 0,
            isJoinable: true
        });
        tribes[3] = Tribe({
            tribeName: "Nova Innovators",
            tribeDescription: "Pioneers of DeFi, building and supporting cutting-edge protocols.",
            numberMembers: 0,
            isJoinable: true
        });
        tribes[4] = Tribe({
            tribeName: "Aurora Guardians",
            tribeDescription: "Protectors of the ecosystem, prioritizing security and risk management.",
            numberMembers: 0,
            isJoinable: true
        });
        tribes[5] = Tribe({
            tribeName: "Comet Chasers",
            tribeDescription: "Risk-takers chasing high-reward opportunities in new projects and tokens.",
            numberMembers: 0,
            isJoinable: true
        });
    }

    function getFunds() public view returns (uint256) {
        return x2EarnRewardsPool.availableFunds(VBD_APP_ID);
    }

    function claimReward() external {
        require(userProfiles[msg.sender].isActive, "User profile not active");
        require(isRewardsActive, "Reward Distribution is not active yet");
        uint256 rewardAmount = userProfiles[msg.sender].rewards;
        require(rewardAmount > 0, "No rewards to claim");
        uint256 availableFunds = getFunds();
        require(rewardAmount <= availableFunds, "Not enough Funds");

        x2EarnRewardsPool.distributeReward(
            VBD_APP_ID,
            rewardAmount,
            msg.sender,
            ""
        );
        totalRewardsClaimed[msg.sender] = rewardAmount;
        userProfiles[msg.sender].rewards = 0;
        emit RewardsClaimed(msg.sender, rewardAmount);
    }

    /**
     * @dev Grant the QUEST_CONTRACT_ROLE to a quest contract
     */
    function grantQuestContractRole(address _questContract) external onlyOwner {
        grantRole(QUEST_CONTRACT_ROLE, _questContract);
    }

    /**
     * @dev Grant the QUEST_CONTRACT_ROLE to a batch quest contract
     */
    function grantBatchQuestContractRole(address[] calldata _questContracts)
        external
        onlyOwner
    {
        for (uint256 i = 0; i < _questContracts.length; i++) {
            grantRole(QUEST_CONTRACT_ROLE, _questContracts[i]);
        }
    }

    /**
     * @dev Revoke the QUEST_CONTRACT_ROLE from a quest contract
     */
    function revokeQuestContractRole(address _questContract)
        external
        onlyOwner
    {
        revokeRole(QUEST_CONTRACT_ROLE, _questContract);
    }

    /**
     * @dev Revoke the QUEST_CONTRACT_ROLE from batch quest contract
     */
    function revokeBatchQuestContractRole(address[] calldata _questContracts)
        external
        onlyOwner
    {
        for (uint256 i = 0; i < _questContracts.length; i++) {
            revokeRole(QUEST_CONTRACT_ROLE, _questContracts[i]);
        }
    }

    /**
     * @dev to create a new tribe
     * callable only by owner
     */
    function addTribe(
        string memory _tribeName,
        string memory _tribeDescription,
        bool _isJoinable
    ) external onlyOwner {
        uint256 _tribeId = nextTribeId;
        tribes[_tribeId] = Tribe({
            tribeName: _tribeName,
            tribeDescription: _tribeDescription,
            numberMembers: 0,
            isJoinable: _isJoinable
        });
        nextTribeId++;
        emit TribeAdded(_tribeId, _tribeName, _tribeDescription);
    }

    /**
     * @dev to disable a tribe
     * callable only by owner
     */
    function setTribeJoinable(uint256 _tribeId, bool _isJoinable)
        external
        onlyOwner
    {
        require(
            bytes(tribes[_tribeId].tribeName).length != 0,
            "Tribe does not exist"
        );
        tribes[_tribeId].isJoinable = _isJoinable;
        emit TribeJoinable(_tribeId, _isJoinable);
    }

    /**
     * @dev to edit a tribe name and description
     * callable only by owner
     */
    function editTribe(
        uint256 _tribeId,
        string memory _tribeName,
        string memory _tribeDescription
    ) external onlyOwner {
        require(
            bytes(tribes[_tribeId].tribeName).length != 0,
            "Tribe does not exist"
        );
        tribes[_tribeId].tribeName = _tribeName;
        tribes[_tribeId].tribeDescription = _tribeDescription;
        emit TribeEdited(_tribeId, _tribeName, _tribeDescription);
    }

    /**
     * @dev return shares for referral and treasury
     */

    function calculateShares()
        internal
        view
        returns (uint256 treasuryShare, uint256 refShare)
    {
        refShare = (joinPrice * referralShare) / 100;
        treasuryShare = joinPrice - refShare;
        return (treasuryShare, refShare);
    }

    /**
     * @dev to join a tribe
     * @notice to prevent users from fake referral each user must pay a fee to join
     * @param _name username that will show in profile page
     * @param _tribe id for the tribe
     * @param _referrer referrer address, cannot referr themselves or null address
     */
    function enterTribe(
        string memory _name,
        uint256 _tribe,
        address _referrer
    ) external {
        require(
            bytes(tribes[_tribe].tribeName).length != 0,
            "Tribe does not exist"
        );
        require(tribes[_tribe].isJoinable, "Tribe is not joinable");
        require(
            !userProfiles[msg.sender].isActive,
            "Profile already activated"
        );
        require(
            phoenixToken.transferFrom(msg.sender, address(this), joinPrice),
            "Token transfer failed"
        );

        userProfiles[msg.sender] = UserProfile({
            name: _name,
            tribe: _tribe,
            points: 0,
            achievements: new uint256[](0),
            referrer: _referrer,
            referredUsers: new address[](0),
            isActive: true,
            rewards: 0
        });

        tribes[_tribe].numberMembers += 1;
        registeredUsers++;

        if (_referrer != address(0) && _referrer != msg.sender) {
            require(
                userProfiles[_referrer].isActive,
                "Referrer profile not active"
            );
            (uint256 treasuryShare, uint256 refShare) = calculateShares();
            require(
                phoenixToken.transfer(_referrer, refShare),
                "Referrer token transfer failed"
            );
            require(
                phoenixToken.transfer(treasuryAddress, treasuryShare),
                "Phoenix token transfer failed"
            );
            userProfiles[_referrer].points += referralPoint;
            userProfiles[_referrer].referredUsers.push(msg.sender);
            emit Referral(msg.sender, _referrer, refShare, treasuryShare);
        } else {
            require(
                phoenixToken.transfer(treasuryAddress, joinPrice),
                "Phoenix token transfer failed"
            );
        }
        emit ProfileActivated(msg.sender, _name, _tribe);
    }

    /**
     * @dev to update user points and achivments and increate ther rewards from X2E Pool
     * callable by quest contracts only
     */
    function updateAchievements(
        address _user,
        uint256 _achievements,
        uint256 _points
    ) external onlyRole(QUEST_CONTRACT_ROLE) {
        require(userProfiles[_user].isActive, "User profile not active");
        userProfiles[_user].achievements.push(_achievements);
        userProfiles[_user].points += _points;
        uint256 rewardForAchivment = (_points * 1e18) / rewardRate;
        userProfiles[_user].rewards += rewardForAchivment;
        emit AchievementUpdated(_user, _achievements);
        emit PointsUpdated(_user, _points);
        emit RewardsUpdated(_achievements, _user, rewardForAchivment);
    }

    function setReferralShare(uint256 _newReferralShare) external onlyOwner {
        require(
            _newReferralShare <= 100,
            "Referral share must be less than or equal to 100"
        );
        referralShare = _newReferralShare;
        emit ReferralShareUpdated(_newReferralShare);
    }

    function setReferralPoint(uint256 _newReferralPoint) external onlyOwner {
        referralPoint = _newReferralPoint;
        emit ReferralPointUpdated(_newReferralPoint);
    }

    function setRewardActive(bool _state) external onlyOwner {
        isRewardsActive = _state;
    }

    function setRewardRate(uint256 _rate) external onlyOwner {
        rewardRate = _rate;
    }

    function isUserActive(address _user) external view returns (bool) {
        return userProfiles[_user].isActive;
    }

    function getUserAchievements(address _user)
        external
        view
        returns (uint256[] memory)
    {
        return userProfiles[_user].achievements;
    }

    function getUserReferralLength(address _user)
        external
        view
        returns (uint256)
    {
        return userProfiles[_user].referredUsers.length;
    }

    // Function to get user profile data
    function getUserProfile(address _user)
        external
        view
        returns (
            string memory name,
            uint256 tribe,
            uint256 points,
            uint256[] memory achievements,
            address referrer,
            address[] memory referredUsers,
            bool isActive,
            uint256 rewards
        )
    {
        UserProfile memory profile = userProfiles[_user];
        return (
            profile.name,
            profile.tribe,
            profile.points,
            profile.achievements,
            profile.referrer,
            profile.referredUsers,
            profile.isActive,
            profile.rewards
        );
    }

    // Function to get tribe data
    function getTribe(uint8 _tribeId)
        external
        view
        returns (
            string memory tribeName,
            string memory tribeDescription,
            uint256 numberMembers,
            bool isJoinable
        )
    {
        Tribe memory tribe = tribes[_tribeId];
        return (
            tribe.tribeName,
            tribe.tribeDescription,
            tribe.numberMembers,
            tribe.isJoinable
        );
    }
}
