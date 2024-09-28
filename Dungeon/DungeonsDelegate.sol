// SPDX-License-Identifier: MIT
// Removed Oracle and Factory Roles. Removed off-chain AgentMinting. Redirected minting requests directly to openingChest functions.

pragma solidity 0.6.12;


import "../contracts/token/ERC721/ERC721.sol";
import "../contracts/token/ERC721/IERC721.sol";
import "../contracts/token/ERC20/IERC20.sol";
import "../contracts/token/ERC20/SafeERC20.sol";
import "../contracts/access/AccessControl.sol";
import "../contracts/proxy/Initializable.sol";
import "../contracts/token/ERC721/ERC721Holder.sol";

import "./DungeonsStorage.sol";

interface IItemFactory {
    function stakeClaim(address user, uint256 _type) external;
}

interface IFOGNFT {
    function getLockTimeReduce(uint _tokenId) external view returns (uint);
}

interface IFOGManager {
    function getStakeLockId(uint _pid, address _user) external view returns (uint);
}

// DungeonManager
contract DungeonsDelegate is Initializable, AccessControl, ERC721Holder, DungeonsStorage {
    using SafeERC20 for IERC20;

    bytes32 public constant FOG_MANAGER_ROLE = keccak256("FOG_MANAGER_ROLE");

    uint public constant MULTIPLIER_SCALE = 1e12;

    function initialize(address admin) external initializer {
        _setupRole(DEFAULT_ADMIN_ROLE, admin);
        _setRoleAdmin(FOG_MANAGER_ROLE, DEFAULT_ADMIN_ROLE);

        // chest staking
        stakePlanCount = 6;
        stakePlan[0].stakeAmount = 500 ether;
        stakePlan[0].lockTime = 13500;
        stakePlan[1].stakeAmount = 2500 ether;
        stakePlan[1].lockTime = 27000;
        stakePlan[2].stakeAmount = 12500 ether;
        stakePlan[2].lockTime = 40500;
        stakePlan[3].stakeAmount = 250000 ether;
        stakePlan[3].lockTime = 54000;
        stakePlan[4].stakeAmount = 750000 ether;
        stakePlan[4].lockTime = 67500;
        stakePlan[5].stakeAmount = 2000000 ether;
        stakePlan[5].lockTime = 81000;
    }

    function setTokenAddress(address _FOGNFT, address _FOGHero, address _ItemFactory, address _FOGManager) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender));
        FOGNFT = _FOGNFT;
        FOGHero = _FOGHero;
        ItemFactory = _ItemFactory;
        FOGManager = _FOGManager;
        grantRole(FOG_MANAGER_ROLE, _FOGManager);
    }

    function setStakePlanCount(uint _stakePlanCount) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender));
        stakePlanCount = _stakePlanCount;
    }

    function setStakePlanInfo(uint id, uint price, uint lockTime) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender));
        stakePlan[id].stakeAmount = price;
        stakePlan[id].lockTime = lockTime;
    }

    function getStakePrice(uint _type) external view returns (uint) {
        return stakePlan[_type].stakeAmount;
    }

   function getChestLockTime(uint _type) external view returns (uint) {
        return stakePlan[_type].lockTime;
    }

    function stakeFOG(uint _type, address _user, uint _stakeAmount) external  {
        require(hasRole(FOG_MANAGER_ROLE, msg.sender));
        require(dungeonAvailable(_type, _user), "Dungeon not available to stake");

        stakeInfo[_type][_user].startTime = block.number;
        stakeInfo[_type][_user].lockTime = stakePlan[_type].lockTime;

        stakedAmount[_type] = stakedAmount[_type].add(_stakeAmount);
    }

    // can add NFTs to dungeon
    function dungeonAvailable(uint _type, address user) public view returns (bool) {
        require(isStakeFinished(_type, user), "There is still a pending stake");
        require(isStakeable(_type), "Wrong type");
        return true;
    }

    function stakeClaim(uint _type, uint _amount) external {
        require(hasRole(FOG_MANAGER_ROLE, msg.sender));
        stakedAmount[_type] = stakedAmount[_type].sub(_amount);
    }

    // is an existing type
    function isStakeable(uint _type) public view returns (bool) {
        if (_type > stakePlanCount) {
            return false;
        }
        return true;
    }

    // has the stake end-block been passed
    function isStakeFinished(uint _type, address _user) public view returns (bool) {
        uint lockTime = stakeInfo[_type][_user].lockTime;
        uint nftLockId = IFOGManager(FOGManager).getStakeLockId(_type, _user);

        if (nftLockId != 0) {
            lockTime = lockTime - ((lockTime * IFOGNFT(FOGNFT).getLockTimeReduce(nftLockId)) / MULTIPLIER_SCALE);
        }

        return block.number > (stakeInfo[_type][_user].startTime.add(lockTime));        
    }


}