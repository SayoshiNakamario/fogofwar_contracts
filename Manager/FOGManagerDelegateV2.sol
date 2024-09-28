// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "../contracts/math/SafeMath.sol";
import "../contracts/token/ERC20/IERC20.sol";
import "../contracts/token/ERC20/SafeERC20.sol";
import "../contracts/token/ERC721/IERC721.sol";
import "../contracts/access/AccessControl.sol";
import "../contracts/proxy/Initializable.sol";
import "../contracts/token/ERC721/ERC721Holder.sol";
import "./FOGManagerStorage.sol";
import "./FOGXP.sol";

interface IArena {
    function payEntry(uint _pid, uint _tickets) external;
    function payTicket(address _user) external;
    function checkTicket(address _user) external view returns (bool);
    function stakeFOG(uint pid, uint stakeAmount) external;
    function arenaActive(uint pid) external view returns (bool);
    function isFarming(uint pid) external view returns (bool);
    function commitArena(uint pid, uint _nftBoostId, uint _nftLockId, uint _heroId) external;
    function arenaLength() external view returns (uint);
    function lastCalled() external view returns (uint);
}
interface IItemFactory {
    function stakeClaim(uint _type, address user, uint heroId, uint boostId) external;
    function getChestPrice(uint _type) external view returns (uint);
    function buyChest(uint _type, address user, uint chestPrice) external;
}
interface IFOGHero {
    function mint(address _user, uint _heroId, uint _category, address _contract, uint _contractID) external;
    function heroSupply() external view returns (uint);
    function getTotalHeroes(address _contract) external view returns (uint);
    function getHeroContract(uint _heroId) external view returns (address);
    function getHeroContractID(uint _heroId) external view returns (uint);
    function addFXP(uint FXP, uint heroId) external;
    function addPower(uint heroId, uint power) external;
    function addBoost(uint heroId, uint amount) external;
    function addPresaleBurn(uint heroId, uint amount) external;
    function burnAPresale() external;
    function getHeroUpgraded(address _contract, uint _heroId) external view returns (bool);
    function getFogID(address _contract, uint _heroId) external view returns (uint);
    function getFXP(uint _heroId) external view returns (uint256);
    function getPower(uint _heroId) external view returns (uint256);
    function getHeroPresaleBurns(uint _heroId) external view returns (uint256);
    function getLevel(uint _heroId) external view returns (uint256);
    function getCategory(uint _heroId) external view returns (uint256);
    function setCategory(uint _heroId, uint _category) external;
    function setCoordinates(uint _heroID, int x, int y) external;
}          
interface IFOGToken {
    function burn(uint amount) external;
}
interface IBoosting {
    function deposit(uint pid, address user, uint lockTime) external;
    function withdraw(uint pid, address user) external;
}
interface IFOGNFT {
    function getLockTimeReduce(uint nftLockId) external view returns (uint256);
    function getPower(uint tokenId) external returns (uint);
    function getRandom(uint tokenId) external returns (uint256);
}
interface IDungeons {
    function dungeonAvailable(uint _type, address user) external view returns (bool);
    function getStakePrice(uint _type) external returns(uint);
    function stakeFOG(uint _type, address user, uint stakeAmount) external;
    function stakeClaim(uint _type, uint _amount) external;
}

