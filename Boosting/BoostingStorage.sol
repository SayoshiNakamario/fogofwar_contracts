// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "../contracts/math/SafeMath.sol";

contract BoostingStorage {
    using SafeMath for uint256;

    // Info of each user.
    struct UserInfo {
        uint256 startTime;
        uint256 lockTime;
    }

    // FOGNFT address
    address public FOGNFT;
    // FOGHero address
    address public FOGHero;
    // FOGManager address
    address public FOGManager;

    // poolId => user address => UserInfo
    mapping (uint => mapping (address => UserInfo)) public userInfo;

    uint public minLockDays;

    uint public maxLockDays;

    uint public baseBoost;

    uint public increaseBoost;
}
