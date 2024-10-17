// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "./interfaces/IKAP20.sol";
import "./interfaces/IKalamangFeeStorage.sol";

contract KalamangFeeStorageTestV1 is IKalamangFeeStorage {
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    address owner;
    uint256 public fee;
    IKAP20 public feeToken;

    constructor(address _tokenAddress) {
        owner = msg.sender;
        fee = 0;
        feeToken = IKAP20(_tokenAddress);
    }

    function setFee(uint256 _fee) external onlyOwner {
        fee = _fee;
    }

    function getFee() external view override returns (uint256) {
        return fee;
    }

    function setFeeToken(address _tokenAddress) external onlyOwner {
        feeToken = IKAP20(_tokenAddress);
    }

    function withdrawFee() external onlyOwner {
        feeToken.transfer(owner, feeToken.balanceOf(address(this)));
    }
}
