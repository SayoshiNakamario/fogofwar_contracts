// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity 0.6.12;

import "../contracts/math/SafeMath.sol";
import "../contracts/token/ERC721/ERC721.sol";
import "../contracts/access/AccessControl.sol";
import "../contracts/proxy/Initializable.sol";

interface IFOGNFT {
    // scaled 1e12
    function getBoosting(uint _tokenId) external view returns (uint);

    // scaled 1e12
    function getLockTimeReduce(uint _tokenId) external view returns (uint);
}

// FOGHeroes
contract FOGHero is
    ERC721("FOGHero", "FOGHero"),
    Initializable,
    AccessControl
{
    using SafeMath for uint256;

    struct HeroInfo {   // cumulative ID of each FOGHero with their info
        address contractAddress;    // nftContracts ID
        uint256 contractID;         // NFT ID in contract
        uint256 category;           // hero type, preasale vs not
        uint256 level;              // level of the hero
        uint256 FXP;                // total FXP
        uint256 boost;              // modifier for farms and dungeons
        uint256 power;              // power value for Arena
        uint256 presaleBurns;       // number of presale heroes burned onto this hero
        uint256 trait;              // hero trait reference
        int256  locX;               // X coordinate
        int256  locY;               // Y coordinate
    }// fogID => HeroInfo
    mapping(uint => HeroInfo) public heroInfo;

    //  for randomized minting
    uint[20000] public mintIDs;
    uint private mintIndex;

    struct ContractInfo { 
        string ipfs;        // link to NFT contracts base ipfs link
        uint256 max;        // max number allowed to mint
        uint256 total;      // current total minted
    }// NFT contract => contracts info
    mapping(address => ContractInfo) public contractInfo;  

    struct FogInfo { 
        bool upgraded;        // whether NFT has upgraded to FOG-compatible
        uint256 fogID;        // the NFTs assigned fogID
    }// NFT contract => ID # => FogInfo
    mapping(address => mapping(uint => FogInfo)) public fogInfo;  

    uint public heroSupply = 0;            // Heroes total supply
    uint public supplyMax = 50000;         // Heroes maximum supply
    uint public FXPBurned = 0;             // FXP burned from

    bytes32 public constant FOG_FARMING_ROLE = keccak256("FARMING_CONTRACT_ROLE");
    bytes32 public constant FOG_MANAGER_ROLE = keccak256("MANAGER_CONTRACT_ROLE");
    bytes32 public constant GAME_MANAGER_ROLE = keccak256("GAME_CONTRACT_ROLE");

    uint256 public constant MULTIPLIER_SCALE = 1e12;

    function initialize(address admin) external initializer {
        _setupRole(DEFAULT_ADMIN_ROLE, admin);
        _setRoleAdmin(FOG_MANAGER_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(FOG_FARMING_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(GAME_MANAGER_ROLE, DEFAULT_ADMIN_ROLE);
    }

///// Sets
    function setFOGManager(address _fogManager) external {
        grantRole(FOG_MANAGER_ROLE, _fogManager);
    }
    function setFarmingAddr(address _farmingAddr) external {
        grantRole(FOG_FARMING_ROLE, _farmingAddr);
    }
    function setGameManager(address _gameManager) external {
        grantRole(GAME_MANAGER_ROLE, _gameManager);
    }
    function setBaseURI(string memory newBaseURI) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender));
        _setBaseURI(newBaseURI);
    }
    function setSupplyMax(uint _supplyMax) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender));
        supplyMax = _supplyMax;
    }
    function setHeroMax(address _contract, uint _heroMax) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender));
        contractInfo[_contract].max = _heroMax;
    }
    function setHeroIPFS(address _contract, string calldata _ipfs) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender));
        contractInfo[_contract].ipfs = _ipfs;
    }
    function addHeroContract(address _contract, uint _heroMax, string calldata _ipfs) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender));
        contractInfo[_contract].ipfs = _ipfs;
        contractInfo[_contract].max = _heroMax;
    }
    function setCoordinates(uint _heroID, int x, int y) external {
        require(hasRole(GAME_MANAGER_ROLE, msg.sender) || hasRole(FOG_MANAGER_ROLE, msg.sender));
        heroInfo[_heroID].locX = x;
        heroInfo[_heroID].locY = y;
    }
    function setTrait(uint _heroID, uint _trait) external {
        require(hasRole(FOG_MANAGER_ROLE, msg.sender));
        heroInfo[_heroID].trait = _trait;
    }
    function setCategory(uint _heroID, uint _category) external {
        require(hasRole(FOG_MANAGER_ROLE, msg.sender));
        heroInfo[_heroID].category = _category;
    }
