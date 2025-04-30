// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract TheOasis {
    string public name = "The Oasis";
    string public version = "1.0.0";
    address public owner;
    mapping(address => uint256) public lastCalled;
    uint256 public waitingTime;

    constructor() {
        owner = msg.sender;
        waitingTime = 14 days;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not the contract owner");
        _;
    }

    function setOwner(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid address");
        owner = newOwner;
    }

    function fillWater() external payable {
        require(msg.value > 0, "You need to send some water");
    }

    function sendDrinkWater(address recipient) external {
        require(recipient != address(0), "Invalid recipient address");
        require(
            block.timestamp >= lastCalled[recipient] + waitingTime,
            "I know you are thirsty, but please wait a bit longer"
        );

        (bool success, ) = recipient.call{value: 0.01 ether}("");
        require(success, "Failed to send drink water");

        lastCalled[recipient] = block.timestamp;
    }

    function nextAvailableCallTime(
        address user
    ) external view returns (uint256) {
        uint256 lastTime = lastCalled[user];
        if (lastTime == 0) {
            return 0;
        }

        return lastTime + waitingTime;
    }

    function setWaitingTime(uint256 _newWaitingTime) external onlyOwner {
        require(_newWaitingTime > 0, "Time must be greater than 0");
        waitingTime = _newWaitingTime;
    }
}
