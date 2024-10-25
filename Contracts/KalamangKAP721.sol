// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "./abstracts/KAP721.sol";

contract KalamangWashing is KAP721 {
    using EnumerableSetUint for EnumerableSetUint.UintSet;

    constructor(
        address transferRouter_,
        address adminRouter_,
        address kyc_,
        address committee_,
        uint256 acceptedKycLevel_
    )
        KAP721(
            "KalamangWashing",
            "KMW",
            "KalamangWashing",
            adminRouter_,
            kyc_,
            committee_,
            acceptedKycLevel_
        )
    {
        _setBaseURI("");
        transferRouter = transferRouter_;
    }

    event MintWithMetadata(
        address indexed operator,
        string _tokenURI,
        uint256 _tokenId
    );

    ///////////////////////////////////////////////////////////////////////////////////////

    function exists(uint256 _tokenId) external view returns (bool) {
        return _exists(_tokenId);
    }

    function tokenOfOwnerByPage(
        address _owner,
        uint256 _page,
        uint256 _limit
    ) external view returns (uint256[] memory) {
        return _holderTokens[_owner].get(_page, _limit);
    }

    function tokenOfOwnerAll(
        address _owner
    ) external view returns (uint256[] memory) {
        return _holderTokens[_owner].getAll();
    }

    ///////////////////////////////////////////////////////////////////////////////////////

    function setTokenURI(uint256 _tokenId, string calldata _tokenURI) external {
        _setTokenURI(_tokenId, _tokenURI);
    }

    function setBaseURI(string calldata _baseURI) external {
        _setBaseURI(_baseURI);
    }

    ///////////////////////////////////////////////////////////////////////////////////////

    function mint(address _to, uint256 _tokenId) external {
        _mint(_to, _tokenId);
    }

    function mintWithMetadata(
        address _to,
        string memory _tokenURI,
        uint256 _tokenId
    ) external {
        _mintWithMetadata(_to, _tokenURI, _tokenId);

        emit MintWithMetadata(_to, _tokenURI, _tokenId);
    }

    ///////////////////////////////////////////////////////////////////////////////////////

    function _mintWithMetadata(
        address _to,
        string memory _tokenURI,
        uint256 _tokenId
    ) internal {
        _mint(_to, _tokenId);
        _setTokenURI(_tokenId, _tokenURI);
    }
}
