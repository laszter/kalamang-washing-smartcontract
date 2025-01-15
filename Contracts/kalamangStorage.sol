// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./interfaces/IKAP20.sol";
import "./interfaces/IKYCBitkubChain.sol";
import "./interfaces/ISdkTransferRouter.sol";
import "./interfaces/IKalamangStorage.sol";
import "./interfaces/IKalamangFeeStorage.sol";

contract KalamangStorage is IKalamangStorage {
    modifier onlyOwner() {
        require(
            msg.sender == owner,
            "KalamangStorage : Only owner can call this function"
        );
        _;
    }

    modifier onlyKalamangController() {
        require(
            msg.sender == kalamangController,
            "KalamangStorage : Only kalamangController can call this function"
        );
        _;
    }

    modifier ownerOrKalamangController() {
        require(
            msg.sender == owner || msg.sender == kalamangController,
            "KalamangStorage : Only owner or kalamangController can call this function"
        );
        _;
    }

    modifier whenNotPaused() {
        require(!isPaused, "KalamangStorage : Contract is paused");
        _;
    }

    address public owner;
    address public kalamangController;
    uint256 public totalKalaMangs;
    IKYCBitkubChain public kycBitkubChain;
    ISdkTransferRouter public sdkTransferRouter;
    bool public isPaused;
    IKalamangFeeStorage public feeStorage;
    bool public isAllowAllTokens;

    mapping(string => uint256) private kalamangIds;
    mapping(uint256 => Kalamang) private kalamangs;
    mapping(string => bool) private kalamangsExists;
    mapping(address => uint256[]) private kalamangsOwner;
    mapping(uint256 => KalamangClaimedHistory[]) private claimedHistory;

    mapping(address => bool) allowTokenAddress;

    constructor(
        address _kalamangController,
        address _kalamangFeeStorage,
        address _kycBitkubChain,
        address _sdkTransferRouter
    ) {
        kalamangController = _kalamangController;
        feeStorage = IKalamangFeeStorage(_kalamangFeeStorage);
        kycBitkubChain = IKYCBitkubChain(_kycBitkubChain);
        sdkTransferRouter = ISdkTransferRouter(_sdkTransferRouter);
        owner = msg.sender;
        isPaused = false;
        isAllowAllTokens = false;
    }

    function createKalamang(
        KalamangConfig calldata _config
    ) external override whenNotPaused onlyKalamangController {
        require(
            allowTokenAddress[_config.tokenAddress] || isAllowAllTokens,
            "KalamangStorage : Token not allowed"
        );
        require(
            !kalamangsExists[_config.kalamangId],
            "KalamangStorage : Kalamang exists"
        );

        kalamangsExists[_config.kalamangId] = true;
        kalamangIds[_config.kalamangId] = totalKalaMangs;

        Kalamang storage newKalamang = kalamangs[totalKalaMangs];
        newKalamang.creator = _config.creator;
        newKalamang.kalamangId = _config.kalamangId;
        newKalamang.tokenAddress = _config.tokenAddress;
        newKalamang.totalTokens = _config.totalTokens;
        newKalamang.claimedTokens = 0;
        newKalamang.maxRecipients = _config.maxRecipients;
        newKalamang.claimedRecipients = 0;
        newKalamang.isactive = true;
        newKalamang.isRandom = _config.isRandom;
        newKalamang.minRandom = _config.minRandom;
        newKalamang.maxRandom = _config.maxRandom;
        newKalamang.acceptedKYCLevel = _config.acceptedKYCLevel;
        newKalamang.isRequireWhitelist = _config.isRequireWhitelist;
        newKalamang.whitelistArray = _config.whitelist;
        for (uint i = 0; i < _config.whitelist.length; i++) {
            newKalamang.whitelist[_config.whitelist[i]] = true;
        }

        kalamangsOwner[_config.creator].push(totalKalaMangs);

        totalKalaMangs++;

        if (_config.isSdkCallerHelper) {
            sdkTransferRouter.transferKAP20(
                _config.tokenAddress,
                address(this),
                _config.totalTokens,
                _config.creator
            );
        } else {
            IKAP20 _token = IKAP20(_config.tokenAddress);
            require(
                _token.transferFrom(
                    _config.creator,
                    address(this),
                    _config.totalTokens
                ),
                "KalamangStorage : Token transfer failed"
            );
        }
    }

    function claimToken(
        string calldata _kalamangId,
        uint256 _claimTokens,
        address _recipient
    ) external override onlyKalamangController returns (uint256) {
        Kalamang storage kalamang = kalamangs[kalamangIds[_kalamangId]];
        require(
            kalamang.creator != address(0),
            "KalamangStorage : Kalamang does not exist"
        );
        require(kalamang.isactive, "KalamangStorage : Kalamang is not active");
        require(
            !kalamang.hasClaimed[_recipient],
            "KalamangStorage : Already claimed"
        );
        require(
            !kalamang.isRequireWhitelist || kalamang.whitelist[_recipient],
            "KalamangStorage : Address is not in whitelist"
        );
        require(
            kycBitkubChain.kycsLevel(_recipient) >= kalamang.acceptedKYCLevel,
            "KalamangStorage : KYC level is not accepted"
        );
        require(
            kalamang.claimedRecipients < kalamang.maxRecipients,
            "KalamangStorage : All tokens have been claimed"
        );

        IKAP20 _token = IKAP20(kalamang.tokenAddress);

        kalamang.hasClaimed[_recipient] = true;
        kalamang.claimedRecipients++;
        kalamang.claimedTokens += _claimTokens;

        uint256 _fee = feeStorage.getFee();

        if (_fee > 0) {
            uint256 feeAmount = (_claimTokens * _fee) / 10000;
            require(
                _token.transfer(address(feeStorage), feeAmount),
                "KalamangStorage : Transfer fee failed"
            );
            _claimTokens -= feeAmount;
        }

        claimedHistory[kalamangIds[_kalamangId]].push(
            KalamangClaimedHistory({
                claimedAddress: _recipient,
                claimedAmount: _claimTokens
            })
        );

        require(
            _token.transfer(_recipient, _claimTokens),
            "KalamangStorage : Transfer failed"
        );

        return _claimTokens;
    }

    function abortKalamang(
        string calldata _kalamangId,
        address _creator
    ) external override ownerOrKalamangController returns (uint256) {
        Kalamang storage kalamang = kalamangs[kalamangIds[_kalamangId]];
        require(
            kalamang.creator != address(0),
            "KalamangStorage : Kalamang does not exist"
        );
        require(
            kalamang.creator == _creator,
            "KalamangStorage : Invalid creator"
        );
        require(kalamang.isactive == true, "KalamangStorage : Already aborted");

        IKAP20 _token = IKAP20(kalamang.tokenAddress);

        uint256 _amount = kalamang.totalTokens - kalamang.claimedTokens;

        require(
            _token.transfer(kalamang.creator, _amount),
            "Token transfer failed"
        );

        kalamang.isactive = false;

        return _amount;
    }

    function abortAllKalamang() external onlyOwner {
        for (uint256 i = 0; i < totalKalaMangs; i++) {
            Kalamang storage kalamang = kalamangs[i];

            if (
                !kalamang.isactive ||
                kalamang.maxRecipients == kalamang.claimedRecipients
            ) {
                continue;
            }

            IKAP20 _token = IKAP20(kalamang.tokenAddress);

            uint256 _amount = kalamang.totalTokens - kalamang.claimedTokens;

            require(
                _token.transfer(kalamang.creator, _amount),
                "KalamangStorage : Token transfer failed"
            );

            kalamang.isactive = false;
        }
    }

    function getKalamangInfo(
        string calldata _kalamangId
    ) public view virtual returns (KalamangInfo memory) {
        uint256 _id = kalamangIds[_kalamangId];
        Kalamang storage kalamang = kalamangs[_id];
        require(
            kalamang.creator != address(0),
            "KalamangStorage : Kalamang does not exist"
        );

        IKAP20 _token = IKAP20(kalamang.tokenAddress);

        KalamangInfo memory info;
        info.creator = kalamang.creator;
        info.kalamangId = kalamang.kalamangId;
        info.tokenAddress = kalamang.tokenAddress;
        info.tokenSymbol = _token.symbol();
        info.maxRecipients = kalamang.maxRecipients;
        info.totalTokens = kalamang.totalTokens;
        info.claimedRecipients = kalamang.claimedRecipients;
        info.isactive = kalamang.isactive;
        info.isRandom = kalamang.isRandom;
        info.minRandom = kalamang.minRandom;
        info.maxRandom = kalamang.maxRandom;
        info.isRequireWhitelist = kalamang.isRequireWhitelist;
        info.acceptedKYCLevel = kalamang.acceptedKYCLevel;
        info.remainingAmounts = kalamang.totalTokens - kalamang.claimedTokens;

        return info;
    }

    function getKalamangsByPage(
        address _kalamangOwnerAddress,
        uint256 _page,
        uint256 _pageLength
    ) public view virtual returns (string[] memory) {
        uint256 _totalMyKalamang = kalamangsOwner[_kalamangOwnerAddress].length;

        // Calculate start and end index for pagination
        if (
            _totalMyKalamang == 0 ||
            ((_page - 1) * _pageLength) >= _totalMyKalamang
        ) {
            return new string[](0); // Return an empty array if out of bounds
        }

        uint256 _start = _totalMyKalamang - ((_page - 1) * _pageLength);
        if (_start < 0) {
            _start = _totalMyKalamang - 1;
        }

        uint256 _end = _start > _pageLength ? _start - _pageLength : 0;
        uint256 _resultLength = _start - _end;

        string[] memory _myKalamangIds = new string[](_resultLength);
        uint256 _index = 0;

        for (uint256 i = _start; i > _end; i--) {
            _myKalamangIds[_index++] = kalamangs[
                kalamangsOwner[_kalamangOwnerAddress][i - 1]
            ].kalamangId; // Access element before decrementing
        }

        return _myKalamangIds;
    }

    function getAllMyKalamangs() public view returns (string[] memory) {
        uint256 _totalMyKalamang = kalamangsOwner[msg.sender].length;
        string[] memory _myKalamangIds = new string[](_totalMyKalamang);
        uint256 _index = 0;

        for (uint256 i = _totalMyKalamang; i > 0; i--) {
            _myKalamangIds[_index++] = kalamangs[
                kalamangsOwner[msg.sender][i - 1]
            ].kalamangId; // Access element before decrementing
        }

        return _myKalamangIds;
    }

    function getKalamangWhitelist(
        string calldata _kalamangId
    ) public view virtual returns (address[] memory) {
        Kalamang storage kalamang = kalamangs[kalamangIds[_kalamangId]];
        if (kalamang.creator == address(0)) {
            return new address[](0);
        }

        return kalamang.whitelistArray;
    }

    function isInWhitelist(
        string calldata _kalamangId,
        address _target
    ) public view virtual returns (bool) {
        Kalamang storage kalamang = kalamangs[kalamangIds[_kalamangId]];
        return kalamang.creator != address(0) && kalamang.whitelist[_target];
    }

    function isClaimed(
        string calldata _kalamangId,
        address _target
    ) public view virtual returns (bool) {
        Kalamang storage kalamang = kalamangs[kalamangIds[_kalamangId]];
        return kalamang.creator != address(0) && kalamang.hasClaimed[_target];
    }

    function getKalamangClaimedHistory(
        string calldata _kalamangId
    ) public view virtual returns (KalamangClaimedHistory[] memory) {
        return claimedHistory[kalamangIds[_kalamangId]];
    }

    function updateWhitelist(
        string calldata _kalamangId,
        bool _isRequireWhitelist,
        address[] calldata _whitelist,
        address _creator
    ) external override onlyKalamangController {
        Kalamang storage kalamang = kalamangs[kalamangIds[_kalamangId]];
        require(
            kalamang.creator == _creator,
            "KalamangStorage : Invalid creator"
        );
        require(kalamang.isactive, "KalamangStorage : Kalamang is not active");

        kalamang.isRequireWhitelist = _isRequireWhitelist;

        for (uint i = 0; i < kalamang.whitelistArray.length; i++) {
            kalamang.whitelist[kalamang.whitelistArray[i]] = false;
        }

        kalamang.whitelistArray = _whitelist;

        for (uint i = 0; i < _whitelist.length; i++) {
            kalamang.whitelist[_whitelist[i]] = true;
        }
    }

    function addWhitelist(
        string calldata _kalamangId,
        address[] calldata _whitelist,
        address _creator
    ) external override onlyKalamangController {
        Kalamang storage kalamang = kalamangs[kalamangIds[_kalamangId]];
        require(
            kalamang.creator == _creator,
            "KalamangStorage : Invalid creator"
        );
        require(kalamang.isactive, "KalamangStorage : Kalamang is not active");

        for (uint i = 0; i < _whitelist.length; i++) {
            if (kalamang.whitelist[_whitelist[i]]) {
                continue;
            }

            kalamang.whitelist[_whitelist[i]] = true;
            kalamang.whitelistArray.push(_whitelist[i]);
        }
    }

    function removeWhitelist(
        string calldata _kalamangId,
        address[] calldata _whitelist,
        address _creator
    ) external override onlyKalamangController {
        Kalamang storage kalamang = kalamangs[kalamangIds[_kalamangId]];
        require(
            kalamang.creator == _creator,
            "KalamangStorage : Invalid creator"
        );
        require(kalamang.isactive, "KalamangStorage : Kalamang is not active");

        for (uint i = 0; i < _whitelist.length; i++) {
            if (!kalamang.whitelist[_whitelist[i]]) {
                continue;
            }

            kalamang.whitelist[_whitelist[i]] = false;

            for (uint j = 0; j < kalamang.whitelistArray.length; j++) {
                if (kalamang.whitelistArray[j] == _whitelist[i]) {
                    kalamang.whitelistArray[j] = kalamang.whitelistArray[
                        kalamang.whitelistArray.length - 1
                    ];
                    kalamang.whitelistArray.pop();
                    break;
                }
            }
        }
    }

    function setPause(bool _isPaused) external onlyOwner {
        isPaused = _isPaused;
    }

    function setKalamangController(
        address _kalamangController
    ) external onlyOwner {
        kalamangController = _kalamangController;
    }

    function setKycBitkubChain(address _kycBitkubChain) external onlyOwner {
        kycBitkubChain = IKYCBitkubChain(_kycBitkubChain);
    }

    function setSdkTransferRouter(
        address _sdkTransferRouter
    ) external onlyOwner {
        sdkTransferRouter = ISdkTransferRouter(_sdkTransferRouter);
    }

    function setFeeStorage(address _feeStorage) external onlyOwner {
        feeStorage = IKalamangFeeStorage(_feeStorage);
    }

    function setOwner(address _owner) external onlyOwner {
        owner = _owner;
    }

    function setAllowTokenAddress(
        address _tokenAddress,
        bool _allow
    ) external onlyOwner {
        allowTokenAddress[_tokenAddress] = _allow;
    }

    function setIsAllowAllTokens(bool _allow) external onlyOwner {
        isAllowAllTokens = _allow;
    }
}
