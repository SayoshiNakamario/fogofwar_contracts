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

import "./ItemFactoryStorage.sol";

interface IFOGToken {
    function burn(uint256 _amount) external;
}

interface IFOGHero {
    function getBoosting(uint256 _heroId) external view returns (uint);
}

interface IFOGNFT {
    function mint(uint tokenId, uint _level, uint _category, uint _item, uint _random, uint _powerMin, uint _powerMax) external;
    function totalSupply() external view returns (uint);
    function itemSupply(uint _level, uint _category, uint _item) external view returns (uint);
    function getBoosting(uint _tokenId) external view returns (uint);
}

// ItemFactory
contract ItemFactoryDelegate is Initializable, AccessControl, ERC721Holder, ItemFactoryStorage {
    using SafeERC20 for IERC20;

    bytes32 public constant FOG_MANAGER_ROLE = keccak256("FOG_MANAGER_ROLE");
    bytes32 public constant FOG_ARENA_ROLE = keccak256("FOG_ARENA_ROLE");

    uint[6][] LEVEL_MASK; 
    uint[10][] ITEM_MASK;

    event MintNFT(uint indexed level, uint indexed category, uint indexed item, uint random, uint tokenId, uint itemSupply);

    event ChestBuy(address indexed user, uint price, uint _type, uint tokenId);

    event MintFinish(address indexed user);

    function initialize(address admin) external initializer {
        _setupRole(DEFAULT_ADMIN_ROLE, admin);
        _setRoleAdmin(FOG_MANAGER_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(FOG_ARENA_ROLE, DEFAULT_ADMIN_ROLE);
        maxNFTLevel = 6;
        maxNFTCategory = 2;
        maxNFTItem = 10;
        maxNFTRandom = 7500;
        lastOrderTimestamp = block.timestamp;

        // chest prices
        chestPricesCount = 6;
        chestPrices[0].price = 1000 ether;
        chestPrices[0].lockTime = 1 days;
        chestPrices[1].price = 5000 ether;
        chestPrices[1].lockTime = 2 days;
        chestPrices[2].price = 25000 ether;
        chestPrices[2].lockTime = 3 days;
        chestPrices[3].price = 125000 ether;
        chestPrices[3].lockTime = 4 days;
        chestPrices[4].price = 625000 ether;
        chestPrices[4].lockTime = 5 days;
        chestPrices[5].price = 3125000 ether;
        chestPrices[5].lockTime = 6 days;

        // weapon or armor chances
        CATEGORY_MASK.push(50);     // armor  - 50%
        CATEGORY_MASK.push(100);    // weapon - 50%

        // level chances per chest
        LEVEL_MASK.push([80,95,99,100,0,0]);    // chest 0 - 80%, 15%,  4%,  1%, 0%, 0%
        LEVEL_MASK.push([65,86,94,100,0,0]);    // chest 1 - 65%, 21%,  8%,  6%, 0%, 0%
        LEVEL_MASK.push([50,76,88,99,100,0]);   // chest 2 - 50%, 26%, 12%, 11%, 1%, 0%
        LEVEL_MASK.push([35,65,82,97,99,100]);  // chest 3 - 35%, 30%, 17%, 15%, 2%, 1%
        LEVEL_MASK.push([20,53,76,95,99,100]);  // chest 4 - 20%, 33%, 23%, 19%, 4%, 1%
        LEVEL_MASK.push([5,40,69,91,98,100]);   // chest 5 - 5%,  35%, 29%, 22%, 7%, 2%

        // item chances per chest
        ITEM_MASK.push([25,45,60,75,85,90,94,97,99,100]);   // items 0 - 25%, 20%, 15%, 15%, 10%, 5%, 4%, 3%, 2%, 1%
        ITEM_MASK.push([20,40,60,75,85,90,94,97,99,100]);   // items 1 - 20%, 20%, 20%, 15%, 10%, 5%, 4%, 3%, 2%, 1% 
        ITEM_MASK.push([15,35,55,75,85,90,94,97,99,100]);   // items 2 - 15%, 20%, 20%, 20%, 10%, 5%, 4%, 3%, 2%, 1%
        ITEM_MASK.push([10,30,50,70,80,86,91,95,98,100]);   // items 3 - 10%, 20%, 20%, 20%, 10%, 6%, 5%, 4%, 3%, 2%
        ITEM_MASK.push([5,25,45,65,80,86,91,95,98,100]);    // items 4 -  5%, 20%, 20%, 20%, 15%, 6%, 5%, 4%, 3%, 2%
        ITEM_MASK.push([5,20,40,60,75,82,88,93,97,100]);    // items 5 -  5%, 15%, 20%, 20%, 15%, 7%, 6%, 5%, 4%, 3%

        // power chances
        POWER_MASK.push(30);    // 30%
        POWER_MASK.push(60);    // 30%
        POWER_MASK.push(80);    // 20%
        POWER_MASK.push(100);   // 20%
    }

///// Sets
    function inputSeed(uint seed_) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender));
        _foundationSeed = seed_;
    }

    function setTokenAddress(address _FOGToken, address _FOGNFT, address _FOGHero) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender));
        FOGToken = _FOGToken;
        FOGNFT = _FOGNFT;
        FOGHero = _FOGHero;
    }

    function setArena(address _Arena) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender));
        grantRole(FOG_ARENA_ROLE, _Arena);
    }

    function setFOGManager(address _FOGManager) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender));
        grantRole(FOG_MANAGER_ROLE, _FOGManager);
    }

    function setNFTParams(uint _maxLevel, uint _maxNFTCategory, uint _maxNFTItem, uint _maxNFTRandom) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender));
        maxNFTLevel = _maxLevel;
        maxNFTCategory = _maxNFTCategory;
        maxNFTItem = _maxNFTItem;
        maxNFTRandom = _maxNFTRandom;
    }
    function setChestPrice(uint _type, uint _chestPrice, uint _lockTime) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender));
        chestPrices[_type].price = _chestPrice;
        chestPrices[_type].lockTime = _lockTime;
    }
