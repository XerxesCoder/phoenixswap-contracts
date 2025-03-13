// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract PhoenixLaunchpad is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Presale {
        uint256 id;
        address owner;
        address tokenAddress;
        uint256 goal; // Goal in tokens
        uint256 deadline;
        uint256 minBuy; // Min VET contribution
        uint256 maxBuy; // Max VET contribution
        uint256 ratio; // Tokens per VET
        uint256 raisedVET; // Total VET raised
        uint256 totalTokenAllocated; // Total tokens allocated to buyers
        bool isWithdrawn;
        string website;
        string twitter;
        string telegram;
    }

    uint256 public presaleCount;
    mapping(uint256 => Presale) public presales;
    mapping(address => uint256) public tokenToPresaleId;
    // returns a user contributions in VET
    mapping(uint256 => mapping(address => uint256)) public contributions;
    // returns a user allocated Tokens
    mapping(uint256 => mapping(address => uint256)) public allocatedTokens;
    // returns a user total presale participation
    mapping(address => uint256[]) public userPresaleIds;

    address public immutable treasury;
    uint256 public FEE_PERCENT = 3;
    uint256 public MAX_DAYS_PRESALE = 10;

    event TokensClaimed(uint256 indexed id, address buyer, uint256 tokenAmount);
    event PresaleCreated(uint256 indexed id, address indexed owner);
    event TokensPurchased(
        uint256 indexed id,
        address buyer,
        uint256 vetAmount,
        uint256 tokenAmount
    );
    event Refunded(uint256 indexed id, address user, uint256 amount);
    event WithdrawFund(
        uint256 indexed id,
        address owner,
        uint256 amount,
        uint256 fee
    );

    constructor(address _treasury) Ownable(msg.sender) {
        require(_treasury != address(0), "Invalid treasury address");
        treasury = _treasury;
    }

    /**
     * @dev create a presale by owner only
     *
     * @param _tokenAddress The address of the token
     * @param _goalTokens total amount of tokens in wei to be send to launchpad for sale
     * @param _daysUntilDeadline number of days till presale ended.
     * @param _minBuy min Vet amount to buy in wei.
     * @param _maxBuy max Vet amount to buy in wei.
     * @param _ratio tokens per Vet e.g 2000 - value must be in VET NOT WEI.
     */
    function createPresale(
        address _tokenAddress,
        address _presaleOwner,
        uint256 _goalTokens,
        uint256 _daysUntilDeadline,
        uint256 _minBuy,
        uint256 _maxBuy,
        uint256 _ratio,
        string memory _website,
        string memory _twitter,
        string memory _telegram
    ) external onlyOwner {
        require(_tokenAddress != address(0), "Invalid token address");
        require(
            _daysUntilDeadline > 0 && _daysUntilDeadline <= MAX_DAYS_PRESALE,
            "Deadline must be 1-10 days"
        );
        require(_minBuy <= _maxBuy, "Invalid buy limits");
        require(_goalTokens > 0 && _ratio > 0, "Invalid parameters");

        uint256 deadline = block.timestamp + (_daysUntilDeadline * 1 days);

        // Transfer tokens from owner to contract
        IERC20(_tokenAddress).safeTransferFrom(
            msg.sender,
            address(this),
            _goalTokens
        );

        presaleCount++;
        presales[presaleCount] = Presale({
            id: presaleCount,
            owner: _presaleOwner,
            tokenAddress: _tokenAddress,
            goal: _goalTokens,
            deadline: deadline,
            minBuy: _minBuy,
            maxBuy: _maxBuy,
            ratio: _ratio,
            raisedVET: 0,
            totalTokenAllocated: 0,
            isWithdrawn: false,
            website: _website,
            twitter: _twitter,
            telegram: _telegram
        });

        tokenToPresaleId[_tokenAddress] = presaleCount;
        emit PresaleCreated(presaleCount, msg.sender);
    }

    /**
     * @dev buy tokens with VET
     *
     * @param _presaleId id of presale
     * @notice VET send to contract should be > minbuy
     * @notice can buy only if goal not reached and deadline is not met
     */

    function buyTokens(uint256 _presaleId) external payable nonReentrant {
        Presale storage presale = presales[_presaleId];
        require(block.timestamp < presale.deadline, "Presale ended");
        require(msg.value >= presale.minBuy, "Below minimum buy");
        require(
            contributions[_presaleId][msg.sender] + msg.value <= presale.maxBuy,
            "Exceeds max buy"
        );

        uint256 tokensToAllocate = msg.value * presale.ratio;
        require(
            presale.totalTokenAllocated + tokensToAllocate <= presale.goal,
            "Exceeds token goal"
        );

        if (contributions[_presaleId][msg.sender] == 0) {
            userPresaleIds[msg.sender].push(_presaleId);
        }

        contributions[_presaleId][msg.sender] += msg.value;
        allocatedTokens[_presaleId][msg.sender] += tokensToAllocate;
        presale.raisedVET += msg.value;
        presale.totalTokenAllocated += tokensToAllocate;

        emit TokensPurchased(
            _presaleId,
            msg.sender,
            msg.value,
            tokensToAllocate
        );
    }

    /**
     * @dev claim tokens after presale ended
     *
     * @param _presaleId id of presale
     * @notice can claim only if goal reached and deadline  met
     */

    function claimTokens(uint256 _presaleId) external nonReentrant {
        Presale storage presale = presales[_presaleId];
        require(block.timestamp >= presale.deadline, "Presale ongoing");
        require(presale.totalTokenAllocated >= presale.goal, "Goal not met");

        uint256 tokensToClaim = allocatedTokens[_presaleId][msg.sender];
        require(tokensToClaim > 0, "No tokens to claim");

        allocatedTokens[_presaleId][msg.sender] = 0;
        IERC20(presale.tokenAddress).safeTransfer(msg.sender, tokensToClaim);

        emit TokensClaimed(_presaleId, msg.sender, tokensToClaim);
    }

    /**
     * @dev refund tokens if presale not succeed
     *
     * @param _presaleId id of presale
     * @notice can refund only if goal not reached and deadline ends
     */

    function claimRefund(uint256 _presaleId) external nonReentrant {
        Presale storage presale = presales[_presaleId];
        require(block.timestamp >= presale.deadline, "Presale ongoing");
        require(presale.totalTokenAllocated < presale.goal, "Goal met");

        uint256 amount = contributions[_presaleId][msg.sender];
        require(amount > 0, "No contribution");

        contributions[_presaleId][msg.sender] = 0;
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Refund failed");

        emit Refunded(_presaleId, msg.sender, amount);
    }

    /**
     * @dev claim vets raised for a presale (Only by presale owner)
     *
     * @param _presaleId id of presale
     * @notice presale owner can only withdraw VET and goal must met and deadline should end
     * @notice platform fee will be duducted from total raised and send to trasury
     */

    function withdrawFunds(uint256 _presaleId) external nonReentrant {
        Presale storage presale = presales[_presaleId];
        require(msg.sender == presale.owner, "Unauthorized");
        require(block.timestamp >= presale.deadline, "Presale ongoing");
        require(!presale.isWithdrawn, "Funds already withdrawn");
        require(presale.totalTokenAllocated >= presale.goal, "Goal not met");

        uint256 platformFee = (presale.raisedVET * FEE_PERCENT) / 100;
        uint256 ownerVET = presale.raisedVET - platformFee;

        // Transfer fee to treasury
        (bool feesuccess, ) = treasury.call{value: platformFee}("");
        require(feesuccess, "Fee transfer failed");
        // Transfer fee to treasury
        (bool success, ) = presale.owner.call{value: ownerVET}("");
        require(success, "Fee transfer failed");
        emit WithdrawFund(_presaleId, msg.sender, ownerVET, platformFee);
    }

    function getPresaleTokenBalance(uint256 _presaleId)
        public
        view
        returns (uint256)
    {
        Presale memory presale = presales[_presaleId];
        return IERC20(presale.tokenAddress).balanceOf(address(this));
    }

    function setMaxDays(uint256 _days) public onlyOwner {
        require(_days <= 14, "Days cannot exceeds 14");
        require(_days > 0, "Days cannot be zero");
        MAX_DAYS_PRESALE = _days;
    }

    function setMaxFee(uint256 _fee) public onlyOwner {
        require(_fee <= 5, "Fee cannot exceeds 5%");
        require(_fee > 0, "Fee cannot be zero");
        FEE_PERCENT = _fee;
    }

    function getPresaleByTokenAddress(address token)
        external
        view
        returns (Presale memory)
    {
        uint256 presaleId = tokenToPresaleId[token];
        require(presaleId != 0, "Presale not found");
        return presales[presaleId];
    }

    function getUserPresaleIds(address user)
        external
        view
        returns (uint256[] memory)
    {
        return userPresaleIds[user];
    }

    receive() external payable {
        revert("Direct VET transfers not allowed");
    }
}