contract FOGManagerDelegate is Initializable, AccessControl, ERC721Holder, FOGManagerStorage {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    FOGXP public FXP;
    bytes32 constant FOG_FARMING_ROLE = keccak256("FARMING_CONTRACT_ROLE");
    uint constant MULTIPLIER_SCALE = 1e12;

    function initialize(address admin, address _BCH, address _presaleAddr) external initializer {
        _setupRole(DEFAULT_ADMIN_ROLE, admin);
        _setRoleAdmin(FOG_FARMING_ROLE, DEFAULT_ADMIN_ROLE);
        BCH = _BCH;
        presaleAddr = _presaleAddr;
    }

////// Sets
    function setAllAddresses(address _FOGHero, address _FOGNFT, address _ItemFactory, address _Boosting, address _Dungeons, address _Arena, address _FOGToken, FOGXP _FXP) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender));
        FOGHero = _FOGHero;
        FOGNFT = _FOGNFT;
        ItemFactory = _ItemFactory;
        Boosting = _Boosting;
        Dungeons = _Dungeons;
        Arena = _Arena;
        FOGToken = _FOGToken;
        FXP = _FXP;
    }
    function setFOGFarming(address _FOGFarming) external {
        grantRole(FOG_FARMING_ROLE, _FOGFarming);
    }
    function setFOGHero(address _FOGHero) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender));
        FOGHero = _FOGHero;
    }
    function setFOGNFT(address _FOGNFT) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender));
        FOGNFT = _FOGNFT;
    }
    function setItemFactory(address _ItemFactory) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender));
        ItemFactory = _ItemFactory;
    }
    function setBoosting(address _Boosting) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender));
        Boosting = _Boosting;
    }   
    function setDungeons(address _Dungeons) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender));
        Dungeons = _Dungeons;
    }   
    function setArena(address _Arena) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender));
        Arena = _Arena;
    } 
    function setArenaWin(uint _chestType) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender));
        arenaWin = _chestType;
    }   
    function setArenaLoss(uint _chestType) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender));
        arenaLoss = _chestType;
    } 
    function setArenaFee(uint _arenaFee) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender));
        arenaFee = _arenaFee;
    } 
    function setHeroPrice(uint _heroPrice) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender));
        heroPrice = _heroPrice;
    }
    function setPresalePrice(uint _presalePrice) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender));
        presalePrice = _presalePrice;
    }
    function setPresaleActive() external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender));
        presaleActive = !presaleActive;
    }
////// Gets
    function getHeroId(uint _type, address user) external view returns (uint) {
        return boostInfo[_type][user].heroId;
    } 
    function getLockId(uint _type, address user) external view returns (uint) {
        return boostInfo[_type][user].nftLockId;
    } 
    function getBoostId(uint _type, address user) external view returns (uint) {
        return boostInfo[_type][user].nftBoostId;
    } 
    function getStakeHeroId(uint _type, address user) external view returns (uint) {
        return stakeInfo[_type][user].heroId;
    } 
    function getStakeLockId(uint _type, address user) external view returns (uint) {
        return stakeInfo[_type][user].nftLockId;
    } 
    function getStakeBoostId(uint _type, address user) external view returns (uint) {
        return stakeInfo[_type][user].nftBoostId;
    } 
    function getArenaHeroId(uint pid, address _user) external view returns (uint) {
        return arenaInfo[pid][_user].heroId;
    } 
    function getArenaBoostId(uint pid, address _user) external view returns (uint) {
        return arenaInfo[pid][_user].nftBoostId;
    } 
////// Farms
    function depositBoosting(uint _pid, address _user, uint _lockTime, uint _nftBoostId, uint _nftLockId, uint _amount) external {
        require(hasRole(FOG_FARMING_ROLE, msg.sender));  
        BoostInfo storage info = boostInfo[_pid][_user];
   
        if (_nftBoostId != 0) {
            if (info.nftBoostId != 0) { 
                IERC721(FOGNFT).safeTransferFrom(address(this), _user, info.nftBoostId);
            }
            IERC721(FOGNFT).safeTransferFrom(_user, address(this), _nftBoostId);
            info.nftBoostId = _nftBoostId;
        }
        if (_nftLockId != 0) {
            if (info.nftLockId != 0) {
                IERC721(FOGNFT).safeTransferFrom(address(this), _user, info.nftLockId);
            }
            info.nftLockId = _nftLockId;
            IERC721(FOGNFT).safeTransferFrom(_user, address(this), _nftLockId);
        }
        if (_lockTime != 0 || _amount != 0) {
            IBoosting(Boosting).deposit(_pid, _user, _lockTime);
        }
    }  
    function depositHero(uint _pid, address _user, uint _heroId, address _heroContract) external {
        require(hasRole(FOG_FARMING_ROLE, msg.sender));
        bool upgrade = IFOGHero(FOGHero).getHeroUpgraded(_heroContract, _heroId);   
        require(upgrade, "Not upgraded");
        uint heroId = boostInfo[_pid][_user].heroId;
        uint fogId = IFOGHero(FOGHero).getFogID(_heroContract, _heroId);

        if (heroId != 0) {
            address heroContract = IFOGHero(FOGHero).getHeroContract(heroId);
            uint heroContractID = IFOGHero(FOGHero).getHeroContractID(heroId);
            IERC721(heroContract).safeTransferFrom(address(this), _user, heroContractID);
        } 

        IERC721(_heroContract).safeTransferFrom(_user, address(this), _heroId);
        boostInfo[_pid][_user].heroId = fogId;
    }
    function withdrawNFT(uint _pid, address _user, bool _nftBoost, bool _nftLock, bool _hero) external {
        require(hasRole(FOG_FARMING_ROLE, msg.sender));
        BoostInfo storage info = boostInfo[_pid][_user];

        if (_nftBoost == true && info.nftBoostId != 0) {
            IERC721(FOGNFT).safeTransferFrom(address(this), _user, info.nftBoostId);
            info.nftBoostId = 0;
        }
        if (_nftLock == true && info.nftLockId != 0) {
            IERC721(FOGNFT).safeTransferFrom(address(this), _user, info.nftLockId);
            info.nftLockId = 0;
        }
        if (_hero == true && info.heroId != 0) {
            address heroContract = IFOGHero(FOGHero).getHeroContract(info.heroId);
            uint heroContractID = IFOGHero(FOGHero).getHeroContractID(info.heroId);
            IERC721(heroContract).safeTransferFrom(address(this), _user, heroContractID);
            info.heroId = 0;
        }

        IBoosting(Boosting).withdraw(_pid, _user);
    } 
