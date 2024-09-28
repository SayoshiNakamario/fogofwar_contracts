// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;


import "../contracts/token/ERC20/ERC20.sol";
import "../contracts/access/Ownable.sol";
import "../contracts/math/SafeMath.sol";


// FOGXP
contract FOGXP is ERC20("FOGXP", "FXP"), Ownable {
    using SafeMath for uint256;

    uint public totalBurned;

    /// @notice Creates `_amount` token to `_to`. Must only be called by the owner (FOGManager).
    function mint(address _to, uint256 _amount) external onlyOwner {
        _mint(_to, _amount);
    }

    function burn(uint256 _amount) external {
        _burn(msg.sender, _amount);
        totalBurned = totalBurned.add(_amount);
    }
}
