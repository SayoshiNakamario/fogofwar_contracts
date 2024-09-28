// SPDX-License-Identifier: MIT

pragma solidity 0.8.12;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract FOGProxy is TransparentUpgradeableProxy {
    constructor(address _logic, address admin_, bytes memory _data) 
        public 
        payable 
        TransparentUpgradeableProxy(_logic, admin_, _data) { }
}