////// Dungeons
    function dungeonStake(uint _type) external payable  {
        uint amount = stakeInfo[_type][msg.sender].stakedFOG;
        require(amount == 0, "Claim first");
        
        uint256 stakeAmount = IDungeons(Dungeons).getStakePrice(_type);
        IERC20(FOGToken).safeTransferFrom(msg.sender, address(this), stakeAmount);
        stakeInfo[_type][msg.sender].stakedFOG = stakeAmount;
        IDungeons(Dungeons).stakeFOG(_type, msg.sender, stakeAmount);

    }
    function stakeClaim(uint _type) external {
        require(msg.sender == tx.origin);
        require(IDungeons(Dungeons).dungeonAvailable(_type, msg.sender));
        StakeInfo storage info = stakeInfo[_type][msg.sender];
        require(info.stakedFOG > 0, "no stake");
        uint amount = info.stakedFOG;
        uint heroId = stakeInfo[_type][msg.sender].heroId;
        uint boostId = stakeInfo[_type][msg.sender].nftBoostId;

        info.stakedFOG = 0;
        IDungeons(Dungeons).stakeClaim(_type, amount);
        IERC20(FOGToken).safeTransfer(msg.sender, amount);
        IItemFactory(ItemFactory).stakeClaim(_type, msg.sender, heroId, boostId);

        if (heroId != 0) {
            mintFXP(msg.sender, ((_type + 1) * 1e18));
        }
    }
   function equipDungeon(uint _type, uint _nftBoostId, uint _nftLockId, uint _heroId, address _heroContract) external  {
        require(IDungeons(Dungeons).dungeonAvailable(_type, msg.sender));
        StakeInfo storage info = stakeInfo[_type][msg.sender];

        if (_nftBoostId != 0) { 
            if (info.nftBoostId != 0) {
                IERC721(FOGNFT).safeTransferFrom(address(this), msg.sender, info.nftBoostId);
            }
            info.nftBoostId = _nftBoostId;
            IERC721(FOGNFT).safeTransferFrom(msg.sender, address(this), _nftBoostId);
        }
        if (_nftLockId != 0) {
            if (info.nftLockId != 0) {
                IERC721(FOGNFT).safeTransferFrom(address(this), msg.sender, info.nftLockId);
            }
            info.nftLockId = _nftLockId;
            IERC721(FOGNFT).safeTransferFrom(msg.sender, address(this), _nftLockId);
        }
        if (_heroId != 0) {
            bool upgrade = IFOGHero(FOGHero).getHeroUpgraded(_heroContract, _heroId); 
            require(upgrade, "Not upgraded");
            if (info.heroId != 0) {
                uint heroContractID = IFOGHero(FOGHero).getHeroContractID(info.heroId);
                address heroContract = IFOGHero(FOGHero).getHeroContract(info.heroId);
                IERC721(heroContract).safeTransferFrom(address(this), msg.sender, heroContractID);
            }
            info.heroId = IFOGHero(FOGHero).getFogID(_heroContract, _heroId); 
            IERC721(_heroContract).safeTransferFrom(msg.sender, address(this), _heroId);
        }
    }
