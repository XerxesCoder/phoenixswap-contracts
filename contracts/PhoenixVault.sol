// SPDX-License-Identifier: MIT
pragma solidity >=0.8.9 <0.9.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

interface IMasterFarmer {
    function deposit(uint256 _pid, uint256 _amount) external;

    function withdraw(uint256 _pid, uint256 _amount) external;

    function enterStaking(uint256 _amount) external;

    function leaveStaking(uint256 _amount) external;

    function pendingPhoenix(uint256 _pid, address _user)
        external
        view
        returns (uint256);

    function userInfo(uint256 _pid, address _user)
        external
        view
        returns (uint256, uint256);

    function phoenixBurn(uint256 _amount) external;

    function emergencyWithdraw(uint256 _pid) external;
}

contract PhoenixVault is Ownable, Pausable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    struct UserInfo {
        uint256 shares; // number of shares for a user
        uint256 lastDepositedTime; // keeps track of deposited time for potential penalty
        uint256 phoenixAtLastUserAction; // keeps track of Phoenix deposited at the last user action
        uint256 lastUserActionTime; // keeps track of the last user action time
    }
    //Phoenix Token
    IERC20 public immutable token;
    //Bank Token xPHNX
    IERC20 public immutable receiptToken;
    // masterfarmer
    IMasterFarmer public immutable masterfarmer;

    mapping(address => UserInfo) public userInfo;

    uint256 public totalShares;
    uint256 public lastHarvestedTime;
    address public admin;

    uint256 public constant MAX_PERFORMANCE_FEE = 500; // 5%
    uint256 public constant MAX_CALL_FEE = 100; // 1%
    uint256 public constant MAX_WITHDRAW_FEE = 100; // 1%
    uint256 public constant MAX_WITHDRAW_FEE_PERIOD = 72 hours; // 3 days

    uint256 public performanceFee = 200; // 2%
    uint256 public callFee = 25; // 0.25%
    uint256 public withdrawFee = 50; // 0.5%
    uint256 public withdrawFeePeriod = 72 hours; // 3 days

    event Deposit(
        address indexed sender,
        uint256 amount,
        uint256 shares,
        uint256 lastDepositedTime
    );
    event Withdraw(address indexed sender, uint256 amount, uint256 shares);
    event Harvest(
        address indexed sender,
        uint256 performanceFee,
        uint256 callFee
    );
    event SetAdmin(address indexed sender, address indexed newAdmin);
    event SetPerformanceFee(
        address indexed sender,
        uint256 indexed newPerformanceFee
    );
    event SetCallFee(address indexed sender, uint256 indexed newCallFee);
    event SetWithdrawFee(
        address indexed sender,
        uint256 indexed newWithdrawFee
    );
    event SetWithdrawFeePeriod(
        address indexed sender,
        uint256 indexed newWithdrawFeePeriod
    );
    event EmergencyWithdraw(address indexed sender);
    event Pause();
    event Unpause();

    constructor(
        address _masterfarmer,
        address _phnx,
        address _xphnx
    ) Ownable(msg.sender) {
        masterfarmer = IMasterFarmer(_masterfarmer);
        receiptToken = IERC20(_xphnx);
        token = IERC20(_phnx);
        admin = msg.sender;
        uint256 expectedAllowance = type(uint256).max;
        IERC20(token).forceApprove(address(masterfarmer), expectedAllowance);
        require(
            token.allowance(address(this), address(masterfarmer)) ==
                expectedAllowance,
            "Approval failed"
        );
    }

    /**
     * @notice Checks if the msg.sender is the admin address
     */
    modifier onlyAdmin() {
        require(msg.sender == admin, "admin: wut?");
        _;
    }

    /**
     * @notice Checks if the msg.sender is a contract or a proxy
     */
    modifier notContract() {
        require(
            (!_isContract(msg.sender)) && (msg.sender == tx.origin),
            "contract not allowed"
        );
        _;
    }

    /**
     * @notice Deposits funds into the Phoenix Vault
     * @dev Only possible when contract not paused.
     * @param _amount: number of tokens to deposit (in Phoenix)
     */
    function deposit(uint256 _amount) external whenNotPaused notContract {
        require(_amount > 0, "Nothing to deposit");

        uint256 pool = balanceOf();
        token.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 currentShares = 0;
        if (totalShares != 0) {
            currentShares = (_amount.mul(totalShares)).div(pool);
        } else {
            currentShares = _amount;
        }
        UserInfo storage user = userInfo[msg.sender];

        user.shares = user.shares.add(currentShares);
        user.lastDepositedTime = block.timestamp;

        totalShares = totalShares.add(currentShares);

        user.phoenixAtLastUserAction = user.shares.mul(balanceOf()).div(
            totalShares
        );
        user.lastUserActionTime = block.timestamp;

        _earn();

        emit Deposit(msg.sender, _amount, currentShares, block.timestamp);
    }

    /**
     * @notice Withdraws all funds for a user
     */
    function withdrawAll() external notContract {
        withdraw(userInfo[msg.sender].shares);
    }

    /**
     * @notice Withdraws from funds from the Phoenix Vault
     * @param _shares: Number of shares to withdraw
     */
    function withdraw(uint256 _shares) public notContract {
        UserInfo storage user = userInfo[msg.sender];
        require(_shares > 0, "Nothing to withdraw");
        require(_shares <= user.shares, "Withdraw amount exceeds balance");

        uint256 currentAmount = (balanceOf().mul(_shares)).div(totalShares);
        user.shares = user.shares.sub(_shares);
        totalShares = totalShares.sub(_shares);

        uint256 bal = available();
        if (bal < currentAmount) {
            uint256 balWithdraw = currentAmount.sub(bal);
            IMasterFarmer(masterfarmer).leaveStaking(balWithdraw);
            uint256 balAfter = available();
            uint256 diff = balAfter.sub(bal);
            if (diff < balWithdraw) {
                currentAmount = bal.add(diff);
            }
        }

        if (block.timestamp < user.lastDepositedTime.add(withdrawFeePeriod)) {
            uint256 currentWithdrawFee = currentAmount.mul(withdrawFee).div(
                10000
            );
            IMasterFarmer(masterfarmer).phoenixBurn(currentWithdrawFee);
            currentAmount = currentAmount.sub(currentWithdrawFee);
        }

        token.safeTransfer(msg.sender, currentAmount);

        if (user.shares > 0) {
            user.phoenixAtLastUserAction = user.shares.mul(balanceOf()).div(
                totalShares
            );
        } else {
            user.phoenixAtLastUserAction = 0;
        }

        user.lastUserActionTime = block.timestamp;

        emit Withdraw(msg.sender, currentAmount, _shares);
    }

    /**
     * @notice Reinvests Phoenix tokens into MasterFarmer
     * @dev Only possible when contract not paused.
     */
    function harvest() external notContract whenNotPaused {
        IMasterFarmer(masterfarmer).leaveStaking(0);

        uint256 bal = available();
        uint256 currentPerformanceFee = bal.mul(performanceFee).div(10000);
        IMasterFarmer(masterfarmer).phoenixBurn(currentPerformanceFee);

        uint256 currentCallFee = bal.mul(callFee).div(10000);
        token.safeTransfer(msg.sender, currentCallFee);

        _earn();

        lastHarvestedTime = block.timestamp;

        emit Harvest(msg.sender, currentPerformanceFee, currentCallFee);
    }

    /**
     * @notice Sets admin address
     * @dev Only callable by the contract owner.
     */
    function setAdmin(address _admin) external onlyOwner {
        require(_admin != address(0), "Cannot be zero address");
        admin = _admin;
        emit SetAdmin(msg.sender, _admin);
    }

    /**
     * @notice Sets performance fee
     * @dev Only callable by the contract admin.
     */
    function setPerformanceFee(uint256 _performanceFee) external onlyAdmin {
        require(
            _performanceFee <= MAX_PERFORMANCE_FEE,
            "performanceFee cannot be more than MAX_PERFORMANCE_FEE"
        );
        performanceFee = _performanceFee;
        emit SetPerformanceFee(msg.sender, _performanceFee);
    }

    /**
     * @notice Sets call fee
     * @dev Only callable by the contract admin.
     */
    function setCallFee(uint256 _callFee) external onlyAdmin {
        require(
            _callFee <= MAX_CALL_FEE,
            "callFee cannot be more than MAX_CALL_FEE"
        );
        callFee = _callFee;
        emit SetCallFee(msg.sender, _callFee);
    }

    /**
     * @notice Sets withdraw fee
     * @dev Only callable by the contract admin.
     */
    function setWithdrawFee(uint256 _withdrawFee) external onlyAdmin {
        require(
            _withdrawFee <= MAX_WITHDRAW_FEE,
            "withdrawFee cannot be more than MAX_WITHDRAW_FEE"
        );
        withdrawFee = _withdrawFee;
        emit SetWithdrawFee(msg.sender, _withdrawFee);
    }

    /**
     * @notice Sets withdraw fee period
     * @dev Only callable by the contract admin.
     */
    function setWithdrawFeePeriod(uint256 _withdrawFeePeriod)
        external
        onlyAdmin
    {
        require(
            _withdrawFeePeriod <= MAX_WITHDRAW_FEE_PERIOD,
            "withdrawFeePeriod cannot be more than MAX_WITHDRAW_FEE_PERIOD"
        );
        withdrawFeePeriod = _withdrawFeePeriod;
        emit SetWithdrawFeePeriod(msg.sender, _withdrawFeePeriod);
    }

    /**
     * @notice Withdraws from MasterFarmer to Vault without caring about rewards.
     * @dev EMERGENCY ONLY. Only callable by the contract admin.
     */
    function emergencyWithdraw() external onlyAdmin {
        IMasterFarmer(masterfarmer).emergencyWithdraw(0);
        emit EmergencyWithdraw(msg.sender);
    }

    /**
     * @notice Withdraw unexpected tokens sent to the Phoenix Vault
     */
    function inCaseTokensGetStuck(address _token) external onlyAdmin {
        require(
            _token != address(token),
            "Token cannot be same as deposit token"
        );
        require(
            _token != address(receiptToken),
            "Token cannot be same as receipt token"
        );

        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(msg.sender, amount);
    }

    /**
     * @notice Triggers stopped state
     * @dev Only possible when contract not paused.
     */
    function pause() external onlyAdmin whenNotPaused {
        _pause();
        emit Pause();
    }

    /**
     * @notice Returns to normal state
     * @dev Only possible when contract is paused.
     */
    function unpause() external onlyAdmin whenPaused {
        _unpause();
        emit Unpause();
    }

    /**
     * @notice Calculates the expected harvest reward from third party
     * @return Expected reward to collect in Phoenix
     */
    function calculateHarvestPhoenixRewards() external view returns (uint256) {
        uint256 amount = IMasterFarmer(masterfarmer).pendingPhoenix(
            0,
            address(this)
        );
        amount = amount.add(available());
        uint256 currentCallFee = amount.mul(callFee).div(10000);

        return currentCallFee;
    }

    /**
     * @notice Calculates the total pending rewards that can be restaked
     * @return Returns total pending Phoenix rewards
     */
    function calculateTotalpendingPhoenixRewards()
        external
        view
        returns (uint256)
    {
        uint256 amount = IMasterFarmer(masterfarmer).pendingPhoenix(
            0,
            address(this)
        );
        amount = amount.add(available());

        return amount;
    }

    /**
     * @notice Calculates the price per share
     */
    function getPricePerFullShare() external view returns (uint256) {
        return totalShares == 0 ? 1e18 : balanceOf().mul(1e18).div(totalShares);
    }

    /**
     * @notice Custom logic for how much the vault allows to be borrowed
     * @dev The contract puts 100% of the tokens to work.
     */
    function available() public view returns (uint256) {
        return token.balanceOf(address(this));
    }

    /**
     * @notice Calculates the total underlying tokens
     * @dev It includes tokens held by the contract and held in MasterFarmer
     */
    function balanceOf() public view returns (uint256) {
        (uint256 amount, ) = IMasterFarmer(masterfarmer).userInfo(
            0,
            address(this)
        );
        return token.balanceOf(address(this)).add(amount);
    }

    /**
     * @notice Deposits tokens into MasterFarmer to earn staking rewards
     */
    function _earn() internal {
        uint256 bal = available();
        if (bal > 0) {
            IMasterFarmer(masterfarmer).enterStaking(bal);
        }
    }

    /**
     * @dev Function to get the amount of shares
     * @param user The address of the user.
     * @return uint256 The amount of shares provided by the user for the given pool.
     */
    function getUserShares(address user) external view returns (uint256) {
        return userInfo[user].shares;
    }

    /**
     * @notice Checks if address is a contract
     * @dev It prevents contract from being targetted
     */
    function _isContract(address addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }
}
