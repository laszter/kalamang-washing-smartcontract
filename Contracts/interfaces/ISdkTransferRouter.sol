// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ISdkTransferRouter {
    event KTokenAddrAdded(address indexed kTokenAddr);

    event KTokenAddrRemoved(address indexed kTokenAddr);

    event ApprovalKAP20(
        address indexed tokenAddr,
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    event ApprovalNFT(
        address indexed tokenAddr,
        address indexed owner,
        address indexed spender,
        bool approved
    );

    event TransferKAP20(
        address indexed tokenAddr,
        address indexed sender,
        address indexed recipient,
        uint256 amount
    );
    event TransferKAP721(
        address indexed tokenAddr,
        address indexed sender,
        address indexed recipient,
        uint256 tokenId
    );
    event TransferKAP1155(
        address indexed tokenAddr,
        address indexed sender,
        address indexed recipient,
        uint256 id,
        uint256 amount
    );

    function transferKAP20(
        address _tokenAddr,
        address _recipient,
        uint256 _amount,
        address _bitkubNext
    ) external;

    function transferKAP20(
        address _callerAddr,
        address _tokenAddr,
        address _recipient,
        uint256 _amount,
        address _bitkubNext
    ) external;

    function transferKAP721(
        address _tokenAddr,
        address _recipient,
        uint256 _tokenId,
        address _bitkubNext
    ) external;

    function transferKAP1155(
        address _tokenAddr,
        address _recipient,
        uint256 _id,
        uint256 _amount,
        address _bitkubNext
    ) external;
}