////// ItemFactory
    function buyChest(uint _type) external payable {
        require(msg.sender == tx.origin);
        uint chestPrice = IItemFactory(ItemFactory).getChestPrice(_type);

        IERC20(FOGToken).safeTransferFrom(msg.sender, address(this), chestPrice);
        IFOGToken(FOGToken).burn(chestPrice);
        IItemFactory(ItemFactory).buyChest(_type, msg.sender, chestPrice);
    }
////// HeroFactory (FOGHero)
    function buyHero(address _contract, uint256 _contractID, uint256 _amount, uint256 _type) external payable {
        require(msg.sender == tx.origin);
        require(_amount < 11, "Max 10");
        if (_amount > 1) {
            require(_contract == FOGHero);
        }
        for (uint i = 0; i < _amount; i++) {
            uint heroSupply = IFOGHero(FOGHero).heroSupply();
            uint heroId = heroSupply + 1;
            
            if (_contract == FOGHero) {
                uint totalHeroes = IFOGHero(FOGHero).getTotalHeroes(_contract);
                _contractID = totalHeroes + 1;
            } else { 
                require(msg.sender == IERC721(_contract).ownerOf(_contractID));
            }

            if (_contract == 0x91bc4F61d45Dfbb9C277CDF6928923Cb46e8A2E9) {  // cryptoRAT body limit
                require(_contractID < 10026);    
            }
            
            if (_type == 0 && presaleActive) {
                IERC20(BCH).safeTransferFrom(msg.sender, address(presaleAddr), presalePrice);
                IFOGHero(FOGHero).mint(msg.sender, heroId, 0, _contract, _contractID);
            } else {
                IERC20(FOGToken).safeTransferFrom(msg.sender, address(this), heroPrice);
                IFOGToken(FOGToken).burn(heroPrice);
                IFOGHero(FOGHero).mint(msg.sender, heroId, 1, _contract, _contractID);
            }
        }
    }
    function addFXP(uint _FXP, uint _heroId) external {
        require(_FXP >= 1);
        IERC20(FXP).safeTransferFrom(msg.sender, address(this), (_FXP * 1e18));
        FXP.burn((_FXP * 1e18));
        IFOGHero(FOGHero).addFXP(_FXP, _heroId);
    }
    function mergeItem(uint[] calldata itemIDs, uint heroId) external {
        uint256 totalPower;
        for (uint i = 0; i < itemIDs.length; i++) {
            uint power = IFOGNFT(FOGNFT).getPower(itemIDs[i]);
            totalPower = totalPower + power;
            IERC721(FOGNFT).safeTransferFrom(msg.sender, address(this), itemIDs[i]);
            IERC721(FOGNFT).safeTransferFrom(address(this), address(0x0f), itemIDs[i]); 
        }     
        IFOGHero(FOGHero).addPower(heroId, totalPower);                         
    }
    function mergeHeroes(uint burnHeroId, uint keepHeroId, uint[] calldata itemIDs) external {
        require(burnHeroId != keepHeroId, "Same Hero");
        address burnContract = IFOGHero(FOGHero).getHeroContract(burnHeroId);
        uint256 burnContractID = IFOGHero(FOGHero).getHeroContractID(burnHeroId);
        uint256 burnsLevel = IFOGHero(FOGHero).getLevel(burnHeroId); 
        uint256 burnsFXP = IFOGHero(FOGHero).getFXP(burnHeroId);
        uint256 burnsCategory = IFOGHero(FOGHero).getCategory(burnHeroId);
        uint256 keepsCategory = IFOGHero(FOGHero).getCategory(keepHeroId);
        uint256 burnsPower = IFOGHero(FOGHero).getPower(burnHeroId) - (burnsLevel * 10); 
        uint256 burnsPresaleBurns = IFOGHero(FOGHero).getHeroPresaleBurns(burnHeroId);
        
        IFOGHero(FOGHero).addPower(keepHeroId, burnsPower);
        IFOGHero(FOGHero).addFXP(burnsFXP, keepHeroId);
        IFOGHero(FOGHero).setCoordinates(burnHeroId, 0, 0);

        if (burnsCategory == 0 && keepsCategory == 0) { 
            IFOGHero(FOGHero).addPresaleBurn(keepHeroId, (1 + burnsPresaleBurns));
            IFOGHero(FOGHero).burnAPresale();
        } else if (burnsCategory == 0) {
            IFOGHero(FOGHero).setCategory(keepHeroId, burnsCategory);
            IFOGHero(FOGHero).addPresaleBurn(keepHeroId, burnsPresaleBurns);

            uint256 keepLevel = IFOGHero(FOGHero).getLevel(keepHeroId);
            if (keepLevel > 20) {
                uint256 excessLevel = keepLevel - 20;
                if (excessLevel > 5) {
                    excessLevel = 5;
                }
                IFOGHero(FOGHero).addBoost(keepHeroId, excessLevel);
            }
        }

        if (itemIDs.length > 0) { 
            require(itemIDs.length < 3, "Max 2 items");
            uint256 bonusPower;
            for (uint i = 0; i < itemIDs.length; i++) {
                IERC721(FOGNFT).safeTransferFrom(msg.sender, address(this), itemIDs[i]);
                IERC721(FOGNFT).safeTransferFrom(address(this), address(0x0f), itemIDs[i]);
                uint256 random = IFOGNFT(FOGNFT).getRandom(itemIDs[i]);
                uint256 randomPower = (burnsLevel * 10 * 1e12 * random / 2) / (1e12 * 10000);
                bonusPower = bonusPower + randomPower;
            }    
            IFOGHero(FOGHero).addPower(keepHeroId, bonusPower);
        }          

        IERC721(burnContract).safeTransferFrom(msg.sender, address(this), burnContractID);
        IERC721(burnContract).safeTransferFrom(address(this), address(0x0f), burnContractID);
    }
