// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;


import "../contracts/token/ERC20/IERC20.sol";
import "../contracts/token/ERC20/SafeERC20.sol";
import "../contracts/math/SafeMath.sol";
import "../contracts/access/Ownable.sol";
import "../contracts/access/AccessControl.sol";
import "./FOGToken.sol";

// FOGFarming is the master of FOG. He can make FOG and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power.
//
// Have fun reading it. Hopefully it's bug-free.

interface Boosting {
    function canWithdraw(uint pid, address user) external view returns (bool);
    function getMultiplier(uint pid, address user) external view returns (uint); // zoom in 1e12 times;
}

interface IFOGManager {
    // Farms
    function depositBoosting(uint pid, address user, uint lockTime, uint nftBoostId, uint nftLockId, uint amount) external;
    function withdrawNFT(uint pid, address user, bool nftBoost, bool nftLock, bool hero) external;    
    function depositHero(uint pid, address user, uint heroId, address heroContract) external;
    // Dungeons
    function stakeClaim(uint _type, address user) external; // can be removed
}

interface IDEX {
    // function userInfo(uint256 pid, address user) external view returns (uint256 amount, uint256 rewardDebt, uint256 rewardLockedUp, uint256 nextHarvestUntil);  // Emberswap
    function userInfo(uint256 pid, address user) external view returns (uint256 amount, uint256 rewardDebt);    // Mistswap & Tango & 1BCH & BEN
    function deposit(uint256 _pid, uint256 _amount) external;                                                   // Mistswap & Emberswap & Tango & 1BCH & BEN
    function withdraw(uint256 _pid, uint256 _amount) external;                                                  // Mistswap & Emberswap & Tango & 1BCH & BEN
    function emergencyWithdraw(uint256 _pid) external;                                                          // Mistswap & Emberswap & Tango & 1BCH & BEN
}

interface IPending {
    function pendingRewards(address _DEX, uint256 _pid, address _user) external view returns (uint256);
}

interface IArena {
    function addLP(uint length) external;
}

