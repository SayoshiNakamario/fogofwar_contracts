// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity 0.6.12;

import "../contracts/math/SafeMath.sol";
import "../contracts/token/ERC721/ERC721.sol";
import "../contracts/access/AccessControl.sol";
import "../contracts/proxy/Initializable.sol";
import "./FOGArenaStorage.sol";

interface IFOGHero {
    function getPower(uint heroId) external view returns(uint256);
}
interface IFOGFarming {
    function endArena(uint[] calldata pids, uint[] calldata allocPoints) external;
}
interface IFOGManager {
    function getArenaHeroId(address _lpToken, address _user) external view returns(uint256);
    function getArenaBoostId(address _lpToken, address _user) external view returns(uint256);
}
interface IFOGNFT {
    function getBoosting(uint heroId) external view returns(uint256);
}
interface IItemFactory {
    function stakeClaim(uint _type, address _user, uint _heroId, uint _boostId) external;
}

// FOGArena
contract FOGArena is Initializable, AccessControl, FOGArenaStorage {
    using SafeMath for uint256;

    bytes32 public constant FOG_MANAGER_ROLE = keccak256("FOG_MANAGER_ROLE");
    bytes32 public constant FOG_FARMING_ROLE = keccak256("FOG_FARMING_ROLE");
    
    uint public constant MULTIPLIER_SCALE = 1e12;
    uint public arenaAllocation;               // Allocation of FOG rewards to Arena, 1e12 = 100%
    
    function initialize(address admin) external initializer {
        _setupRole(DEFAULT_ADMIN_ROLE, admin);
        _setRoleAdmin(FOG_MANAGER_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(FOG_FARMING_ROLE, DEFAULT_ADMIN_ROLE);
    }

//// Gets
    function getPower(uint256 _lpid) external view returns (uint256) {
        return arenaInfo[lpInfo[_lpid].key].power;
    }
    function getStakedFOG(uint256 _lpid) external view returns (uint256) {
        return arenaInfo[lpInfo[_lpid].key].stakedFOG;
    }
    function getTickets(uint256 _pid) external view returns (uint256) {
        return lpInfo[_pid].tickets;
    }
    // total number of pools in this arena round
    function getRoundPools() external view returns (uint256) {
        return arenaInfo.length;
    }
    // total number of lpInfo entries
    function getLPInfoLength() external view returns (uint256) {
        return lpInfo.length;
    }
    // get FOG ID of arena participant
    function getArenaPID(uint aid) external view returns (uint256) {
        return arenaInfo[aid].pid;
    }
    // can add to arena
    function arenaActive(uint256 _pid) external view returns (bool) {
        LPInfo storage lp = lpInfo[_pid];
        require(lp.active, "LP not permitted in arena");
        require(lp.key != 0, "LP didnt pay for arena");
        return true;
    }
    // LP won arena
    function isFarming(uint256 _pid) external view returns (bool) {
        LPInfo storage lp = lpInfo[_pid];
        if (lp.farming) {
            return true;
        }
        return false;
    }
    // Number of blocks left in the round
    function blocksRemaining() external view returns (uint) {
        if (block.number < lastCalled + arenaLength) {
            uint blocks = (lastCalled + arenaLength) - block.number;
            return blocks;
        } else {
            return 0;
        }   
    }

//// Sets
    function setAllAddress(address _FOGManager, address _FOGHero, address _FOGNFT, address _FOGFarming, address _ItemFactory) external {
        hasRole(DEFAULT_ADMIN_ROLE, msg.sender);
        FOGManager = _FOGManager;
        grantRole(FOG_MANAGER_ROLE, _FOGManager);
        FOGHero = _FOGHero;
        FOGNFT = _FOGNFT;
        FOGFarming = _FOGFarming;
        grantRole(FOG_FARMING_ROLE, _FOGFarming);
        ItemFactory = _ItemFactory;  
    }
    function setFOGManager(address _FOGManager) external {
        hasRole(DEFAULT_ADMIN_ROLE, msg.sender);
        FOGManager = _FOGManager;
        grantRole(FOG_MANAGER_ROLE, _FOGManager);
    }
    function setItemFactory(address _ItemFactory) external {
        hasRole(DEFAULT_ADMIN_ROLE, msg.sender);
        ItemFactory = _ItemFactory;
    }
    function setFOGHero(address _FOGHero) external {
        hasRole(DEFAULT_ADMIN_ROLE, msg.sender);
        FOGHero = _FOGHero;
    }
    function setFOGNFT(address _FOGNFT) external {
        hasRole(DEFAULT_ADMIN_ROLE, msg.sender);
        FOGNFT = _FOGNFT;
    }
    function setFOGFarming(address _FOGFarming) external {
        hasRole(DEFAULT_ADMIN_ROLE, msg.sender);
        FOGFarming = _FOGFarming;
        grantRole(FOG_FARMING_ROLE, _FOGFarming);
    }
    function setArenaLength(uint256 _arenaLength) external {
        hasRole(DEFAULT_ADMIN_ROLE, msg.sender);
        arenaLength = _arenaLength;
    }
    function setMaxWinners(uint256 _maxWinners) external {
        hasRole(DEFAULT_ADMIN_ROLE, msg.sender);
        maxWinners = _maxWinners;
    }
    function setRewardChest(uint256 _rewardChest) external {
        hasRole(DEFAULT_ADMIN_ROLE, msg.sender);
        rewardChest = _rewardChest;
    }
    function setFOGAllocation(uint256 _arenaAllocation) external {
        hasRole(DEFAULT_ADMIN_ROLE, msg.sender);
        arenaAllocation = _arenaAllocation;
    }
    function setActive(uint256 _pid) external {
        hasRole(DEFAULT_ADMIN_ROLE, msg.sender);
        LPInfo storage lp = lpInfo[_pid];
        lp.active = !lp.active;
    }
    // Add a new LP token to the participant whitelist
    function addLP(uint length) external {
        require(hasRole(FOG_FARMING_ROLE, msg.sender) || hasRole(DEFAULT_ADMIN_ROLE, msg.sender));
        if (lpInfo.length < length) {
            lpInfo.push(LPInfo(false, false, 0, 0));
        }
    }
//// Arena
    // Add an arena ticket to a whitelisted LP
    function payEntry(uint _pid, uint _tickets) external {
        require(hasRole(FOG_MANAGER_ROLE, msg.sender));
        LPInfo storage lp = lpInfo[_pid];
        require(lp.active, "LP not permitted in arena");
        lp.tickets = lp.tickets + _tickets;
    }

    // Whitelist a new user
    function payTicket(address _user) external {
        require(hasRole(FOG_MANAGER_ROLE, msg.sender));
        require(block.number < lastCalled + arenaLength);
        trackTickets[_user] = lastCalled + arenaLength;  
    }

    // check if user has a ticket
    function checkTicket(address _user) external view returns (bool) {
        require (trackTickets[_user] > block.number, "Buy a ticket for this round");
        return true;
    }

    function commitArena(uint256 _pid, uint256 _nftBoostId, uint256 _nftLockId, uint256 _heroId) external {
        require(hasRole(FOG_MANAGER_ROLE, msg.sender));
        ArenaInfo storage arena = arenaInfo[lpInfo[_pid].key];      // use lpInfo's pointer key since arenaInfo changes
        // hero
        if (_heroId != 0) {
            uint heroPower = IFOGHero(FOGHero).getPower(_heroId);
            arena.power = arena.power + heroPower;
            arena.totalNFT++;
            arena.heroes++;
            // check leader
            if (arena.heroId != 0) {
                uint oldHero = IFOGHero(FOGHero).getPower(arena.heroId);
                if (heroPower > oldHero) {
                    arena.heroId = _heroId;
                }
            } else {
                arena.heroId = _heroId;
            }
        }
        // nftBoost
        if (_nftBoostId != 0) {
            uint heroPower = IFOGHero(FOGHero).getPower(_heroId);
            if (heroPower != 0) {
                uint boost = IFOGNFT(FOGNFT).getBoosting(_nftBoostId);
                arena.power = arena.power + ((heroPower * boost) / 1e12);
            }
            arena.totalNFT++;
        }
        // nftLock
        if (_nftLockId != 0) {
            arena.totalNFT++;
        }
    }

    function stakeFOG(uint _pid, uint _stakeAmount) external  {
        require(hasRole(FOG_MANAGER_ROLE, msg.sender));
        require(lpInfo[_pid].active);
        ArenaInfo storage arena = arenaInfo[lpInfo[_pid].key];
        arena.stakedFOG = arena.stakedFOG + _stakeAmount;
    }

    function endArena() external {
        require(block.number > lastCalled + arenaLength);
        lastCalled = block.number;

        // remove old winners flag
        if (winners.length != 0) {
            for (uint t = 0; t < winners.length; t++) {                             
                lpInfo[winners[t]].farming = false;
            }
        }

        // remove old arena round data
        delete arenaScores;
        delete winners;
        delete allocPoints;
        uint totalPower = 1;
        uint totalNFT = 1;
        uint totalHeroes = 1;
        uint totalFOG = 1;
        // get total numbers
        for (uint i = 1; i < arenaInfo.length; i++) {
            totalPower = totalPower + arenaInfo[i].power;
            totalNFT = totalNFT + arenaInfo[i].totalNFT;
            totalHeroes = totalHeroes + arenaInfo[i].heroes;
            totalFOG = totalFOG + arenaInfo[i].stakedFOG;
        }
        // get list of arena scores in 3e11
        arenaScores.push(ArenaScores(0, 0));
        uint powerScore;
        uint nftScore;
        uint heroesScore;
        uint fogScore;
        uint scoreTemp;
        for (uint i = 1; i < arenaInfo.length; i++) {
            powerScore = (12e10 * arenaInfo[i].power) / totalPower;                    // 40%   
            nftScore = (45e9 * arenaInfo[i].totalNFT) / totalNFT;                      // 15%
            heroesScore = (45e9 * arenaInfo[i].heroes) / totalHeroes;                  // 15%
            fogScore = (9e10 * arenaInfo[i].stakedFOG) / totalFOG;                     // 30%
            scoreTemp = powerScore + nftScore + heroesScore + fogScore;
            arenaScores.push(ArenaScores(scoreTemp / 3e9, scoreTemp));                      // arena score out of 100 & 3e11
        }
        // determine winners
        bool full = false;
        for (uint s = 100; s > 0; s--) {                            // start at top score and work down
            if (full) {                                     // if full was set to true then break this loop
                break;
            }
            for (uint a = 1; a < arenaScores.length; a++) {         // take the current score and check the list of arenas for it
                if (arenaScores[a].score == s) {                    // if one matches
                    winners.push(arenaInfo[a].pid);                 // add arenas LP pid to the winners array
                    if (winners.length == maxWinners) {             // if max winners then run final data collection, otherwise go find next highest score
                        full = true;
                        break;
                    }
                }
            }
        }
        // determine winners total and set flags
        uint totalAlloc;

        for (uint t = 0; t < winners.length; t++) {                                     // for each winner pid
            totalAlloc = totalAlloc + arenaScores[lpInfo[winners[t]].key].allocation;   // add their 3e11 score into a total
            lpInfo[winners[t]].farming = true;                                          // Cannot participate in next round
        }
        // determine winners share of FOG allocation between themselves
        for (uint p = 0; p < winners.length; p++) {
            uint temp = ((arenaAllocation * arenaScores[lpInfo[winners[p]].key].allocation) / totalAlloc);     // score converted to share of arenas FOG allocation
            allocPoints.push(temp);                                                                 // save winner allocation 
        }

        delete arenaInfo;
        IFOGFarming(FOGFarming).endArena(winners, allocPoints);     // send results to FOGFarming
        IItemFactory(ItemFactory).stakeClaim(rewardChest, msg.sender, 0, 0);
        startArena();
    }

    function initializeArena() external {
        hasRole(DEFAULT_ADMIN_ROLE, msg.sender);
        lastCalled = block.number;
        delete arenaInfo;
        delete arenaScores;
        delete winners;
        delete allocPoints;
        startArena();
    }

    function startArena() internal {
        arenaInfo.push(ArenaInfo(0, 0, 0, 0, 0, 0));                    // add empty entry to position 0

        for (uint pid = 0; pid < lpInfo.length; pid++) {                // loop over entire list of whitelisted LPs
            if (lpInfo[pid].active && !lpInfo[pid].farming) {           // for LPs allowed into arena and not currently farming (winners)
                if (lpInfo[pid].tickets > 0) {                          // check if LP has a ticket available
                    lpInfo[pid].tickets--;                              // burn a ticket
                    arenaInfo.push(ArenaInfo(pid, 0, 0, 0, 0, 0));      // add the LP to new arena
                    lpInfo[pid].key = arenaInfo.length - 1;             // record the LPs position in the arenaInfo array for future reference
                } else {
                    lpInfo[pid].key = 0;                                // if LP has no tickets set its position to 0
                }
            } else {
                lpInfo[pid].key = 0;                                    // if LP is disabled or farming set its position to 0
            }
        }
    }


}
