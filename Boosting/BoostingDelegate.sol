// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "../contracts/math/SafeMath.sol";
import "../contracts/token/ERC721/IERC721.sol";
import "../contracts/access/AccessControl.sol";
import "../contracts/proxy/Initializable.sol";
import "../contracts/token/ERC721/ERC721Holder.sol";
import "./BoostingStorage.sol";

interface IFOGNFT {
    function getBoosting(uint _tokenId) external view returns (uint);               // scaled 1e12
    function getLockTimeReduce(uint _tokenId) external view returns (uint);         // scaled 1e12
    function ownerOf(uint _tokenId) external view returns (uint);
}
interface IFOGHero {
    function getBoosting(uint _heroId) external view returns (uint);                // scaled 1e12
    function ownerOf(uint _heroId) external view returns (uint);
}
interface IFOGManager {
    function getHeroId(uint _pid, address _user) external view returns (uint);
    function getLockId(uint _pid, address _user) external view returns (uint);
    function getBoostId(uint _pid, address _user) external view returns (uint);
}

contract BoostingDelegate is Initializable, AccessControl, ERC721Holder, BoostingStorage {

    bytes32 public constant FOG_FARMING_ROLE = keccak256("FARMING_CONTRACT_ROLE");
    bytes32 public constant FOG_MANAGER_ROLE = keccak256("FOG_MANAGER_ROLE");

    uint public constant MULTIPLIER_SCALE = 1e12;

    event BoostingDeposit(uint indexed _pid, address indexed _user, uint _lockTime, uint _nftBoostId, uint _nftLockId);

    event BoostingWithdraw(uint indexed _pid, address indexed _user);

    event BoostingEmergencyWithdraw(uint indexed _pid, address indexed _user);

    event NFTWithdraw(uint indexed _pid, address indexed _user);

    function initialize(address admin) external initializer {
        _setupRole(DEFAULT_ADMIN_ROLE, admin);
        _setRoleAdmin(FOG_FARMING_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(FOG_MANAGER_ROLE, DEFAULT_ADMIN_ROLE);
        minLockDays = 189000;           // 14 days of blocks @ 6.4second blocks
        maxLockDays = 2430000;          // 180 days of blocks @ 6.4second blocks
        increaseBoost = 192e8;
    }

///// Sets
    function setFarmingAddr(address _farmingAddr) external {
        grantRole(FOG_FARMING_ROLE, _farmingAddr);
    }
    function setFOGHero(address _FOGHero) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender));
        FOGHero = _FOGHero;
    }
    function setFOGNFT(address _FOGNFT) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender));
        FOGNFT = _FOGNFT;
    }
    function setFOGManager(address _FOGManager) external {
        grantRole(FOG_MANAGER_ROLE, _FOGManager);
        FOGManager = _FOGManager;
    }
    function setBoostScale(uint _minLockDays, uint _baseBoost, uint _increaseBoost) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender));
        minLockDays = _minLockDays;
        baseBoost = _baseBoost;
        increaseBoost = _increaseBoost;
    }
    function setMaxLockDays(uint _maxLockDays) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender));
        maxLockDays = _maxLockDays;
    }
///// Gets
    function getTimestamp() external view returns (uint) {
        uint blockTime = block.timestamp;
        return blockTime;
    }
    function getExpirationTime(uint _pid, address _user) public view returns (uint) {
        UserInfo storage info = userInfo[_pid][_user];
        uint heroId = IFOGManager(FOGManager).getHeroId(_pid, _user);
        uint nftLockId = IFOGManager(FOGManager).getLockId(_pid, _user);
        uint nftBoosting = 0;

        if (nftLockId != 0) {
            nftBoosting = IFOGNFT(FOGNFT).getLockTimeReduce(nftLockId);
        }
        if (heroId != 0) {
            nftBoosting = nftBoosting + (IFOGHero(FOGHero).getBoosting(heroId)/2);
        }
        uint endTime = info.startTime.add(info.lockTime.mul(MULTIPLIER_SCALE - nftBoosting).div(MULTIPLIER_SCALE));
        return endTime;
    }
    // scale 1e12 times
    function getMultiplier(uint _pid, address _user) external view returns (uint) {
        UserInfo storage info = userInfo[_pid][_user];

        uint nftBoost = 0;
        uint nftBoostId = IFOGManager(FOGManager).getBoostId(_pid, _user);
        if (nftBoostId != 0) {
            nftBoost = IFOGNFT(FOGNFT).getBoosting(nftBoostId);    
        }
        
        uint heroBoost = 0; 
        uint heroId = IFOGManager(FOGManager).getHeroId(_pid, _user);
        if (heroId != 0) {
            heroBoost = IFOGHero(FOGHero).getBoosting(heroId); 
        }

        uint lockBoost = getLockTimeBoost(info.lockTime); 
        if (lockBoost != 0) {
            return MULTIPLIER_SCALE.add(nftBoost).add(heroBoost).add(lockBoost);
        } 

        return MULTIPLIER_SCALE.add(nftBoost).add(heroBoost);
    } 
    function getLockTimeBoost(uint lockTime) public view returns (uint) {
        uint lockBoost = 0;
        if (lockTime >= minLockDays) {
            lockBoost = lockTime.sub(minLockDays).div(43200).mul(increaseBoost);
        }
        return lockBoost;
    }
///// Do
    function deposit(uint _pid, address _user, uint _lockTime) external {
        require(hasRole(FOG_MANAGER_ROLE, msg.sender));
        require(_lockTime <= maxLockDays, "lock time too high");

        UserInfo storage info = userInfo[_pid][_user];

        if (_lockTime > info.lockTime || canWithdraw(_pid, _user)) {
            info.startTime = block.number;
            info.lockTime = _lockTime;
        } else {
            uint difference = block.number - info.startTime;         // time difference between now and original startTime
            info.startTime = block.number;                        // nows starting lockTime
            info.lockTime = info.lockTime - difference;              // locked in for original amount - surpassed days (same endtime, less boost, more deposited)
        }
    }
    function withdraw(uint _pid, address _user) external {
        require(hasRole(FOG_MANAGER_ROLE, msg.sender));
        UserInfo storage info = userInfo[_pid][_user];
        
        info.startTime = 0;
        info.lockTime = 0;

        emit BoostingWithdraw(_pid, _user);
    }
    function canWithdraw(uint _pid, address _user) public view returns (bool) {
        return block.number >= getExpirationTime(_pid, _user);
    }
}
