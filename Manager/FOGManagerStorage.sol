// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "../contracts/math/SafeMath.sol";

contract FOGManagerStorage {
    using SafeMath for uint256;

    address public FOGToken;
    address public BCH;     
    address presaleAddr;  
    address public FOGNFT;         
    address public FOGHero;       
    address public ItemFactory; 
    address public Boosting; 
    address public Dungeons;
    address public Arena;

    uint public minLockDays;
    uint public maxLockDays;
    uint public baseBoost;
    uint public increaseBoost;
    uint public arenaFee;
    uint public arenaWin;
    uint public arenaLoss;
    uint public heroPrice;
    uint public presalePrice = 0.01 ether;
    bool public presaleActive;

////// Farm boost tracking
    struct BoostInfo {
        uint256 nftBoostId;
        uint256 nftLockId;
        uint256 heroId;
    }
        // pid => user address => BoostInfo
    mapping (uint => mapping (address => BoostInfo)) public boostInfo;

////// Dungeon tracking
    struct StakeInfo {
        uint nftBoostId;
        uint nftLockId;
        uint heroId;
        uint stakedFOG;
    }
        // dungeon => user => StakeInfo
    mapping(uint => mapping(address => StakeInfo)) public stakeInfo;

////// Arena tracking
    struct ArenaInfo {
        uint nftBoostId;
        uint nftLockId;
        uint heroId;
        uint stakedFOG;
        uint lockBlock;     // end of arena round after committing
        uint lockStart;     // block number when committed
    }
        // pid => user => ArenaInfo
    mapping(uint => mapping(address => ArenaInfo)) public arenaInfo;

}