///// Gets
    function getRandomSeed() internal view returns (uint) {
        return _foundationSeed;
    }

    function getChestPrice(uint _type) external view returns (uint) {
        return chestPrices[_type].price;
    }

///// Item Factory
    function buyChest(uint _type, address _user, uint _chestPrice) external {
        require(hasRole(FOG_MANAGER_ROLE, msg.sender));  
        lastOrderTimestamp = block.timestamp;

        // _type = level of chest. buying does not get hero boost
        openChest(_user, _chestPrice, _type, 0, 0);
    }

    function randomNFT(address user, uint _type) private view returns (uint tokenId, uint level, uint category, uint item, uint random, uint powerMin, uint powerMax) {
        uint totalSupply = IFOGNFT(FOGNFT).totalSupply();
        tokenId = totalSupply + 1;
        uint[6] memory randoms; // workaround for stack depth error
        randoms[0] = uint(keccak256(abi.encode(tokenId, user, blockhash(block.number - 30), getRandomSeed())));
        randoms[1] = uint(keccak256(abi.encode(randoms[0])));
        randoms[2] = uint(keccak256(abi.encode(randoms[1])));
        randoms[3] = uint(keccak256(abi.encode(randoms[2])));
        randoms[4] = uint(keccak256(abi.encode(randoms[3])));
        randoms[5] = uint(keccak256(abi.encode(randoms[4])));

        random = randoms[0].mod(maxNFTRandom) + 1;
        category = getMaskValue(randoms[1].mod(100), CATEGORY_MASK);
        level = getLevelMaskValue(randoms[2].mod(100), LEVEL_MASK[_type]) + 1; 
        item = getItemMaskValue(randoms[3].mod(100), ITEM_MASK[_type]) + 1;
        powerMin = getMaskValue(randoms[4].mod(100), POWER_MASK) + 1;
        powerMax = getMaskValue(randoms[5].mod(100), POWER_MASK) + 1;
    }

    // category, powerMin, powerMax
    function getMaskValue(uint random, uint[] memory mask) private pure returns (uint) {
        for (uint i=0; i<mask.length; i++) {
            if (random < mask[i]) {
                return i;
            }
        }
    }

    // level
    function getLevelMaskValue(uint random, uint[6] memory mask) private pure returns (uint) {
        for (uint i=0; i<mask.length; i++) {
            if (random < mask[i]) {
                return i;
            }
        }
    }

    // item
    function getItemMaskValue(uint random, uint[10] memory mask) private pure returns (uint) {
        for (uint i=0; i<mask.length; i++) {
            if (random < mask[i]) {
                return i;
            }
        }
    }

    function openChest(address user, uint price, uint _type, uint _heroId, uint _boostId) internal {
        uint tokenId;
        uint level;
        uint category;
        uint item;
        uint random;
        uint powerMin;
        uint powerMax;
        (tokenId, level, category, item, random, powerMin, powerMax) = randomNFT(user, _type);

        if (_type == 0) {               // empty chest chance
            if (uint(keccak256(abi.encode(random, blockhash(block.number - 40)))).mod(100) < 30) {    
                emit MintNFT(0, 0, 0, 0, 0, 0);
                return;
            }
        }

        if (_heroId != 0) {             // increases random variance by hero boost
            uint heroBoost = IFOGHero(FOGHero).getBoosting(_heroId);
            random = random + (((random + 100) * 1e12) / 100e12) * (heroBoost / 1e10);  // + 100 to avoid low randoms rounding to 0          
        }

        if (_boostId != 0) {             // boost reroll chance
            level = reroll(tokenId, user, _boostId, _type, level);
        } 

        IFOGNFT(FOGNFT).mint(tokenId, level, category, item, random, powerMin, powerMax);
        IERC721(FOGNFT).safeTransferFrom(address(this), user, tokenId);

        uint itemSupply = IFOGNFT(FOGNFT).itemSupply(category, level, item);
        emit MintNFT(level, category, item, random, tokenId, itemSupply);
        emit ChestBuy(user, price, _type, tokenId);
    }

    function stakeClaim(uint _type, address user, uint _heroId, uint _boostId) external {
        require(hasRole(FOG_MANAGER_ROLE, msg.sender) || hasRole(FOG_ARENA_ROLE, msg.sender));
        require(_type < chestPricesCount, "_type error");

        openChest(user, 0, _type, _heroId, _boostId);
    }

    function reroll(uint tokenId, address user, uint _boostId, uint _type, uint level) internal view returns (uint) {
        uint boost = IFOGNFT(FOGNFT).getBoosting(_boostId).div(1e8);
        uint newChance = uint(keccak256(abi.encode(tokenId, user, blockhash(block.number - 31), getRandomSeed())));
        if (newChance.mod(10000) < boost) {
            uint level2 = getLevelMaskValue(newChance.mod(100), LEVEL_MASK[_type]) + 1;
            if (level2 > level) {
                return level2;
            } else {
                return level;
            }
        }
        return level;
    }
}