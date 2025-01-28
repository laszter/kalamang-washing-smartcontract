// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

abstract contract Committee {
    address public committee;

    event SetCommittee(
        address indexed oldCommittee,
        address indexed newCommittee,
        address indexed caller
    );

    modifier onlyCommittee() {
        require(msg.sender == committee, "Restricted only committee");
        _;
    }

    function setCommittee(address _committee) external onlyCommittee {
        emit SetCommittee(committee, _committee, msg.sender);
        committee = _committee;
    }
}
