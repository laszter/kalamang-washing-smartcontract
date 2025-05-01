// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract TheOasis {
    string public name = "The Oasis";
    string public version = "1.0.0";
    address public owner;
    mapping(address => uint256) public lastDrinkTime;
    uint256 public waitingTime;
    uint256 public waterAmount;

    event OwnerChanged(address indexed newOwner);
    event WaitingTimeUpdated(uint256 newTime);
    event WaterAmountUpdated(uint256 newAmount);

    constructor() {
        owner = msg.sender;
        waitingTime = 14 days;
        waterAmount = 0.01 ether;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not the contract owner");
        _;
    }

    receive() external payable {
        require(msg.value > 0, "You need to send some water");
    }

    function fillWater() external payable {
        require(msg.value > 0, "You need to send some water");
    }

    function sendDrinkWater(address recipient) external {
        require(recipient != address(0), "Invalid recipient address");
        require(
            block.timestamp >= lastDrinkTime[recipient] + waitingTime,
            "I know you are thirsty, but please wait a bit longer"
        );

        uint256 balance = address(this).balance;
        uint256 sendAmount = waterAmount > balance ? balance : waterAmount;
        require(sendAmount > 0, "No water available to send");

        lastDrinkTime[recipient] = block.timestamp;

        (bool success, ) = recipient.call{value: sendAmount}("");
        require(success, "Failed to send drink water");
    }

    function nextAvailableCallTime(
        address recipient
    ) external view returns (uint256) {
        uint256 lastTime = lastDrinkTime[recipient];
        if (lastTime == 0) {
            return 0;
        }

        return lastTime + waitingTime;
    }

    function setOwner(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid address");
        owner = newOwner;
        emit OwnerChanged(newOwner);
    }

    function setWaitingTime(uint256 _newWaitingTime) external onlyOwner {
        require(_newWaitingTime > 0, "Time must be greater than 0");
        waitingTime = _newWaitingTime;
        emit WaitingTimeUpdated(_newWaitingTime);
    }

    function setWaterAmount(uint256 _newWaterAmount) external onlyOwner {
        require(_newWaterAmount > 0, "Amount must be greater than 0");
        waterAmount = _newWaterAmount;
        emit WaterAmountUpdated(_newWaterAmount);
    }
}