contract FOGFarming is Ownable, AccessControl {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.

        uint256 dexRewardDebt; // extra reward debt
        //
        // We do some fancy math here. Basically, any point in time, the amount of FOGs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accFOGPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accFOGPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;                 // Address of LP token contract.
        uint256 allocPoint;             // How many allocation points assigned to this pool. FOGs to distribute per block.
        uint256 lastRewardBlock;        // Last block number that FOGs distribution occurs.
        uint256 accFOGPerShare;         // Accumulated FOGs per share, times 1e12. See below.
        uint256 activeAddresses;        // number of unique addresses with LP in pool
        // extra pool reward
        uint256 dexID;                  // FOGs ID for the DEX
        uint256 dexPID;                 // External DEX PID
        uint256 accDexPerShare;         // Accumulated extra token per share, times 1e12.
        bool dualFarmingEnable;         // Whether pid interacts with external DEX farms.
        bool dualWasEnabled;            // User may have DEX rewards to claim.
        bool emergencyMode;             // Forced external LP to come back to FOG.
        bool disabled;                  // Disables deposits into this pid.
    }

    FOGToken public fog;                // The FOG TOKEN!
    address public devaddr;             // Dev address.
    uint256 public startBlock;          // The block number when FOG mining starts.
    uint256 public fogPerBlock;         // FOG tokens created per block.
    uint256 public maxMultiplier;       // Max multiplier
    address[] public dexFarming;        // dexID > dex farming address
    address[] public dexTokens;         // dexID > reward token address
    address public boostingAddr;        // boosting address for item bonuses
    address public FOGManager;          // FOGManager address              
    address public Pending;             // Pending address for external pending tokens on UI
    address public Arena;               // Arena address
    address public Bridge;              // Bridge address

    PoolInfo[] public poolInfo;                                             // Info of each pool.
    uint[] public arenaFarms;                                               // Current arena farm winners.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;     // Info of each user that stakes LP tokens.
    uint256 public totalAllocPoint = 0;                                     // Total allocation points. Must = all allocated.

    bytes32 public constant ARENA_ROLE = keccak256("ARENA_ROLE");           // Declare whitelist role for endArena()
    bytes32 public constant BRIDGE_ROLE = keccak256("BRIDGE_ROLE");         // Declare whitelist role for trusted Bridge
    uint256 public constant TEAM_PERCENT = 10;                              // Devs earn 10% on top of FOG mints
    uint256 public constant PID_NOT_SET = 2**256 - 1;                       // uint256 max number used as not configured status

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        FOGToken _fog,
        address _devaddr,
        address _boostingAddr,
        uint256 _fogPerBlock,
        uint256 _startBlock,
        address _FOGManager
    ) public {
        fog = _fog;
        devaddr = _devaddr;
        startBlock = _startBlock;
        boostingAddr = _boostingAddr;
        fogPerBlock = _fogPerBlock;
        maxMultiplier = 333e10;
        FOGManager = _FOGManager;
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setRoleAdmin(ARENA_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(BRIDGE_ROLE, DEFAULT_ADMIN_ROLE);
    }

///// Sets
    function setArena(address _Arena) external onlyOwner {
        grantRole(ARENA_ROLE, _Arena);
        Arena = _Arena;
    }

    function setBridge(address _Bridge) external onlyOwner {
        grantRole(BRIDGE_ROLE, _Bridge);
        Bridge = _Bridge;
    }

    function setDexIDs(uint _pid, uint _dexID, uint _dexPID) external onlyOwner {  
        poolInfo[_pid].dexID = _dexID;                              // Set dex for this LP
        poolInfo[_pid].dexPID = _dexPID;                            // Set dex poolID for this LP
    }

    function setDualFarming(uint _pid, bool _dualFarmingEnable) external onlyOwner {  
        PoolInfo storage pool = poolInfo[_pid];
        address DEX = dexFarming[pool.dexID];
        uint lpSupply = pool.lpToken.balanceOf(address(this));

        poolInfo[_pid].dualFarmingEnable = _dualFarmingEnable;      // Set if dual farming to dex
        if (_dualFarmingEnable) {                                   // If going to true deposit LPs FOG has now
            IERC20(pool.lpToken).approve(DEX, lpSupply);
            IDEX(DEX).deposit(pool.dexPID, lpSupply);
            pool.dualWasEnabled = true;
        } else {                                                    // Otherwise going to false, update rewards then withdraw
            uint total;
            (total,) = IDEX(DEX).userInfo(pool.dexPID, address(this));
            if (total == 0) {
                if (pool.lastRewardBlock < block.number) {
                    pool.lastRewardBlock = block.number;
                }
                return;
            }
            uint256 dexReward = IPending(Pending).pendingRewards(DEX, pool.dexPID, address(this));
            if (dexReward != 0) {
                pool.accDexPerShare = pool.accDexPerShare.add(dexReward.mul(1e12).div(total));
            }
            IDEX(DEX).withdraw(pool.dexPID, total);
        }
    }

    function setDexContract(address _dexContract) external onlyOwner {        
        dexFarming.push(_dexContract);
    }

    function setAddresses(address _boostingAddr, address _FOGManager) external onlyOwner {        
        boostingAddr = _boostingAddr;
        FOGManager = _FOGManager;
    }

    function setDexToken(address _dexToken) external onlyOwner {  
        dexTokens.push(_dexToken);
    }

    function setPending(address _Pending) external onlyOwner {  
        Pending = _Pending;
    }

    function setMaxMultiplier(uint _maxMultiplier) external onlyOwner {
        maxMultiplier = _maxMultiplier;
    }

    // Update the given pool's FOG allocation point.
    function setAlloc(uint256 _pid, uint256 _allocPoint, bool _withUpdate) external onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }
    function setPerBlock(uint256 _perBlock) external onlyOwner {
        fogPerBlock = _perBlock;
    }
    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function addLP(uint256 _allocPoint, IERC20 _lpToken, bool _withUpdate) external onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);

        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accFOGPerShare: 0,
            dexID: PID_NOT_SET,
            dexPID: PID_NOT_SET,
            accDexPerShare: 0,
            dualFarmingEnable: false,
            dualWasEnabled: false,
            emergencyMode: false,
            disabled: false,
            activeAddresses: 0
        }));

        IArena(Arena).addLP(poolInfo.length);      // keep poolInfo entry count in sync with Arena.lpInfo
    }

