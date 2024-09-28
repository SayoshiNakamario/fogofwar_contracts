// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "../contracts/math/SafeMath.sol";

contract DungeonsStorage {
    using SafeMath for uint256;

    struct StakeInfo {
        uint lockTime;
        uint startTime;
    }

    struct StakePlan {
        uint stakeAmount;
        uint lockTime;
    }

    // user => stake type => stake info
    mapping(uint => mapping(address => StakeInfo)) public stakeInfo;

    mapping(address => uint) public emptyTimes;

    // id => plan
    mapping(uint => StakePlan) public stakePlan;

    address public FOGNFT;
    address public FOGHero;
    address public ItemFactory;
    address public FOGManager;

    uint public lastOrderTimestamp;
    uint public stakePlanCount;
    uint[] public CATEGORY_MASK; 
    uint[] public POWER_MASK; 

    // planId => stakeFOGAmount
    mapping(uint => uint) public stakedAmount;

    
}