///// Gets
    function getCategory(uint256 _heroId) external view returns (uint256) {
        uint256 category = heroInfo[_heroId].category;
        return category;
    }
    function getLevel(uint256 _heroId) external view returns (uint256) {
        uint256 level = heroInfo[_heroId].level;
        return level;
    }
    function getFXP(uint256 _heroId) external view returns (uint256) {
        uint256 FXP = heroInfo[_heroId].FXP;
        return FXP;
    }
    function getBoosting(uint256 _heroId) external view returns (uint256) {
        uint256 boost = heroInfo[_heroId].boost + (heroInfo[_heroId].presaleBurns * 1e10);
        return boost;
    }
    function getPower(uint256 _heroId) external view returns (uint256) {
        uint256 power = heroInfo[_heroId].power;
        return power;
    }
    function getMaxHeroes(address _contract) external view returns (uint256) {
        uint256 maxHeroes = contractInfo[_contract].max;
        return maxHeroes;
    }
    function getTotalHeroes(address _contract) external view returns (uint256) {
        uint256 totalHeroes = contractInfo[_contract].total;
        return totalHeroes;
    }
    function getHeroStruct(uint _heroId) external view returns (HeroInfo memory) {
        HeroInfo storage hero = heroInfo[_heroId];
        return hero;
    }
    function getHeroContract(uint _heroId) external view returns (address) {
        address heroContract = heroInfo[_heroId].contractAddress;
        return heroContract;
    }
    function getHeroContractID(uint _heroId) external view returns (uint) {
        uint heroContractID = heroInfo[_heroId].contractID;
        return heroContractID;
    }
    function getTokenURI(uint _heroId) external view returns (string memory) {
        string memory newtokenURI = string(abi.encodePacked(contractInfo[heroInfo[_heroId].contractAddress].ipfs,'/',heroInfo[_heroId].contractID.toString(),'.json'));
        return newtokenURI;
    }
    function getFogID(address _contract, uint _heroId) external view returns (uint) {
        uint heroID = fogInfo[_contract][_heroId].fogID;
        return heroID;
    }
    function getHeroUpgraded(address _contract, uint _heroId) external view returns (bool) {
        if (_contract == address(this)) {
            return true;
        }
        bool upgrade = fogInfo[_contract][_heroId].upgraded;
        return upgrade;
    }
    function getHeroX(uint _heroId) external view returns (int256) {
        int256 x = heroInfo[_heroId].locX;
        return x;
    }
    function getHeroY(uint _heroId) external view returns (int256) {
        int256 y = heroInfo[_heroId].locY;
        return y;
    }
    function getHeroTrait(uint _heroId) external view returns (uint) {
        uint heroTrait = heroInfo[_heroId].trait;
        return heroTrait;
    }
    function getHeroPresaleBurns(uint _heroId) external view returns (uint256) {
        uint heroBurns = heroInfo[_heroId].presaleBurns;
        return heroBurns;
    }