///// Gets
    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }
    function poolAddresses(uint256 pid) external view returns (uint256) {
        return poolInfo[pid].activeAddresses;
    }
    function arenaFarmsLength() external view returns (uint256) {
        return arenaFarms.length;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        if (_from < startBlock) {
            return 0;
        }

        return _to.sub(_from);
    }

    // View function to see pending FOGs on frontend.
    function pendingFOG(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accFOGPerShare = pool.accFOGPerShare;
        
        uint256 lpSupply;
        if (pool.dexID == PID_NOT_SET || !pool.dualFarmingEnable) {
            lpSupply = pool.lpToken.balanceOf(address(this));
        } else {
            (lpSupply,) = IDEX(dexFarming[pool.dexID]).userInfo(pool.dexPID, address(this));
        }

        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 fogReward = multiplier.mul(fogPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accFOGPerShare = accFOGPerShare.add(fogReward.mul(1e12).div(lpSupply));
            // multiplier from lockTime and NFT
            if (boostingAddr != address(0)) {
                uint multiplier2 = Boosting(boostingAddr).getMultiplier(_pid, _user);
                if (multiplier2 > maxMultiplier) {
                    multiplier2 = maxMultiplier;
                }
                return user.amount.mul(accFOGPerShare).div(1e12).sub(user.rewardDebt).mul(multiplier2).div(1e12);
            }
        }
        return user.amount.mul(accFOGPerShare).div(1e12).sub(user.rewardDebt);
    }

    // View function to see pending DEX rewards on frontend.
    function pendingTokens(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accDexPerShare = pool.accDexPerShare;
        uint256 lpSupply;

        // dual farming not active and was never enabled
        if (!pool.dualFarmingEnable && !pool.dualWasEnabled) {
            return 0;
        } 
        // dual farming disabled but was enabled
        else if (!pool.dualFarmingEnable && pool.dualWasEnabled) {
            return user.amount.mul(accDexPerShare).div(1e12).sub(user.dexRewardDebt);
        } 
        // dual farming active
        else if (pool.dualFarmingEnable) {
            require(pool.dexID != PID_NOT_SET && pool.dexPID != PID_NOT_SET);
            address DEX = dexFarming[pool.dexID];
            (lpSupply,) = IDEX(DEX).userInfo(pool.dexPID, address(this));

            if (lpSupply != 0) {
                uint256 dexReward = IPending(Pending).pendingRewards(DEX, pool.dexPID, address(this));
                accDexPerShare = accDexPerShare.add(dexReward.mul(1e12).div(lpSupply));
            }
            return user.amount.mul(accDexPerShare).div(1e12).sub(user.dexRewardDebt);
        }    
    }

    // Update reward vairables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        uint256 lpSupply;
        address DEX = address(0);   
        
        // detect active dual farm
        if (pool.dualFarmingEnable == true) {
            require(pool.dexID != PID_NOT_SET && pool.dexPID != PID_NOT_SET);
            DEX = dexFarming[pool.dexID];
        }

        // FOG-only farm, update
        if (DEX == address(0)) {
            lpSupply = pool.lpToken.balanceOf(address(this));
            if (lpSupply == 0) {
                if (pool.lastRewardBlock < block.number) {
                    pool.lastRewardBlock = block.number;
                }
                return;
            }
        // Otherwise dual farm, update and claim
        } else {
            (lpSupply,) = IDEX(DEX).userInfo(pool.dexPID, address(this));
            if (lpSupply == 0) {
                if (pool.lastRewardBlock < block.number) {
                    pool.lastRewardBlock = block.number;
                }
                return;
            }
            uint256 dexReward = IPending(Pending).pendingRewards(DEX, pool.dexPID, address(this));
            pool.accDexPerShare = pool.accDexPerShare.add(dexReward.mul(1e12).div(lpSupply));
            IDEX(DEX).withdraw(pool.dexPID, 0);
        }
        
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 fogReward = multiplier.mul(fogPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        pool.accFOGPerShare = pool.accFOGPerShare.add(fogReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    function withdrawAllFromDex(uint _pid) external onlyOwner {       
        updatePool(_pid);

        PoolInfo storage pool = poolInfo[_pid];
        pool.dualFarmingEnable = false;
        uint total;
        (total,) = IDEX(dexFarming[pool.dexID]).userInfo(pool.dexPID, address(this));
        IDEX(dexFarming[pool.dexID]).withdraw(pool.dexPID, total);
    }

    // Deposit LP tokens and NFTs to FOG.
    function deposit(uint256 _pid, uint256 _amount, uint lockTime, uint _nftBoostId, uint _nftLockId, uint _heroId, address _heroContract) external {
        PoolInfo storage pool = poolInfo[_pid];
        require(pool.disabled == false, "Pool deposits disabled.");
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        uint userAmountOld = user.amount;

        // harvest any rewards
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accFOGPerShare).div(1e12).sub(user.rewardDebt);
            if (boostingAddr != address(0)) {
                // multiplier from lockTime and NFT
                uint multiplier2 = Boosting(boostingAddr).getMultiplier(_pid, msg.sender);
                if (multiplier2 > maxMultiplier) {
                    multiplier2 = maxMultiplier;
                }
                pending = pending.mul(multiplier2).div(1e12);                
            }
            mintFOG(pending);
            safeFOGTransfer(msg.sender, pending);
        } else {
            poolInfo[_pid].activeAddresses++;
        }

        // check if manager active & options included
        if (FOGManager != address(0)) {
            if (_amount != 0 || lockTime != 0 || _nftBoostId != 0 || _nftLockId != 0) {
                IFOGManager(FOGManager).depositBoosting(_pid, msg.sender, lockTime, _nftBoostId, _nftLockId, _amount);
            }
            if (_heroId != 0) {
                IFOGManager(FOGManager).depositHero(_pid, msg.sender, _heroId, _heroContract);
            }
        } 

        // update user and take LP
        user.amount = user.amount.add(_amount);
        user.rewardDebt = user.amount.mul(pool.accFOGPerShare).div(1e12);
        pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);

        // if dual farming active claim rewards and deposit to DEX
        if (pool.dualFarmingEnable) {
            require(pool.dexID != PID_NOT_SET && pool.dexPID != PID_NOT_SET);
            address DEX = dexFarming[pool.dexID];
            require(DEX != address(0));
            uint256 dexPending = userAmountOld.mul(pool.accDexPerShare).div(1e12).sub(user.dexRewardDebt);

            user.dexRewardDebt = user.amount.mul(pool.accDexPerShare).div(1e12);
            safeDEXTransfer(msg.sender, dexPending, pool.dexID);
            IERC20(pool.lpToken).approve(DEX, _amount);
            IDEX(DEX).deposit(pool.dexPID, _amount);
        // otherwise claim any pending rewards
        } else if (pool.dualWasEnabled) {
            uint256 dexPending = userAmountOld.mul(pool.accDexPerShare).div(1e12).sub(user.dexRewardDebt); 

            user.dexRewardDebt = user.amount.mul(pool.accDexPerShare).div(1e12);
            safeDEXTransfer(msg.sender, dexPending, pool.dexID);            
        }
        
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens or NFTs from FOG farms.
    function withdraw(uint256 _pid, uint256 _amount, bool _nftBoost, bool _nftLock, bool _hero) external {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        uint256 userOldAmount = user.amount;
        uint256 pending = user.amount.mul(pool.accFOGPerShare).div(1e12).sub(user.rewardDebt);
        
        // check for timelock and boost modifiers
        if (boostingAddr != address(0)) {
            require(Boosting(boostingAddr).canWithdraw(_pid, msg.sender), "Lock time not finish");

            // multiplier from lockTime and NFT
            uint multiplier2 = Boosting(boostingAddr).getMultiplier(_pid, msg.sender);
            if (multiplier2 > maxMultiplier) {
                multiplier2 = maxMultiplier;
            }
            pending = pending.mul(multiplier2).div(1e12);
        }
        // harvest any rewards
        user.amount = user.amount.sub(_amount);
        user.rewardDebt = user.amount.mul(pool.accFOGPerShare).div(1e12);
        mintFOG(pending);
        safeFOGTransfer(msg.sender, pending);
        // claim any pending DEX rewards
        if (pool.dualFarmingEnable || pool.dualWasEnabled) {
            uint256 dexPending = userOldAmount.mul(pool.accDexPerShare).div(1e12).sub(user.dexRewardDebt);
            if (dexPending > 0) {
                user.dexRewardDebt = user.amount.mul(pool.accDexPerShare).div(1e12);
                safeDEXTransfer(msg.sender, dexPending, pool.dexID);
            }
        }
        // remove from active address count
        if (_amount == user.amount) {
            poolInfo[_pid].activeAddresses--;
        }
        // send withdraw
        if (_amount > 0) {
            if (pool.dualFarmingEnable) {
                require(pool.dexID != PID_NOT_SET && pool.dexPID != PID_NOT_SET);
                address DEX = dexFarming[pool.dexID];

                IDEX(DEX).withdraw(pool.dexPID, _amount);
                pool.lpToken.safeTransfer(address(msg.sender), _amount);
            } else {
                pool.lpToken.safeTransfer(address(msg.sender), _amount);
            }
        }
        // send NFTs
        if (FOGManager != address(0) && _nftBoost == true || _nftLock == true || _hero == true) {
            IFOGManager(FOGManager).withdrawNFT(_pid, msg.sender, _nftBoost, _nftLock, _hero);
        }
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw LP to FOG without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdrawEnable(uint256 _pid) external onlyOwner {
        PoolInfo storage pool = poolInfo[_pid];
        address DEX = dexFarming[pool.dexID];

        pool.emergencyMode = true;
        pool.dualFarmingEnable = false;
        IDEX(DEX).emergencyWithdraw(pool.dexPID);
    }

    // Withdraw LP and NFTs to user without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) external {
        PoolInfo storage pool = poolInfo[_pid];
        require(pool.emergencyMode, "Emergency mode not enabled.");

        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        IFOGManager(FOGManager).withdrawNFT(_pid, msg.sender, true, true, true);
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // Toggles whether a farms deposits are enabled.
    function disableFarm(uint256 _pid) external onlyOwner {
        PoolInfo storage pool = poolInfo[_pid];
        pool.disabled = !pool.disabled;
    }

    // Safe FOG transfer function, just in case if rounding error causes pool to not have enough FOGs.
    function safeFOGTransfer(address _to, uint256 _amount) internal {
        uint256 fogBal = fog.balanceOf(address(this));
        if (_amount > fogBal) {
            require(fog.transfer(_to, fogBal));
        } else {
            require(fog.transfer(_to, _amount));
        }
    }

    // Safe DEX transfer function, just in case if rounding error causes pool to not have enough reward tokens.
    function safeDEXTransfer(address _to, uint256 _amount, uint256 _pid) internal {
        uint256 dexBal = IERC20(dexTokens[_pid]).balanceOf(address(this));
        if (_amount > dexBal) {
            IERC20(dexTokens[_pid]).safeTransfer(_to, dexBal);
        } else {
            IERC20(dexTokens[_pid]).safeTransfer(_to, _amount);
        }
    }

    // Update dev address by the previous dev.
    function dev(address _devaddr) external {
        require(msg.sender == devaddr, "Should be dev address");
        devaddr = _devaddr;
    }

    function mintFOG(uint amount) private {
        fog.mint(devaddr, amount.mul(TEAM_PERCENT).div(100));
        fog.mint(address(this), amount);
    }

    function bridgeFOG(address _user, uint amount) external {
        require(hasRole(BRIDGE_ROLE, msg.sender));
        fog.mint(_user, amount);
    }

//// Arena
    function endArena(uint[] calldata pids, uint[] calldata allocPoints) external {
        require(hasRole(ARENA_ROLE, msg.sender));
        require(pids.length == allocPoints.length, "Arena arguments do not match");

        // Disable existing arena farms
        if (arenaFarms.length != 0) {
            for (uint i = 0; i < arenaFarms.length; i++) {
            totalAllocPoint = totalAllocPoint - poolInfo[arenaFarms[i]].allocPoint;
            poolInfo[arenaFarms[i]].allocPoint = 0;                                     
            poolInfo[arenaFarms[i]].disabled = true;
            }
            delete arenaFarms;
        }
        // Add new farms
        for (uint i = 0; i < pids.length; i++) {
            arenaFarms.push(pids[i]);
            poolInfo[pids[i]].allocPoint = allocPoints[i];
            totalAllocPoint = totalAllocPoint + allocPoints[i];
            poolInfo[pids[i]].disabled = false;
        }
    }
}