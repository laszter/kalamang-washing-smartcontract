// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

abstract contract Pauseable {
    event Paused(address account);

    event Unpaused(address account);

    bool public paused;

    constructor() {
        paused = false;
    }

    modifier whenNotPaused() {
        require(!paused, "Pauseable: paused");
        _;
    }

    modifier whenPaused() {
        require(paused, "Pauseable: not paused");
        _;
    }

    function _pause() internal virtual whenNotPaused {
        paused = true;
        emit Paused(msg.sender);
    }

    function _unpause() internal virtual whenPaused {
        paused = false;
        emit Unpaused(msg.sender);
    }
}
