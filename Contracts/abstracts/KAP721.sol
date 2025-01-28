// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../interfaces/IKAP721.sol";
import "../interfaces/IKAP721Metadata.sol";
import "../interfaces/IKAP721Enumerable.sol";
import "../interfaces/IKAP721Receiver.sol";
import "./KAP165.sol";
import "./Authorization.sol";
import "./Committee.sol";
import "./KYCHandler.sol";
import "./Pauseable.sol";

import "../libraries/Address.sol";
import "../libraries/Strings.sol";
import "../libraries/EnumerableSetUint.sol";
import "../libraries/EnumerableMap.sol";

abstract contract KAP721 is
    IKAP721,
    IKAP721Metadata,
    IKAP721Enumerable,
    KAP165,
    Authorization,
    Committee,
    KYCHandler,
    Pauseable
{
    using Address for address;
    using Strings for uint256;
    using EnumerableSetUint for EnumerableSetUint.UintSet;
    using EnumerableMap for EnumerableMap.UintToAddressMap;

    // Token name
    string public override name;

    // Token symbol
    string public override symbol;

    // Base URI
    string public baseURI;

    // Base KAP URI
    string public baseKapURI;

    // Mapping from token ID to approved address
    mapping(uint256 => address) private _tokenApprovals;

    // Mapping from owner to operator approvals
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    // Mapping for token URIs
    mapping(uint256 => string) private _tokenURIs;

    // Mapping for kap URIs
    mapping(uint256 => string) private _kapURIs;

    // Mapping from holder address to their (enumerable) set of owned tokens
    mapping(address => EnumerableSetUint.UintSet) _holderTokens;

    // Enumerable mapping from token ids to their owners
    EnumerableMap.UintToAddressMap private _tokenOwners;

    constructor(
        string memory name_,
        string memory symbol_,
        string memory project_,
        address adminRouter_,
        address kyc_,
        address committee_,
        uint256 acceptedKycLevel_
    ) Authorization(project_) {
        name = name_;
        symbol = symbol_;
        adminRouter = IAdminProjectRouter(adminRouter_);
        kyc = IKYCBitkubChain(kyc_);
        committee = committee_;
        acceptedKycLevel = acceptedKycLevel_;
    }

    function activateOnlyKycAddress() public onlyCommittee {
        _activateOnlyKycAddress();
    }

    function setKYC(IKYCBitkubChain _kyc) public onlyCommittee {
        _setKYC(_kyc);
    }

    function setAcceptedKycLevel(uint256 _kycLevel) public onlyCommittee {
        _setAcceptedKycLevel(_kycLevel);
    }

    function pause() public onlyCommittee {
        _pause();
    }

    function unpause() public onlyCommittee {
        _unpause();
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(KAP165, IKAP165) returns (bool) {
        return
            interfaceId == type(IKAP721).interfaceId ||
            interfaceId == type(IKAP721Metadata).interfaceId ||
            interfaceId == type(IKAP721Enumerable).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    function balanceOf(
        address owner
    ) public view virtual override returns (uint256) {
        return _holderTokens[owner].length();
    }

    function ownerOf(
        uint256 tokenId
    ) public view virtual override returns (address) {
        return
            _tokenOwners.get(
                tokenId,
                "KAP721: owner query for nonexistent token"
            );
    }

    function tokenURI(
        uint256 tokenId
    ) public view virtual override returns (string memory) {
        require(_exists(tokenId), "KAP721: URI query for nonexistent token");

        string memory _tokenURI = _tokenURIs[tokenId];

        // If there is no base URI, return the token URI.
        if (bytes(baseURI).length == 0) {
            return _tokenURI;
        }
        // If both are set, concatenate the baseURI and tokenURI (via abi.encodePacked).
        if (bytes(_tokenURI).length > 0) {
            return string(abi.encodePacked(baseURI, _tokenURI));
        }

        // If there is a baseURI but no tokenURI, concatenate the tokenID to the baseURI.
        return string(abi.encodePacked(baseURI, tokenId.toString()));
    }

    function kapURI(
        uint256 tokenId
    ) public view virtual override returns (string memory) {
        require(_exists(tokenId), "KAP721: URI query for nonexistent token");

        string memory _kapURI = _kapURIs[tokenId];

        // If there is no base KAP URI, return the kapURI.
        if (bytes(baseKapURI).length == 0) {
            return _kapURI;
        }
        // If both are set, concatenate the base KAP URI and kapURI (via abi.encodePacked).
        if (bytes(_kapURI).length > 0) {
            return string(abi.encodePacked(baseKapURI, _kapURI));
        }

        // If there is a base KAP URI but no kapURI, concatenate the tokenID to the base KAP URI.
        return string(abi.encodePacked(baseKapURI, tokenId.toString()));
    }

    function totalSupply() public view virtual override returns (uint256) {
        // _tokenOwners are indexed by tokenIds, so .length() returns the number of tokenIds
        return _tokenOwners.length();
    }

    function tokenOfOwnerByIndex(
        address owner,
        uint256 index
    ) public view virtual override returns (uint256) {
        return _holderTokens[owner].at(index);
    }

    function tokenByIndex(
        uint256 index
    ) public view virtual override returns (uint256) {
        (uint256 tokenId, ) = _tokenOwners.at(index);
        return tokenId;
    }

    function approve(address to, uint256 tokenId) public virtual override {
        address owner = KAP721.ownerOf(tokenId);
        require(to != owner, "KAP721: approval to current owner");

        require(
            msg.sender == owner || isApprovedForAll(owner, msg.sender),
            "KAP721: approve caller is not owner nor approved for all"
        );

        _approve(to, tokenId);
    }

    function getApproved(
        uint256 tokenId
    ) public view virtual override returns (address) {
        require(
            _exists(tokenId),
            "KAP721: approved query for nonexistent token"
        );

        return _tokenApprovals[tokenId];
    }

    function setApprovalForAll(
        address operator,
        bool approved
    ) public virtual override {
        require(operator != msg.sender, "KAP721: approve to caller");

        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function isApprovedForAll(
        address owner,
        address operator
    ) public view virtual override returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual override {
        require(
            _isApprovedOrOwner(msg.sender, tokenId),
            "KAP721: transfer caller is not owner nor approved"
        );

        _transfer(from, to, tokenId);
    }

    function adminTransfer(
        address from,
        address to,
        uint256 tokenId
    ) external override onlyCommittee {
        _transfer(from, to, tokenId);
    }

    function internalTransfer(
        address sender,
        address recipient,
        uint256 tokenId
    ) external override onlySuperAdminOrTransferRouter returns (bool) {
        require(
            kyc.kycsLevel(sender) >= acceptedKycLevel &&
                kyc.kycsLevel(recipient) >= acceptedKycLevel,
            "Only internal purpose"
        );

        _transfer(sender, recipient, tokenId);
        return true;
    }

    function externalTransfer(
        address sender,
        address recipient,
        uint256 tokenId
    ) external override onlySuperAdminOrTransferRouter returns (bool) {
        require(
            kyc.kycsLevel(sender) >= acceptedKycLevel,
            "Only external purpose"
        );

        _transfer(sender, recipient, tokenId);
        return true;
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual override {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) public virtual override {
        require(
            _isApprovedOrOwner(msg.sender, tokenId),
            "KAP721: transfer caller is not owner nor approved"
        );
        _safeTransfer(from, to, tokenId, _data);
    }

    function _safeTransfer(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) internal virtual {
        _transfer(from, to, tokenId);
        require(
            _checkOnKAP721Received(from, to, tokenId, _data),
            "KAP721: transfer to non KAP721Receiver implementer"
        );
    }

    function _exists(uint256 tokenId) internal view virtual returns (bool) {
        return _tokenOwners.contains(tokenId);
    }

    function _isApprovedOrOwner(
        address spender,
        uint256 tokenId
    ) internal view virtual returns (bool) {
        require(
            _exists(tokenId),
            "KAP721: operator query for nonexistent token"
        );
        address owner = KAP721.ownerOf(tokenId);
        return (spender == owner ||
            getApproved(tokenId) == spender ||
            isApprovedForAll(owner, spender));
    }

    function _safeMint(address to, uint256 tokenId) internal virtual {
        _safeMint(to, tokenId, "");
    }

    function _safeMint(
        address to,
        uint256 tokenId,
        bytes memory _data
    ) internal virtual {
        _mint(to, tokenId);
        require(
            _checkOnKAP721Received(address(0), to, tokenId, _data),
            "KAP721: transfer to non KAP721Receiver implementer"
        );
    }

    function _mint(address to, uint256 tokenId) internal virtual whenNotPaused {
        require(to != address(0), "KAP721: mint to the zero address");
        require(!_exists(tokenId), "KAP721: token already minted");

        _beforeTokenTransfer(address(0), to, tokenId);

        _holderTokens[to].add(tokenId);

        _tokenOwners.set(tokenId, to);

        emit Transfer(address(0), to, tokenId);
    }

    function _burn(uint256 tokenId) internal virtual whenNotPaused {
        address owner = ownerOf(tokenId); // internal owner

        _beforeTokenTransfer(owner, address(0), tokenId);

        // Clear approvals
        _approve(address(0), tokenId);

        _holderTokens[owner].remove(tokenId);
        _holderTokens[address(0)].add(tokenId);

        _tokenOwners.set(tokenId, address(0));

        emit Transfer(owner, address(0), tokenId);
    }

    function _transfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual whenNotPaused {
        require(
            ownerOf(tokenId) == from,
            "KAP721: transfer of token that is not own"
        ); // internal owner
        require(to != address(0), "KAP721: transfer to the zero address");

        _beforeTokenTransfer(from, to, tokenId);

        // Clear approvals from the previous owner
        _approve(address(0), tokenId);

        _holderTokens[from].remove(tokenId);
        _holderTokens[to].add(tokenId);

        _tokenOwners.set(tokenId, to);

        emit Transfer(from, to, tokenId);
    }

    function _approve(address to, uint256 tokenId) internal virtual {
        _tokenApprovals[tokenId] = to;
        emit Approval(KAP721.ownerOf(tokenId), to, tokenId);
    }

    function _setTokenURI(
        uint256 tokenId,
        string memory _tokenURI
    ) internal virtual {
        require(_exists(tokenId), "KAP721: URI set of nonexistent token");
        _tokenURIs[tokenId] = _tokenURI;
        emit Uri(tokenId);
    }

    function _setBaseURI(string memory baseURI_) internal virtual {
        baseURI = baseURI_;
    }

    function _setKapURI(
        uint256 tokenId,
        string memory _kapURI
    ) internal virtual {
        require(_exists(tokenId), "KAP721: URI set of nonexistent token");
        _kapURIs[tokenId] = _kapURI;
        emit Uri(tokenId);
    }

    function _setBaseKapURI(string memory baseKapURI_) internal virtual {
        baseKapURI = baseKapURI_;
    }

    function _checkOnKAP721Received(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) private returns (bool) {
        if (to.isContract()) {
            try
                IKAP721Receiver(to).onKAP721Received(
                    msg.sender,
                    from,
                    tokenId,
                    _data
                )
            returns (bytes4 retval) {
                return retval == IKAP721Receiver.onKAP721Received.selector;
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert(
                        "KAP721: transfer to non KAP721Receiver implementer"
                    );
                } else {
                    assembly {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        } else {
            return true;
        }
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual {}
}
