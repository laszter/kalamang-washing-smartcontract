// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces/IKAP20.sol";
import "./interfaces/IKYCBitkubChain.sol";
import "./interfaces/ISdkTransferRouter.sol";
import "./interfaces/IKalaMangWashingStorage.sol";

contract KalaMangWashingStorageTestV1 is IKalaMangWashingStorage {
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    modifier onlyKalaMangController() {
        require(
            msg.sender == kalamangController,
            "Only kalamangController can call this function"
        );
        _;
    }

    modifier ownerOrKalaMangController() {
        require(
            msg.sender == owner || msg.sender == kalamangController,
            "Only owner or kalamangController can call this function"
        );
        _;
    }

    modifier whenNotPaused() {
        require(!isPaused, "Contract is paused");
        _;
    }

    address public owner;
    address public kalamangController;
    uint256 public totalKalaMangs;
    IKAP20 public token;
    IKYCBitkubChain public kycBitkubChain;
    ISdkTransferRouter public sdkTransferRouter;
    bool public isPaused;
    string[] private kalamangIds;

    mapping(string => KalaMang) private kalamangs;
    mapping(string => bool) private kalamangsExists;
    mapping(address => uint256[]) private kalamangsOwner;
    mapping(string => KalaMangClaimedHistory[]) private claimedHistory;

    constructor(
        address _kalamangController,
        address _kycBitkubChain,
        address _sdkTransferRouter,
        address _token
    ) {
        kalamangController = _kalamangController;
        token = IKAP20(_token);
        kycBitkubChain = IKYCBitkubChain(_kycBitkubChain);
        sdkTransferRouter = ISdkTransferRouter(_sdkTransferRouter);
        owner = msg.sender;
        isPaused = false;
    }

    function createKalamang(
        KalaMangConfig calldata _config
    ) external override onlyKalaMangController {
        require(_config.creator != address(0), "Creator address is required");
        require(!kalamangsExists[_config.kalamangId], "Kalamang exists");
        require(_config.totalTokens > 0, "Total tokens is required");
        require(_config.maxRecipients > 0, "Max recipients is required");
        require(
            _config.remainingAmounts.length > 0,
            "Remaining amounts is required"
        );

        KalaMang storage newKalamang = kalamangs[_config.kalamangId];
        newKalamang.creator = _config.creator;
        newKalamang.totalTokens = _config.totalTokens;
        newKalamang.maxRecipients = _config.maxRecipients;
        newKalamang.claimedRecipients = 0;
        newKalamang.isactive = true;
        newKalamang.isRandom = _config.isRandom;
        newKalamang.remainingAmounts = _config.remainingAmounts;
        newKalamang.acceptedKYCLevel = _config.acceptedKYCLevel;
        newKalamang.isRequireWhitelist = _config.isRequireWhitelist;
        for (uint i = 0; i < _config.whitelist.length; i++) {
            newKalamang.whitelist[_config.whitelist[i]] = true;
        }

        totalKalaMangs++;

        kalamangsExists[_config.kalamangId] = true;
        kalamangIds.push(_config.kalamangId);

        kalamangsOwner[_config.creator].push(kalamangIds.length - 1);

        if (_config.isSdkCallerHelper) {
            sdkTransferRouter.transferKAP20(
                address(token),
                address(this),
                _config.totalTokens,
                _config.creator
            );
        } else {
            require(
                token.transferFrom(
                    _config.creator,
                    address(this),
                    _config.totalTokens
                ),
                "Token transfer failed"
            );
        }
    }

    function claimToken(
        string calldata _kalamangId,
        uint256 _claimIndex,
        address _recipient
    ) external override onlyKalaMangController returns (uint256) {
        KalaMang storage kalamang = kalamangs[_kalamangId];
        require(kalamang.creator != address(0), "Kalamang does not exist");
        require(kalamang.isactive, "Kalamang is not active");
        require(!kalamang.hasClaimed[_recipient], "Already claimed");
        require(
            kalamang.whitelist[_recipient] || !kalamang.isRequireWhitelist,
            "Address is not in whitelist"
        );
        require(
            _claimIndex < kalamang.remainingAmounts.length,
            "Invalid claim index"
        );
        require(
            kycBitkubChain.isAddressKyc(_recipient) &&
                kycBitkubChain.kycsLevel(_recipient) >=
                kalamang.acceptedKYCLevel,
            "KYC level is not accepted"
        );
        require(
            !kalamang.isRequireWhitelist || kalamang.whitelist[_recipient],
            "Address is not in whitelist"
        );

        uint256 amount = kalamang.remainingAmounts[_claimIndex];

        kalamang.hasClaimed[_recipient] = true;
        kalamang.claimedRecipients++;

        uint256 lastIndex = kalamang.remainingAmounts.length - 1;
        if (_claimIndex != lastIndex) {
            kalamang.remainingAmounts[_claimIndex] = kalamang.remainingAmounts[
                lastIndex
            ];
        }
        kalamang.remainingAmounts.pop();

        claimedHistory[_kalamangId].push(
            KalaMangClaimedHistory({
                claimedAddress: _recipient,
                claimedAmount: amount
            })
        );

        require(token.transfer(_recipient, amount), "Transfer failed");

        return amount;
    }

    function abortKalamang(
        string calldata _kalamangId,
        address _creator
    ) external override ownerOrKalaMangController returns (uint256) {
        KalaMang storage kalamang = kalamangs[_kalamangId];
        require(kalamang.creator != address(0), "Kalamang does not exist");
        require(kalamang.creator == _creator, "Invalid creator");
        require(kalamang.isactive == true, "Already aborted");

        uint256 amount = 0;
        for (uint256 i = 0; i < kalamang.remainingAmounts.length; i++) {
            amount += kalamang.remainingAmounts[i];
        }

        require(
            token.transfer(kalamang.creator, amount),
            "Token transfer failed"
        );

        kalamang.isactive = false;

        return amount;
    }

    function abortAllKalamang() external onlyOwner {
        for (uint256 i = 0; i < kalamangIds.length; i++) {
            KalaMang storage kalamang = kalamangs[kalamangIds[i]];

            if (!kalamang.isactive) {
                continue;
            }

            uint256 amount = 0;
            for (uint256 j = 0; j < kalamang.remainingAmounts.length; j++) {
                amount += kalamang.remainingAmounts[j];
            }

            require(
                token.transfer(kalamang.creator, amount),
                "Token transfer failed"
            );

            kalamang.isactive = false;
        }
    }

    function getKalamangInfo(
        string calldata kalamangId
    ) public view virtual returns (KalaMangInfo memory) {
        KalaMang storage kalamang = kalamangs[kalamangId];
        require(kalamang.creator != address(0), "Kalamang does not exist");

        KalaMangInfo memory info;
        info.creator = kalamang.creator;
        info.kalamangId = kalamangId;
        info.maxRecipients = kalamang.maxRecipients;
        info.totalTokens = kalamang.totalTokens;
        info.claimedRecipients = kalamang.claimedRecipients;
        info.isactive = kalamang.isactive;
        info.remainingAmounts = 0;

        for (uint256 i = 0; i < kalamang.remainingAmounts.length; i++) {
            info.remainingAmounts += kalamang.remainingAmounts[i];
        }

        return info;
    }

    function getMyKalamangs(
        address _kalamangOwnerAddress,
        uint256 _page,
        uint256 _pageLength
    ) public view virtual returns (string[] memory) {
        uint256[] storage kalamangIdIndexes = kalamangsOwner[
            _kalamangOwnerAddress
        ];
        uint256 length = kalamangIdIndexes.length;

        // Calculate start and end index for pagination
        if (length == 0 || _page * _pageLength >= length) {
            return new string[](0); // Return an empty array if out of bounds
        }

        uint256 start = length - (_page * _pageLength);
        uint256 end = start >= _pageLength ? start - _pageLength : 0;
        uint256 resultLength = start - end;

        string[] memory myKalamangIds = new string[](resultLength);
        uint256 index = 0;

        for (uint256 i = start - 1; i >= end; i--) {
            myKalamangIds[index] = kalamangIds[kalamangIdIndexes[i]];
            index++;
            if (i == 0) break; // Break the loop when `i` reaches 0 to avoid underflow
        }

        return myKalamangIds;
    }

    function isClaimed(
        string calldata kalamangId,
        address _target
    ) public view virtual returns (bool) {
        KalaMang storage kalamang = kalamangs[kalamangId];
        return kalamang.creator != address(0) && kalamang.hasClaimed[_target];
    }

    function getKalamangClaimedHistory(
        string calldata _kalamangId
    ) public view virtual returns (KalaMangClaimedHistory[] memory) {
        KalaMang storage kalamang = kalamangs[_kalamangId];
        require(kalamang.creator != address(0), "Kalamang does not exist");

        return claimedHistory[_kalamangId];
    }

    function getKalamangRemainingRecipients(
        string calldata _kalamangId
    ) public view virtual override returns (uint256) {
        KalaMang storage kalamang = kalamangs[_kalamangId];
        require(kalamang.creator != address(0), "Kalamang does not exist");

        return kalamang.maxRecipients - kalamang.claimedRecipients;
    }

    function addKalamangWhiteList(
        string calldata _kalamangId,
        address[] calldata _whitelist
    ) external override onlyKalaMangController {
        KalaMang storage kalamang = kalamangs[_kalamangId];
        require(kalamang.creator != address(0), "Kalamang does not exist");

        for (uint i = 0; i < _whitelist.length; i++) {
            kalamang.whitelist[_whitelist[i]] = true;
        }
    }

    function removeKalamangWhiteList(
        string calldata _kalamangId,
        address[] calldata _whitelist
    ) external override onlyKalaMangController {
        KalaMang storage kalamang = kalamangs[_kalamangId];
        require(kalamang.creator != address(0), "Kalamang does not exist");

        for (uint i = 0; i < _whitelist.length; i++) {
            kalamang.whitelist[_whitelist[i]] = false;
        }
    }

    function setPause(bool _isPaused) external onlyOwner {
        isPaused = _isPaused;
    }

    function setKalaMangController(
        address _kalaMangController
    ) external onlyOwner {
        kalamangController = _kalaMangController;
    }

    function setSdkTransferRouter(
        address _sdkTransferRouter
    ) external onlyOwner {
        sdkTransferRouter = ISdkTransferRouter(_sdkTransferRouter);
    }
}