////// Arena
    function payEntry(uint _pid, uint _tickets) external payable {
        uint totalFee = (arenaFee * 10) * _tickets;
        IERC20(FOGToken).safeTransferFrom(msg.sender, address(this), totalFee);
        IFOGToken(FOGToken).burn(totalFee);
        IArena(Arena).payEntry(_pid, _tickets);
    }

    function payTicket() external payable {
        IERC20(FOGToken).safeTransferFrom(msg.sender, address(this), arenaFee);
        IFOGToken(FOGToken).burn(arenaFee);
        IArena(Arena).payTicket(msg.sender);
    }

    function stakeArena(uint pid, uint stakeAmount) public payable  {
        ArenaInfo storage arena = arenaInfo[pid][msg.sender];
        require(arena.lockBlock > block.number, "Must commit");

        IERC20(FOGToken).safeTransferFrom(msg.sender, address(this), stakeAmount);
        arena.stakedFOG = arena.stakedFOG + stakeAmount;

        uint boost = IFOGNFT(FOGNFT).getLockTimeReduce(arena.nftLockId);        
        if (boost != 0) {
            stakeAmount = stakeAmount + ((stakeAmount * boost) / 1e12);
        }

        IArena(Arena).stakeFOG(pid, stakeAmount);
    }
   function equipArena(uint pid, uint _nftBoostId, uint _nftLockId, uint _heroId, address _heroContract, uint _stakeAmount) external {
        require(IArena(Arena).arenaActive(pid), "Arena inactive");
        require(IArena(Arena).checkTicket(msg.sender), "Need ticket");
        ArenaInfo storage arena = arenaInfo[pid][msg.sender];
        require(arena.lockBlock < block.number);

        if (_nftBoostId != 0) { 
            if (arena.nftBoostId != 0) {
                IERC721(FOGNFT).safeTransferFrom(address(this), msg.sender, arena.nftBoostId);
            }
            arena.nftBoostId = _nftBoostId;
            IERC721(FOGNFT).safeTransferFrom(msg.sender, address(this), _nftBoostId);
        }
        if (_nftLockId != 0) {
            if (arena.nftLockId != 0) {
                IERC721(FOGNFT).safeTransferFrom(address(this), msg.sender, arena.nftLockId);
            }
            arena.nftLockId = _nftLockId;
            IERC721(FOGNFT).safeTransferFrom(msg.sender, address(this), _nftLockId);
        }
        if (_heroId != 0) {          
            if (arena.heroId != 0) {
                uint ContractID = IFOGHero(FOGHero).getHeroContractID(arena.heroId);
                address Contract = IFOGHero(FOGHero).getHeroContract(arena.heroId);
                IERC721(Contract).safeTransferFrom(address(this), msg.sender, ContractID);
            }
            arena.heroId = IFOGHero(FOGHero).getFogID(_heroContract, _heroId);
            IERC721(_heroContract).safeTransferFrom(msg.sender, address(this), _heroId);
        }
        if (_stakeAmount != 0) {
            IERC20(FOGToken).safeTransferFrom(msg.sender, address(this), _stakeAmount);
            arena.stakedFOG = arena.stakedFOG + _stakeAmount;
        }
    }
    function commitArena(uint pid) external  {
        require(IArena(Arena).arenaActive(pid), "LP inactive");
        require(IArena(Arena).checkTicket(msg.sender), "Buy ticket");
        ArenaInfo storage arena = arenaInfo[pid][msg.sender];
        require(arena.lockBlock < block.number, "Already committed");
        uint arenaLength = IArena(Arena).arenaLength();
        uint lastCalled = IArena(Arena).lastCalled();

        if (arena.lockStart != 0) {
            claimArena(pid);
        }

        arena.lockBlock = lastCalled + arenaLength;     // end of the current arena round
        arena.lockStart = block.number;                 // block user committed to this arena

        IArena(Arena).commitArena(pid, arena.nftBoostId, arena.nftLockId, arena.heroId);

        if (arena.stakedFOG != 0) {
            uint boost = IFOGNFT(FOGNFT).getLockTimeReduce(arena.nftLockId);
            uint stakeAmount = arena.stakedFOG;      
            if (boost != 0) {
                stakeAmount = arena.stakedFOG + ((arena.stakedFOG * boost) / 1e12);
            }

            IArena(Arena).stakeFOG(pid, stakeAmount);
        }
    }
    function unstakeArena(uint pid, uint unstakeAmount) external  {
        ArenaInfo storage arena = arenaInfo[pid][msg.sender];
        require(arena.lockBlock < block.number, "Arena running");
        arena.stakedFOG = arena.stakedFOG - unstakeAmount;
        IERC20(FOGToken).safeTransfer(msg.sender, unstakeAmount);

        if (arena.lockStart != 0) {
            claimArena(pid);
        }
    }
    function abandonArena(uint pid) external  {
        ArenaInfo storage arena = arenaInfo[pid][msg.sender];
        require(block.number > arena.lockBlock, "Arena running");

        if (arena.lockStart != 0) {
            claimArena(pid);
        }
        if (arena.nftBoostId != 0) {
            IERC721(FOGNFT).safeTransferFrom(address(this), msg.sender, arena.nftBoostId);
            arena.nftBoostId = 0;
        }
        if (arena.nftLockId != 0) {
            IERC721(FOGNFT).safeTransferFrom(address(this), msg.sender, arena.nftLockId);
            arena.nftLockId = 0;
        }
        if (arena.heroId != 0) {
            uint heroContractID = IFOGHero(FOGHero).getHeroContractID(arena.heroId);
            address heroContract = IFOGHero(FOGHero).getHeroContract(arena.heroId);
            IERC721(heroContract).safeTransferFrom(address(this), msg.sender, heroContractID);
            arena.heroId = 0;
        }
        if (arena.stakedFOG != 0) {
            uint balance = arena.stakedFOG;
            arena.stakedFOG = 0;
            IERC20(FOGToken).safeTransfer(msg.sender, balance);
        }
    }

    function claimArena(uint pid) public  {
        ArenaInfo storage arena = arenaInfo[pid][msg.sender];
        require(arena.lockBlock != 0, "Commit first");
        require(arena.lockBlock < block.number, "End Arena first");
        uint blocks = arena.lockBlock - arena.lockStart; 
        
        arena.lockBlock = 0;
        arena.lockStart = 0;   
         
        if (arena.heroId != 0) { 
            mintFXP(msg.sender, ((blocks * 1e13) * 7));
        }

        if (IArena(Arena).isFarming(pid) && arena.stakedFOG > 199) {
            if (blocks > 27000) {
                IItemFactory(ItemFactory).stakeClaim(arenaWin, msg.sender, arena.heroId, arena.nftBoostId);
            }
        } else if (blocks > 27000 && arena.stakedFOG > 199) {
            IItemFactory(ItemFactory).stakeClaim(arenaLoss, msg.sender, arena.heroId, arena.nftBoostId);
        }
    }
    function mintFXP(address user, uint amount) private {
        FXP.mint(user, amount);
    }

}
