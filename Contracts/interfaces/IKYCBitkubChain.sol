// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IKYCBitkubChain {
    function kycsLevel(address _addr) external view returns (uint256);

    function isAddressKyc(address _address) external view returns (bool);
}
