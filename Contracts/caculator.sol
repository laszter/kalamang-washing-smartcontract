// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Calculator {
    address public owner;
    address public sdkCallHelperRouter;
    uint256 publicValue;
    mapping(address => uint256) privateValue;

    constructor(address _sdkCallHelperRouter) {
        owner = msg.sender;
        sdkCallHelperRouter = _sdkCallHelperRouter;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    modifier onlySdkCallHelperRouter() {
        require(msg.sender == sdkCallHelperRouter, "Only sdkCallHelperRouter can call this function");
        _;
    }

    event AddPrivateValue(address indexed _from, uint256 _value);

    function setOwner(address _owner) public onlyOwner {
        owner = _owner;
    }

    function setSdkCallHelperRouter(address _sdkCallHelperRouter) public onlyOwner {
        sdkCallHelperRouter = _sdkCallHelperRouter;
    }

    function addPublicValue(uint256 _value) external {
        publicValue += _value;
    }

    function subPublicValue(uint256 _value) external {
        publicValue -= _value;
    }

    function getPublicValue() external view returns (uint256) {
        return publicValue;
    }

    function addPrivateValue(uint256 _value) external {
        privateValue[msg.sender] += _value;
        emit AddPrivateValue(msg.sender, _value);
    }

    function subPrivateValue(uint256 _value) external {
        privateValue[msg.sender] -= _value;
    }

    function getMyValue() external view returns (uint256) {
        return privateValue[msg.sender];
    }

    function addPrivateValueBySdk(uint256 _value, address _bitkubNext) external onlySdkCallHelperRouter {
        privateValue[_bitkubNext] += _value;
        emit AddPrivateValue(_bitkubNext, _value);
    }

    function subPrivateValueBySdk(uint256 _value, address _bitkubNext) external onlySdkCallHelperRouter {
        privateValue[_bitkubNext] -= _value;
    }

    function getMyValueBySdk(address _bitkubNext) external onlySdkCallHelperRouter view returns (uint256) {
        return privateValue[_bitkubNext];
    }

    function getTargetValue(address _bitkubNext) external view returns (uint256) {
        return privateValue[_bitkubNext];
    }
}