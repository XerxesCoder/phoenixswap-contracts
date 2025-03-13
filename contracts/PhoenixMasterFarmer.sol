// SPDX-License-Identifier: MIT

pragma solidity >=0.8.9 <0.9.0;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "contracts/PhoniexToken.sol";
import "contracts/PhoenixBank.sol";

// MasterFarmer is the master of Phoenix. He can make Phoenixs and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once Phoenix is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MasterFarmer is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of Phoenixs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accPhoenixPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accPhoenixPerShare` (and `lastRewardBlockTime`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool.
        uint256 lastRewardBlockTime; // Last block time that Phoenixs distribution occurs.
        uint256 accPhoenixPerShare; // Accumulated Phoenixs per share, times 1e12. See below.
    }

    // The Phoenix TOKEN!
    PhoniexSwapToken public phoenix;
    // The PhoenixBANK (xPhoenix) TOKEN!
    PhoenixBank public bank;
    // Treasury address.
    address public treasuryAddr;
    // Dev team address.
    address public devAddr;
    // Phoenix tokens created per second.
    uint256 public phoenixPerSecond = 9000000000000000000;
    // Reward muliplier for early Phoenix makers.
    uint256[] public REWARD_MULTIPLIER = [9, 8, 7, 6, 5, 4, 3, 2, 1];
    // When multiplier changes.
    uint256[] public CHANGE_MULTIPLIER_AT_TIME;
    // When multiplier will change to 1.
    uint256 public FINISH_BONUS_AT_TIME;
    // 15% reward for devs (12.5%) and treasury (2.5%).
    uint256 public constant PERCENT_FOR_DEV = 125;
    uint256 public constant PERCENT_FOR_TREASURY = 25;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block time when Phoenix mining starts.
    uint256 public startBlockTime;

    event PhoenixBurn(address indexed from, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );
    event SetTreasury(address indexed user, address indexed newTreasury);
    event SetDev(address indexed user, address indexed newDev);
    event Add(address indexed user, IERC20 indexed pair, uint256 indexed point);
    event Set(address indexed user, uint256 indexed pid, uint256 indexed point);

    constructor(
        address _phnx,
        address _xphnx,
        address _dev,
        address _treasury,
        uint256 _startblocktime
    ) Ownable(msg.sender) {
        phoenix = PhoniexSwapToken(_phnx);
        bank = PhoenixBank(_xphnx);
        treasuryAddr = _treasury;
        devAddr = _dev;
        startBlockTime = _startblocktime;
        uint256 _changeMultiplierAfterTime = 2592000; // 30 day
        for (uint256 i = 0; i < REWARD_MULTIPLIER.length - 1; i++) {
            uint256 changeMultiplierAtTime = _changeMultiplierAfterTime
                .mul(i + 1)
                .add(_startblocktime);
            CHANGE_MULTIPLIER_AT_TIME.push(changeMultiplierAtTime);
        }
        FINISH_BONUS_AT_TIME = _changeMultiplierAfterTime
            .mul(REWARD_MULTIPLIER.length - 1)
            .add(_startblocktime);

        // staking pool
        poolInfo.push(
            PoolInfo({
                lpToken: phoenix,
                allocPoint: 1000,
                lastRewardBlockTime: _startblocktime,
                accPhoenixPerShare: 0
            })
        );

        totalAllocPoint = 1000;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function checkForDuplicate(IERC20 _lpToken) internal view {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            require(
                poolInfo[pid].lpToken != _lpToken,
                "Add: pool already exists!!!!"
            );
        }
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(
        uint256 _allocPoint,
        IERC20 _lpToken,
        bool _withUpdate
    ) public onlyOwner {
        checkForDuplicate(_lpToken); // ensure you can't add duplicate pools
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlockTime = block.timestamp > startBlockTime
            ? block.timestamp
            : startBlockTime;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardBlockTime: lastRewardBlockTime,
                accPhoenixPerShare: 0
            })
        );
        updateStakingPool();
        emit Add(msg.sender, _lpToken, _allocPoint);
    }

    // Update the given pool's Phoenix allocation point. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) public onlyOwner {
        require(_pid != 0, "You can't set allocPoint for staking pool.");
        if (_withUpdate) {
            massUpdatePools();
        }
        if (poolInfo[_pid].allocPoint != _allocPoint) {
            uint256 prevAllocPoint = poolInfo[_pid].allocPoint;
            poolInfo[_pid].allocPoint = _allocPoint;
            totalAllocPoint = totalAllocPoint.sub(prevAllocPoint).add(
                _allocPoint
            );
            updateStakingPool();
            emit Set(msg.sender, _pid, _allocPoint);
        }
    }

    function updateStakingPool() internal {
        uint256 length = poolInfo.length;
        uint256 points = 0;
        for (uint256 pid = 1; pid < length; ++pid) {
            points = points.add(poolInfo[pid].allocPoint);
        }
        if (points != 0) {
            points = points.div(4);
            totalAllocPoint = totalAllocPoint.sub(poolInfo[0].allocPoint).add(
                points
            );
            poolInfo[0].allocPoint = points;
        }
    }

    // Return reward multiplier over the given _from to _to block time.
    function getMultiplier(uint256 _from, uint256 _to)
        public
        view
        returns (uint256)
    {
        require(_to >= _from, "Multiplier: _from is bigger than _to");
        _from = _from > startBlockTime ? _from : startBlockTime;
        if (_to < startBlockTime) {
            return 0;
        }
        if (_from >= FINISH_BONUS_AT_TIME) {
            return _to.sub(_from);
        } else {
            uint256 result = 0;
            uint256 fromTime = _from;
            uint256 toTime = _to;
            for (uint256 i = 0; i < CHANGE_MULTIPLIER_AT_TIME.length; i++) {
                uint256 endTime = CHANGE_MULTIPLIER_AT_TIME[i];
                if (fromTime < endTime) {
                    uint256 m = endTime.sub(fromTime).mul(REWARD_MULTIPLIER[i]);
                    fromTime = endTime;
                    result = result.add(m);
                }
                if (toTime < endTime) {
                    uint256 m = endTime.sub(toTime).mul(REWARD_MULTIPLIER[i]);
                    toTime = endTime;
                    result = result.sub(m);
                }
            }
            if (_to >= FINISH_BONUS_AT_TIME) {
                uint256 m = _to.sub(FINISH_BONUS_AT_TIME);
                result = result.add(m);
            }
            return result;
        }
    }

    // Return how many Phoenix can mint based on Phoenix remaining supply.
    function phoenixCanMint(uint256 _amount)
        internal
        view
        returns (uint256 phoenixReward)
    {
        uint256 canMint = phoenix
            .maxSupply()
            .sub(phoenix.totalSupply())
            .mul(1000)
            .div(1000 + PERCENT_FOR_TREASURY + PERCENT_FOR_DEV);
        if (canMint < _amount) {
            phoenixReward = canMint;
        } else {
            phoenixReward = _amount;
        }
    }

    // View function to see pending Phoenixs on frontend.
    function pendingPhoenix(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accPhoenixPerShare = pool.accPhoenixPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.timestamp > pool.lastRewardBlockTime && lpSupply != 0) {
            uint256 multiplier = getMultiplier(
                pool.lastRewardBlockTime,
                block.timestamp
            );
            uint256 rewardAmount = multiplier
                .mul(phoenixPerSecond)
                .mul(pool.allocPoint)
                .div(totalAllocPoint);
            uint256 phoenixReward = phoenixCanMint(rewardAmount);
            accPhoenixPerShare = accPhoenixPerShare.add(
                phoenixReward.mul(1e12).div(lpSupply)
            );
        }
        return
            user.amount.mul(accPhoenixPerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.timestamp <= pool.lastRewardBlockTime) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlockTime = block.timestamp;
            return;
        }
        uint256 multiplier = getMultiplier(
            pool.lastRewardBlockTime,
            block.timestamp
        );
        uint256 rewardAmount = multiplier
            .mul(phoenixPerSecond)
            .mul(pool.allocPoint)
            .div(totalAllocPoint);
        uint256 phoenixReward = phoenixCanMint(rewardAmount);
        // Minting for devs and treasury will stop when total minted exceeds max supply.
        if (phoenix.totalMinted() < phoenix.maxSupply()) {
            phoenix.mint(devAddr, phoenixReward.mul(PERCENT_FOR_DEV).div(1000));
            phoenix.mint(
                treasuryAddr,
                phoenixReward.mul(PERCENT_FOR_TREASURY).div(1000)
            );
        }
        phoenix.mint(address(bank), phoenixReward);
        pool.accPhoenixPerShare = pool.accPhoenixPerShare.add(
            phoenixReward.mul(1e12).div(lpSupply)
        );
        pool.lastRewardBlockTime = block.timestamp;
    }

    // Deposit LP tokens to MasterFarmer for phoenix allocation.
    function deposit(uint256 _pid, uint256 _amount) public {
        require(_pid != 0, "deposit phoenix by staking");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user
                .amount
                .mul(pool.accPhoenixPerShare)
                .div(1e12)
                .sub(user.rewardDebt);
            if (pending > 0) {
                safePhoenixTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(
                address(msg.sender),
                address(this),
                _amount
            );
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accPhoenixPerShare).div(1e12);
    }

    // Withdraw LP tokens from MasterFarmer.
    function withdraw(uint256 _pid, uint256 _amount) public {
        require(_pid != 0, "withdraw phoenix by unstaking");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user
            .amount
            .mul(pool.accPhoenixPerShare)
            .div(1e12)
            .sub(user.rewardDebt);
        if (pending > 0) {
            safePhoenixTransfer(msg.sender, pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accPhoenixPerShare).div(1e12);
    }

    // Stake phoenix tokens to MasterFarmer
    function enterStaking(uint256 _amount) public {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][msg.sender];
        updatePool(0);
        if (user.amount > 0) {
            uint256 pending = user
                .amount
                .mul(pool.accPhoenixPerShare)
                .div(1e12)
                .sub(user.rewardDebt);
            if (pending > 0) {
                safePhoenixTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(
                address(msg.sender),
                address(this),
                _amount
            );
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accPhoenixPerShare).div(1e12);

        bank.mint(msg.sender, _amount);
    }

    // Withdraw phoenix tokens from STAKING.
    function leaveStaking(uint256 _amount) public {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][msg.sender];
        uint256 userBankBalance = bank.balanceOf(msg.sender);
        require(
            userBankBalance >= _amount,
            "withdraw: You do not have enough xPhoenix!"
        );
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(0);
        uint256 pending = user
            .amount
            .mul(pool.accPhoenixPerShare)
            .div(1e12)
            .sub(user.rewardDebt);
        if (pending > 0) {
            safePhoenixTransfer(msg.sender, pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accPhoenixPerShare).div(1e12);
        bank.burn(msg.sender, _amount);
    }

    // Burning phoenix tokens.
    function phoenixBurn(uint256 _amount) public {
        uint256 balance = phoenix.balanceOf(msg.sender);
        require(balance >= _amount, "Burning: You don't have phoenix enough!");
        phoenix.burn(msg.sender, _amount);
        emit PhoenixBurn(msg.sender, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        if (_pid == 0) {
            uint256 userBankBalance = bank.balanceOf(msg.sender);
            require(
                userBankBalance >= user.amount,
                "EmergencyWithdraw: You do not have enough xPhoenix!"
            );
            bank.burn(msg.sender, user.amount);
        }
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    // Safe phoenix transfer function, just in case if rounding error causes pool to not have enough Phoenixs.
    function safePhoenixTransfer(address _to, uint256 _amount) internal {
        bank.safePhoenixTransfer(_to, _amount);
    }

    /**
     * @dev Function to get the amount of LP tokens provided by a user for a specific pool.
     * @param pid The pool ID.
     * @param user The address of the user.
     * @return uint256 The amount of LP tokens provided by the user for the given pool.
     */
    function getUserPoolAmount(uint256 pid, address user)
        external
        view
        returns (uint256)
    {
        return userInfo[pid][user].amount;
    }

    // Update treasury address by the previous treasury.
    function setTreasury(address _treasuryAddr) public {
        require(msg.sender == treasuryAddr, "Set Treasury: wut?");
        require(_treasuryAddr != address(0), "Cannot be zero address");
        treasuryAddr = _treasuryAddr;
        emit SetTreasury(msg.sender, _treasuryAddr);
    }

    // Update dev address by the previous dev.
    function setDev(address _devAddr) public {
        require(msg.sender == devAddr, "Set Dev: wut?");
        require(_devAddr != address(0), "Cannot be zero address");
        devAddr = _devAddr;
        emit SetDev(msg.sender, _devAddr);
    }
}
