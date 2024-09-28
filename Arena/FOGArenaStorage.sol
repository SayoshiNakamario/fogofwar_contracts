// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "../contracts/math/SafeMath.sol";

contract FOGArenaStorage {
    using SafeMath for uint256;

    address public FOGHero;
    address public FOGManager;
    address public FOGNFT;
    address public FOGFarming;
    address public ItemFactory;
    uint public arenaLength;                   // Number of blocks per arena round
    uint public lastCalled;                    // Last time endArena was called
    uint public maxWinners;                    // Max number of arena winners each round
    uint public rewardChest;                   // Chest level given for ending arena

    struct LPInfo {
        bool active;                    // is LP permitted in arena
        bool farming;                   // LP won a farm       
        uint256 tickets;                // number of additional arena round tickets
        uint256 key;                    // arenaInfo key
    }
    LPInfo[] public lpInfo;             // FOG pid > LPInfo

    struct ArenaInfo {
        uint256 pid;                    // FOG pid
        uint256 heroes;                 // number of heroes attached
        uint256 totalNFT;               // total number of NFTs attached
        uint256 stakedFOG;              // FOG staked
        uint256 power;                  // power value for Arena
        uint256 heroId;                 // ID of strongest attached hero
    }
    ArenaInfo[] public arenaInfo;        // key > ArenaInfo

    struct ArenaScores {
        uint score;                      // score in 100
        uint allocation;                 // score in 3e11
    }
    ArenaScores[] public arenaScores;  

    uint[] public winners;                                     // PID of winners
    uint[] public allocPoints;                                 // percent dominance of arena in 1e12
    mapping(address => uint) public trackTickets;       // Users who can participate
}
