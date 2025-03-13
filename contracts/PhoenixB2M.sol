// SPDX-License-Identifier: MIT
pragma solidity >=0.8.9 <0.9.0;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IToken {
    function renounceOwnership() external;

    function mint(address to, uint256 amount) external;

    function burn(uint256 amount) external;

    function transfer(address to, uint256 amount) external returns (bool);

    function balanceOf(address account) external view returns (uint256);
}

interface IMasterFarmer {
    function phoenixBurn(uint256 _amount) external;
}

interface IPhoenixWorld {
    function isUserActive(address _user) external view returns (bool);

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
        );
}

contract PhoenixB2M is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct BonusLevel {
        uint256 pointsThreshold;
        uint256 bonusPercentage;
    }

    // Mapping to track contributions
    mapping(address => uint256) private _contributions;
    mapping(address => uint256) private _tokensMintable;
    mapping(address => bool) private _usersUsedBonus;

    // BurnToMint parameters
    IERC20 private constant _phoenixToken =
        IERC20(0x0000000000000000000000000000000000000001);
    IToken private constant _token =
        IToken(0x0000000000000000000000000000000000000001);
    address private _devsWallet;
    address private _daoWallet;
    address private _ecosystemWallet;
    uint256 private _rate;
    uint256 private _othersShare;
    uint256 private _totalPhoenixAmount;
    uint256 private _privatePhoenixAmount;
    uint256 private _openingTime;
    uint256 private _privateTime;
    uint256 private _closingTime;
    uint256 private _startClaimingTime;
    uint256 private _endClaimingTime;
    uint256 private _goal;
    bool private _goalReached;
    bool private _finalized;
    uint256 private _minBurn;
    uint256 private _maxBurn;
    uint256 private _maxSupply;
    uint256 private _totalMintable;
    uint256 private _usersMintable;
    uint256 private _othersMintable;
    BonusLevel[] public bonusLevels;
    uint256 private _totalContributionCounter;
    uint256 private _privateContributionCounter;
    uint256 private _totalUsersThatUsedBonus;
    uint256 private _totalBonus;
    IPhoenixWorld private constant _phoenixWorldContract =
        IPhoenixWorld(0x0000000000000000000000000000000000000001);
    IMasterFarmer private constant _masterFarmerContract =
        IMasterFarmer(0x0000000000000000000000000000000000000001);

    // Events
    event Contribute(
        address indexed beneficiary,
        uint256 value,
        uint256 amount,
        string phase
    );
    event GoalReached(uint256 amountRaised);
    event Refunded(address indexed beneficiary, uint256 amount);
    event Finalized(
        address indexed sender,
        uint256 amountBurned,
        uint256 amountMinted
    );
    event TokensClaimed(address indexed claimer, uint256 amount);
    event RemainingTokensBurned(uint256 amount);

    // Modifier to ensure actions are only performed while the burnToMint is active
    modifier onlyWhileActive() {
        require(_isBurnToMintActive(), "BurnToMint not active");
        _;
    }

    // Modifier to ensure actions are only performed while the burnToMint is closed
    modifier onlyWhileClosed() {
        require(!_isBurnToMintActive(), "BurnToMint still active");
        _;
    }

    // Modifier to ensure actions are performed before the burnToMint starts
    modifier beforeBurnToMintStart() {
        require(
            block.timestamp < _openingTime,
            "BurnToMint has already started"
        );
        _;
    }

    constructor() Ownable(msg.sender) {
        bonusLevels.push(BonusLevel(50, 1)); // Example: 1% bonus if points >= 50
        bonusLevels.push(BonusLevel(100, 2)); // Example: 2% bonus if points >= 100
        bonusLevels.push(BonusLevel(200, 3)); // Example: 3% bonus if points >= 200
        bonusLevels.push(BonusLevel(500, 4)); // Example: 4% bonus if points >= 500
        bonusLevels.push(BonusLevel(1000, 5)); // Example: 5% bonus if points >= 1000
    }

    // Function to contribute during the burnToMint
    function contribute(uint256 burnAmount)
        public
        onlyWhileActive
        nonReentrant
    {
        // Ensure that the sender has not already contributed
        require(
            _contributions[msg.sender] == 0,
            "User has already contributed"
        );

        // Ensure that the current contribution does not exceed the maximum cap
        require(burnAmount <= _maxBurn, "The contribution exceeds maximum cap");

        // Ensure that the current contribution meets the minimum cap
        require(
            burnAmount >= _minBurn,
            "The contribution is below minimum cap"
        );

        uint256 allowance = _phoenixToken.allowance(msg.sender, address(this));
        uint256 balance = _phoenixToken.balanceOf(msg.sender);

        require(allowance >= burnAmount, "Check the Phoenix token allowance");
        require(balance >= burnAmount, "Insufficient Phoenix balance");

        uint256 tokensRequested = (burnAmount * _rate) / (10**18);

        // Apply bonus percentage based on bonus levels
        uint256 bonusPercentage = calculateBonusPercentage(msg.sender);
        uint256 tokensToIssue = tokensRequested +
            ((tokensRequested * bonusPercentage) / 100);

        // Ensure total minted tokens (users + others) do not exceed hard cap
        require(
            _totalMintable + (tokensToIssue * (1 + _othersShare / 100)) <=
                _maxSupply,
            "Exceeds hard cap"
        );

        // Transfer Phoenix tokens to this contract
        _phoenixToken.safeTransferFrom(
            address(msg.sender),
            address(this),
            burnAmount
        );

        // Update state variables
        _totalPhoenixAmount += burnAmount;
        _usersMintable += tokensToIssue;
        _othersMintable += ((tokensToIssue * _othersShare) / 100);
        _totalMintable = _usersMintable + _othersMintable;
        _totalContributionCounter += 1;
        _contributions[msg.sender] = burnAmount;
        _tokensMintable[msg.sender] = tokensToIssue;

        if (bonusPercentage > 0 && !_usersUsedBonus[msg.sender]) {
            _totalUsersThatUsedBonus += 1;
            _usersUsedBonus[msg.sender] = true;
            _totalBonus += (tokensRequested * bonusPercentage) / 100;
        }

        // Emit event for contribution
        if (block.timestamp <= _privateTime) {
            _privatePhoenixAmount += burnAmount;
            _privateContributionCounter += 1;
            emit Contribute(msg.sender, burnAmount, tokensToIssue, "Private");
        } else {
            emit Contribute(msg.sender, burnAmount, tokensToIssue, "Public");
        }
        // Check if goal is reached
        if (!_goalReached && _totalPhoenixAmount >= _goal) {
            _goalReached = true;
            emit GoalReached(_totalPhoenixAmount);
        }
    }

    // Function to calculate bonus percentage based on user points
    function calculateBonusPercentage(address user)
        private
        view
        returns (uint256)
    {
        uint256 userPoints = 0;
        uint256 bonusPercentage = 0;

        if (_phoenixWorldContract.isUserActive(user)) {
            userPoints = getUserPoints(user);
            for (uint256 i = 0; i < bonusLevels.length; i++) {
                if (userPoints >= bonusLevels[i].pointsThreshold) {
                    bonusPercentage = bonusLevels[i].bonusPercentage;
                }
            }
        }

        return bonusPercentage;
    }

    // Function to retrieve user points from PhoenixWorld contract
    function getUserPoints(address user) private view returns (uint256) {
        (, , uint256 points, , , , ,) = _phoenixWorldContract.getUserProfile(
            user
        );
        return points;
    }

    // Function for investors to claim refund if the goal is not reached
    function claimRefund() public onlyWhileClosed nonReentrant {
        require(!_goalReached, "Goal reached, no refunds available");
        uint256 amount = _contributions[msg.sender];
        require(amount > 0, "No funds to refund");

        // Transfer Phoenix to msg.sender
        _contributions[msg.sender] = 0;
        _phoenixToken.safeTransfer(msg.sender, amount);

        emit Refunded(msg.sender, amount);
    }

    // Public function to finalize the burnToMint if the goal is reached
    function finalize() public onlyWhileClosed nonReentrant {
        require(_goalReached, "The base goal hasn't been reached yet.");
        require(!_finalized, "BurnToMint has already finalized");

        _masterFarmerContract.phoenixBurn(_totalPhoenixAmount);
        _token.mint(address(this), _usersMintable);
        _token.mint(address(_devsWallet), (_othersMintable * 50) / 100);
        _token.mint(address(_daoWallet), (_othersMintable * 20) / 100);
        _token.mint(address(_ecosystemWallet), (_othersMintable * 30) / 100);

        _finalized = true;

        // Set the startClaiming time to 30 minutes after finalizing
        _startClaimingTime = block.timestamp + 15 * 60; // 15 minutes in seconds

        // Renounce ownership of token
        _token.renounceOwnership();

        emit Finalized(
            msg.sender,
            _totalPhoenixAmount,
            _usersMintable + _othersMintable
        );
    }

    // Function for investors to claim tokens after the burnToMint
    function claimTokens() public onlyWhileClosed nonReentrant {
        require(_goalReached, "The base goal hasn't been reached yet.");
        require(_finalized, "BurnToMint has not finalized");
        require(_tokensMintable[msg.sender] > 0, "No tokens to claim");
        require(
            block.timestamp <= _endClaimingTime,
            "The time for claiming has already passed"
        );
        // Ensure that the current time is after the startClaiming time
        require(
            block.timestamp >= _startClaimingTime,
            "Claiming period has not started yet"
        );

        uint256 tokensToClaim = _tokensMintable[msg.sender];
        _tokensMintable[msg.sender] = 0;

        bool success = _token.transfer(msg.sender, tokensToClaim);
        require(success, "Token transfer failed");

        emit TokensClaimed(msg.sender, tokensToClaim);
    }

    // Function to burn remaining tokens after claiming dead line
    function burnRemainingTokens()
        public
        onlyOwner
        onlyWhileClosed
        nonReentrant
    {
        require(_goalReached, "The base goal hasn't been reached yet.");
        require(_finalized, "BurnToMint has not finalized");
        require(
            block.timestamp > _endClaimingTime,
            "Burning must be after claiming time"
        );
        uint256 remainingTokens = _token.balanceOf(address(this));
        require(remainingTokens > 0, "No remaining tokens to burn");

        _token.burn(remainingTokens);

        emit RemainingTokensBurned(remainingTokens);
    }

    // Function to check if the burnToMint is active
    function _isBurnToMintActive() internal view returns (bool) {
        return
            block.timestamp >= _openingTime && block.timestamp <= _closingTime;
    }

    // Getter functions for various burnToMint parameters
    function getRate() public view returns (uint256) {
        return _rate;
    }

    function getOthersShare() public view returns (uint256) {
        return _othersShare;
    }

    function getTotalPhoenixBurned() public view returns (uint256) {
        return _totalPhoenixAmount;
    }

    function getPrivatePhoenixBurned() public view returns (uint256) {
        return _privatePhoenixAmount;
    }

    function getOpeningTime() public view returns (uint256) {
        return _openingTime;
    }

    function getPrivateTime() public view returns (uint256) {
        return _privateTime;
    }

    function getClosingTime() public view returns (uint256) {
        return _closingTime;
    }

    function getStartClaimingTime() public view returns (uint256) {
        return _startClaimingTime;
    }

    function getEndClaimingTime() public view returns (uint256) {
        return _endClaimingTime;
    }

    function getGoal() public view returns (uint256) {
        return _goal;
    }

    function isGoalReached() public view returns (bool) {
        return _goalReached;
    }

    function isFinalized() public view returns (bool) {
        return _finalized;
    }

    function getminBurn() public view returns (uint256) {
        return _minBurn;
    }

    function getmaxBurn() public view returns (uint256) {
        return _maxBurn;
    }

    function getMaxSupply() public view returns (uint256) {
        return _maxSupply;
    }

    function getTotalMintable() public view returns (uint256) {
        return _totalMintable;
    }

    function getUsersMintable() public view returns (uint256) {
        return _usersMintable;
    }

    function getOthersMintable() public view returns (uint256) {
        return _othersMintable;
    }

    function getBonusLevelCount() public view returns (uint256) {
        return bonusLevels.length;
    }

    function getContributions(address user) public view returns (uint256) {
        return _contributions[user];
    }

    function getTokensMintable(address user) public view returns (uint256) {
        return _tokensMintable[user];
    }

    function getTokenContract() public pure returns (address) {
        return address(_token);
    }

    function getDevsWallet() public view returns (address) {
        return address(_devsWallet);
    }

    function getDaoWallet() public view returns (address) {
        return address(_daoWallet);
    }

    function getEcosystemWallet() public view returns (address) {
        return address(_ecosystemWallet);
    }

    function isBurnToMintActive() public view returns (bool) {
        return _isBurnToMintActive();
    }

    function getTotalContributionCounter() public view returns (uint256) {
        return _totalContributionCounter;
    }

    function getPrivateContributionCounter() public view returns (uint256) {
        return _privateContributionCounter;
    }

    function getTotalUsersThatUsedBonus() public view returns (uint256) {
        return _totalUsersThatUsedBonus;
    }

    function getTotalBonus() public view returns (uint256) {
        return _totalBonus;
    }

    // Setter function for the devs wallet address
    function setWallets(
        address devsWallet,
        address daoWallet,
        address ecosystemWallet
    ) public onlyOwner {
        require(
            devsWallet != address(0) &&
                daoWallet != address(0) &&
                ecosystemWallet != address(0),
            "Invalid wallet addresses"
        );
        _devsWallet = devsWallet;
        _daoWallet = daoWallet;
        _ecosystemWallet = ecosystemWallet;
    }

    // Setter functions for burnToMint parameters, to be called before the burnToMint starts
    function setRate(uint256 rate) public onlyOwner beforeBurnToMintStart {
        require(rate > 0, "BurnToMint rate must be greater than zero");
        _rate = rate;
    }

    function setOthersShare(uint256 othersShare)
        public
        onlyOwner
        beforeBurnToMintStart
    {
        require(
            othersShare >= 0,
            "OthersShare must be equal or greater than zero"
        );
        _othersShare = othersShare;
    }

    function setOpeningTime(uint256 openingTime)
        public
        onlyOwner
        beforeBurnToMintStart
    {
        require(
            openingTime >= block.timestamp,
            "Opening time must be in the future"
        );
        _openingTime = openingTime;
    }

    function setPrivateTime(uint256 privateTime)
        public
        onlyOwner
        beforeBurnToMintStart
    {
        require(
            privateTime > _openingTime,
            "Private time must be after opening time"
        );
        _privateTime = privateTime;
    }

    function setClosingTime(uint256 closingTime)
        public
        onlyOwner
        beforeBurnToMintStart
    {
        require(
            closingTime > _privateTime,
            "Closing time must be after private time"
        );
        _closingTime = closingTime;
    }

    function setEndClaimingTime(uint256 endClaimingTime) public onlyOwner {
        require(
            endClaimingTime > _closingTime,
            "End Claiming time must be after closing time"
        );
        require(
            _endClaimingTime > block.timestamp,
            "The time for claiming has already passed"
        );
        require(
            endClaimingTime > _endClaimingTime,
            "New end claiming time must be after previous end claiming time"
        );
        _endClaimingTime = endClaimingTime;
    }

    function setGoal(uint256 goal) public onlyOwner beforeBurnToMintStart {
        require(goal > 0, "Goal must be greater than zero");
        _goal = goal;
    }

    function setminBurn(uint256 minBurn)
        public
        onlyOwner
        beforeBurnToMintStart
    {
        require(minBurn > 0, "Minimum cap must be greater than zero");
        _minBurn = minBurn;
    }

    function setmaxBurn(uint256 maxBurn)
        public
        onlyOwner
        beforeBurnToMintStart
    {
        require(
            maxBurn > _minBurn,
            "Maximum cap must be greater than minimum cap"
        );
        _maxBurn = maxBurn;
    }

    function setMaxSupply(uint256 maxSupply)
        public
        onlyOwner
        beforeBurnToMintStart
    {
        require(maxSupply > 0, "Hard cap must be greater than zero");
        _maxSupply = maxSupply;
    }
}
