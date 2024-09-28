// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "../contracts/math/SafeMath.sol";

interface IDEX {
    function pendingGreenBen(uint256 _pid, address _user) external view returns (uint256);                      // BEN
    function pendingCake(uint256 _pid, address _user) external view returns (uint256);                          // 1BCH (& LAW?)
    function pendingSushi(uint256 _pid, address _user) external view returns (uint256);                         // Mistswap & Tango (& Verse?)
    function pendingTokens(uint256 _pid, address _user) external view returns (uint256);                        // Emberswap - multitokens
    function pending(uint256 _pid, address _user) external view returns (uint256);                              // Ki
}

contract Pending {
    using SafeMath for uint256;

    function pendingRewards(address _DEX, uint _pid, address _user) external view returns (uint256 amount) { 
        // Mistswap OR Tango
        if (_DEX == 0x5ee747274cDAc7F6CF5cD3aE2c53123BCEED59c4 || _DEX == 0x184B1f2F2839f90a5109Eb738a074b370B73773E) {
            amount = IDEX(_DEX).pendingSushi(_pid, _user);
            return amount;
        }
        // Benswap
        if (_DEX == 0xDEa721EFe7cBC0fCAb7C8d65c598b21B6373A2b6) {
           uint256 rewards = IDEX(_DEX).pendingGreenBen(_pid, _user);
           return rewards;
        }
    }
}
