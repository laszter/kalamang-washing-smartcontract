// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../Contracts/kalamangV2.sol";
import "../Contracts/kalamangStorageV2.sol";

contract MockKYC {
    function kycsLevel(address) external pure returns (uint256) {
        return 4;
    }
}

contract MockToken {
    string public name = "Mock";
    string public symbol = "MOCK";
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract Recipient {
    function claim(
        KalamangV2 _controller,
        string memory _id
    ) external {
        _controller.claimToken(_id);
    }
}

contract Creator {
    function create(
        KalamangV2 _controller,
        KalamangStorageV2 _store,
        MockToken _token,
        uint256 _totalTokens,
        uint256 _maxRecipients
    ) external returns (string memory) {
        _token.mint(address(this), _totalTokens);
        _token.approve(address(_store), _totalTokens);

        address[] memory emptyWhitelist;
        _controller.createKalamang(
            address(_token),
            _totalTokens,
            _maxRecipients,
            false,
            0,
            0,
            0,
            false,
            emptyWhitelist,
            true,
            false // requireVoucher (Recipient.claim uses the direct path)
        );

        string[] memory ids = _store.getAllMyKalamangs();
        return ids[0];
    }
}

contract NonOwner {
    function trySetFee(
        KalamangStorageV2 _store,
        string memory _id,
        uint256 _fee
    ) external {
        _store.setKalamangFee(_id, _fee);
    }
}
