// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "./interfaces/IKAP20.sol";
import "./interfaces/IKalamangFeeStorage.sol";

contract KalamangFeeStorage is IKalamangFeeStorage {
    modifier onlyOwner() {
        require(
            msg.sender == owner,
            "KalamangFeeStorage : Only owner can call this function"
        );
        _;
    }

    address owner;
    uint256 public fee;

    constructor() {
        owner = msg.sender;
        fee = 0;
    }

    function setFee(uint256 _fee) external onlyOwner {
        fee = _fee;
    }

    function getFee() external view override returns (uint256) {
        return fee;
    }

    function withdrawFee(
        address[] calldata _tokenAddresses
    ) external onlyOwner {
        for (uint256 i = 0; i < _tokenAddresses.length; i++) {
            IKAP20 _feeToken = IKAP20(_tokenAddresses[i]);
            require(
                _feeToken.transfer(owner, _feeToken.balanceOf(address(this))),
                "KalamangFeeStorage : Withdraw fee failed"
            );
        }
    }

    function setOwner(address _owner) external onlyOwner {
        owner = _owner;
    }
}