///// Do 
    function pickRandomId(uint random) private returns (uint id) {
        uint length = mintIDs.length - mintIndex++;                                                    // number of remaining mints
        require(length > 0, "All FOGHeroes minted");                                        
        uint randomIndex = random % length;                                                            // random number
        id = mintIDs[randomIndex] != 0 ? mintIDs[randomIndex] : randomIndex;                           // if result not 0 stay 0, else stay random number
        mintIDs[randomIndex] = uint(mintIDs[length - 1] == 0 ? length - 1 : mintIDs[length - 1]);      // if mint[last] == 0, set mint[random] = minted amount, else set mint[random] = mint[last]
        mintIDs[length - 1] = 0;                                                                       // set mint[last] = 0
    }   
    function mint(address user, uint256 heroId, uint256 category, address _contract, uint256 contractID) external {
        require(hasRole(FOG_MANAGER_ROLE, msg.sender));
        require(heroSupply < supplyMax,"Maximum FOGHeros reached");
        require(contractInfo[_contract].total < contractInfo[_contract].max,"Maximum FOGHeros reached for this contract");
        contractInfo[_contract].total++;        // increase individual contract total
        heroSupply++;                           // increase total FOGHeroes.

        if (_contract == address(this)) {                                                                   // if FOG minotaur:
            uint random = uint(keccak256(abi.encode(mintIndex++, heroId, blockhash(block.number - 30))));   // get pseudorandom number 
            uint randomID = pickRandomId(random);           // pick random ID
            contractID = randomID;                                   
            _safeMint(user, randomID);                      // mint randomized token direct to user from remaining mintIDs                                                            // mint token as usual
            string memory heroURI = string(abi.encodePacked(contractID.toString(),'.json'));        
            _setTokenURI(contractID, heroURI);             
        } else {                                                                       // otherwise an external NFT collection:
            require(!fogInfo[_contract][contractID].upgraded, "Already Upgraded");     // check if this external NFT was already upgraded
            fogInfo[_contract][contractID].upgraded = true;                            // flag it as now upgraded
        }

        fogInfo[_contract][contractID].fogID = heroId;              // set heroes fogID reference

        if (category == 0) {                                        // presale
            heroInfo[heroId].contractAddress = _contract;
            heroInfo[heroId].contractID = contractID;
            heroInfo[heroId].category = 0;
            heroInfo[heroId].level = 5;
            heroInfo[heroId].FXP = 0;
            heroInfo[heroId].boost = 5e10;     
            heroInfo[heroId].power = 5;
            heroInfo[heroId].presaleBurns = 0;     
        } else {                                                    // regular heroes
            heroInfo[heroId].contractAddress = _contract;
            heroInfo[heroId].contractID = contractID;
            heroInfo[heroId].category = 1;
            heroInfo[heroId].level = 1;
            heroInfo[heroId].FXP = 0;
            heroInfo[heroId].boost = 1e10;     
            heroInfo[heroId].power = 1;
            heroInfo[heroId].presaleBurns = 0;
        }
    }

    function addFXP(uint FOGXP, uint256 heroId) external {
        require(hasRole(FOG_MANAGER_ROLE, msg.sender) || hasRole(GAME_MANAGER_ROLE, msg.sender));
        HeroInfo storage hero = heroInfo[heroId];
        uint oldLevel = hero.level;

        hero.FXP = hero.FXP + FOGXP;                                // add new FXP to hero
        while (hero.FXP >= (hero.level * (hero.level * 2))) {       // level up hero based on new FXP total
            hero.level++;
            if (hero.category == 0) {                               // if presale
                if (hero.level <= 25) {                             // and still 25 or under
                    hero.boost = hero.boost + 1e10;                 // add a 1% boost
                }
            } else {                                                // otherwise regular hero
                if (hero.level <= 20) {                             // and still 20 or under
                    hero.boost = hero.boost + 1e10;                 // add a 1% boost
                }
            }
        }

        uint levelsGained = hero.level - oldLevel;                  // number of levels gained
        if (levelsGained > 0) {                                     // if leveled up
            hero.power = hero.power + (levelsGained * 10);          // gain 10 free power per level
        }
    }

    function removeFXP(uint FOGXP, uint256 heroId) external {
        require(hasRole(GAME_MANAGER_ROLE, msg.sender));
        HeroInfo storage hero = heroInfo[heroId];
        uint oldLevel = hero.level;

        if (hero.FXP >= FOGXP) {
            hero.FXP = hero.FXP - FOGXP;                            // remove FXP from hero as long as it doesn't go negative
        }
                              
        while (hero.FXP < (hero.level * (hero.level * 2))) {        // if new FXP total is under level requirement
            hero.level--;                                           // lose a level
            if (hero.category == 0) {                               // if presale
                if (hero.level < 25) {                              // and now under level 25
                    hero.boost = hero.boost - 1e10;                 // lose 1% boost
                }
            } else {                                                // otherwise regular hero
                if (hero.level < 20) {                              // and now under level 20
                    hero.boost = hero.boost - 1e10;                 // lose 1% boost
                }
            }
        }

        uint levelsLost = oldLevel - hero.level;                    // number of levels lost
        hero.power = hero.power - (levelsLost * 10);                // lose 10 free levelup power per level lost

        if (hero.level < oldLevel && hero.power > (hero.level * 10)) {  // if lost a level and have extra power from merging
            hero.power = hero.power - (hero.power / 10);                // remove 10% hero power
        }
    }

    function addPower(uint256 _heroId, uint256 _power) external {
        require(hasRole(FOG_MANAGER_ROLE, msg.sender));
        HeroInfo storage hero = heroInfo[_heroId];
        hero.power = hero.power + _power;
    }
    function addBoost(uint256 _heroId, uint256 _amount) external {
        require(hasRole(FOG_MANAGER_ROLE, msg.sender));
        heroInfo[_heroId].boost = heroInfo[_heroId].boost + (1e10 * _amount);
    }
    function addPresaleBurn(uint256 _heroId, uint256 _amount) external {
        require(hasRole(FOG_MANAGER_ROLE, msg.sender));
        heroInfo[_heroId].presaleBurns = heroInfo[_heroId].presaleBurns + _amount;
    }
    function _setTokenURI(uint256 tokenId, string memory _tokenURI) internal virtual override {
        _tokenURIs[tokenId] = _tokenURI;
    }
}
