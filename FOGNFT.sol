// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity 0.6.12;

import "../contracts/math/SafeMath.sol";
import "../contracts/token/ERC721/ERC721.sol";
import "../contracts/access/AccessControl.sol";
import "../contracts/proxy/Initializable.sol";

// FOGNFT
contract FOGNFT is
    ERC721("FOGNFT", "FOGNFT"),
    Initializable,
    AccessControl
{
    using SafeMath for uint256;

    struct TokenInfo {
        uint256 level;      // rarity
        uint256 category;   // weapon or armor
        uint256 item;       // item type
        uint256 random;     // boost variance
        uint256 boost;      // boosting or reduction
        uint256 powerMin;   // power min variance
        uint256 powerMax;   // power max variance
    }

    // tokenId => tokenInfo
    mapping(uint => TokenInfo) public tokenInfo;

    // category => level => item => tokenURI
    mapping(uint => mapping(uint => mapping(uint => string))) public nftURI;

    // chance scaled 1e12
    mapping(uint => uint) public LEVEL_CHANCE;      // 60%, 30%, 5%, 1%
    mapping(uint => uint) public ITEM_CHANCE;       // 35%, 30%, 20%, 10%, 5%

    // NFT item's total supply: category => level => item
    mapping(uint => mapping(uint => mapping(uint => uint))) public itemSupply;

    bytes32 public constant ITEM_FACTORY_ROLE =
        keccak256("ITEM_FACTORY_ROLE");

    uint256 public constant MULTIPLIER_SCALE = 1e12;

    function initialize(address admin) external initializer {
        _setupRole(DEFAULT_ADMIN_ROLE, admin);
        _setRoleAdmin(ITEM_FACTORY_ROLE, DEFAULT_ADMIN_ROLE);

        // Level rarity bonus
        LEVEL_CHANCE[0] = 1e6;      
        LEVEL_CHANCE[1] = 14e5; 
        LEVEL_CHANCE[2] = 19e5;
        LEVEL_CHANCE[3] = 26e5;
		LEVEL_CHANCE[4] = 32e5; 
        LEVEL_CHANCE[5] = 40e5;

        // Item rarity bonus
        ITEM_CHANCE[0] = 5e4;
        ITEM_CHANCE[1] = 6e4;
        ITEM_CHANCE[2] = 7e4; 
        ITEM_CHANCE[3] = 8e4; 
        ITEM_CHANCE[4] = 9e4;
        ITEM_CHANCE[5] = 10e4;
        ITEM_CHANCE[6] = 11e4;  
        ITEM_CHANCE[7] = 12e4;  
        ITEM_CHANCE[8] = 13e4;    
        ITEM_CHANCE[9] = 14e4; 

    } 
    function setItemFactory(address _nftFactory) external {
        grantRole(ITEM_FACTORY_ROLE, _nftFactory);
    }

    function setBaseURI(string memory newBaseURI) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender));
        _setBaseURI(newBaseURI);
    }

    function setNftURI(
        uint256 level,
        uint256 category,
        uint256 item,
        string memory URI
    ) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender));
        nftURI[category][level][item] = URI;
    }

function setMultiNftURI(
        uint256[] memory categorys,
        uint256[] memory levels,
        uint256[] memory items,
        string[] memory URIs
    ) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender));
        uint c = 0;
        uint l = 0;
        uint i = 0;

        for (uint t = 0; t < URIs.length; t++) {
            nftURI[categorys[c]][levels[l]][items[i]] = URIs[t];
            i++;
                if (i == 10 && l == 5) {
                    c = 1;
                    l = 0;
                    i = 0;
                } else if (i == 10) {
                    i = 0;
                    l = l + 1;
                }
        }
    }

    function getNftURI(uint256 category, uint256 level, uint256 item) external view returns (string memory) {
        return nftURI[category][level][item];
    }

    // Retrieve boosting amount in 1e12
    function getBoosting(uint256 _tokenId) external view returns (uint256) {
        require(tokenInfo[_tokenId].category == 1);
        uint256 boost = tokenInfo[_tokenId].boost;
        return boost;
    }

    // Retrieve timelock reduction amount in 1e12
    function getLockTimeReduce(uint256 _tokenId) external view returns (uint256) {
        require(tokenInfo[_tokenId].category == 0);
        uint256 reduce = tokenInfo[_tokenId].boost;
        return reduce;
    }
    // Retrieve random 'luck' stat
    function getRandom(uint256 _tokenId) external view returns (uint256) {
        uint256 random = tokenInfo[_tokenId].random;
        return random;
    }
    function mint(
        uint256 tokenId,
        uint256 _level,
        uint256 _category,
        uint256 _item,
        uint256 _random,
        uint256 _powerMin,
        uint256 _powerMax
    ) external {
        require(hasRole(ITEM_FACTORY_ROLE, msg.sender));
        require(
            _level > 0 && _level < 7,
            "level must larger than 0 and less than 7"
        );
        uint256 base = (LEVEL_CHANCE[_level - 1] * ITEM_CHANCE[_level - 1]);         // initial boost

        tokenInfo[tokenId].level = _level;
        tokenInfo[tokenId].category = _category;
        tokenInfo[tokenId].item = _item;
        tokenInfo[tokenId].random = _random;
        tokenInfo[tokenId].powerMin = _level + _powerMin; 
        tokenInfo[tokenId].powerMax = _level + _item + _powerMin + _powerMax; 
        // tokenInfo[tokenId].boost
            if (_category == 0 ) {                                                              // if cooldown reduction item
                uint totalBoost = base + ((base / 1e4) * (_random));                            // base boost + bonus up to 75%
                tokenInfo[tokenId].boost = (totalBoost.sub((totalBoost.div(1e4)).mul(5000)));   // totalBoost - 50%
            } else {                                                                    
                tokenInfo[tokenId].boost = (base + (((base / 1e4) * _random)));         // otherwise base boost + bonus up to 75%
            }
        _safeMint(msg.sender, tokenId);
        _setTokenURI(tokenId, nftURI[_category][_level][_item]);
        itemSupply[_category][_level][_item]++;
    }

    // Get power of item for merging to hero
    function getPower(uint256 _tokenId) external view returns (uint256) {
        TokenInfo storage item = tokenInfo[_tokenId];
        uint size = 1 + (item.powerMax - item.powerMin);
        uint random = uint(keccak256(abi.encode(_tokenId, totalSupply(), blockhash(block.number - 30))));

        uint[] memory powerChance = new uint[](size);

        for (uint i = 0; i < size; i++) {
            powerChance[i] = i + item.powerMin;
        }

        uint result = powerChance[random.mod(size)];
        return result;
    }

}
