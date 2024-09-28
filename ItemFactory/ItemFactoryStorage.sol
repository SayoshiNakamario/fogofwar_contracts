// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "../contracts/math/SafeMath.sol";

contract ItemFactoryStorage {
    using SafeMath for uint256;

    struct ChestPrices {
        uint price;
        uint lockTime;
    }

    // id => plan
    mapping(uint => ChestPrices) public chestPrices;

    address public FOGToken;
    address public FOGNFT;
    address public FOGHero;

    uint internal _foundationSeed;
    uint[] public CATEGORY_MASK; 
    uint[] public POWER_MASK;
    uint public chestPricesCount;
    uint public maxNFTLevel;
    uint public maxNFTCategory;
    uint public maxNFTItem;
    uint public maxNFTRandom;
    uint public lastOrderTimestamp;
}
