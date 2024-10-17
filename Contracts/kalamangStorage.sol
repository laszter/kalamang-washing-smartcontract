// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./interfaces/IKAP20.sol";
import "./interfaces/IKYCBitkubChain.sol";
import "./interfaces/ISdkTransferRouter.sol";
import "./interfaces/IKalaMangWashingStorage.sol";
import "./interfaces/IKalamangFeeStorage.sol";

contract KalaMangWashingStorageTestV2 is IKalaMangWashingStorage {
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

    string public kalamangName;
    address public owner;
    address public kalamangController;
    uint256 public totalKalaMangs;
    IKAP20 public token;
    IKYCBitkubChain public kycBitkubChain;
    ISdkTransferRouter public sdkTransferRouter;
    bool public isPaused;
    string[] private kalamangIds;
    IKalamangFeeStorage public feeStorage;

    mapping(string => KalaMang) private kalamangs;
    mapping(string => bool) private kalamangsExists;
    mapping(address => uint256[]) private kalamangsOwner;
    mapping(string => KalaMangClaimedHistory[]) private claimedHistory;

    constructor(
        string memory _kalamangName,
        address _kalamangController,
        address _kalamangFeeStorage,
        address _kycBitkubChain,
        address _sdkTransferRouter,
        address _token
    ) {
        kalamangName = _kalamangName;
        kalamangController = _kalamangController;
        feeStorage = IKalamangFeeStorage(_kalamangFeeStorage);
        token = IKAP20(_token);
        kycBitkubChain = IKYCBitkubChain(_kycBitkubChain);
        sdkTransferRouter = ISdkTransferRouter(_sdkTransferRouter);
        owner = msg.sender;
        isPaused = false;
    }

    function createKalamang(
        KalaMangConfig calldata _config
    ) external override whenNotPaused onlyKalaMangController {
        require(!kalamangsExists[_config.kalamangId], "Kalamang exists");

        KalaMang storage newKalamang = kalamangs[_config.kalamangId];
        newKalamang.creator = _config.creator;
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
        uint256 _claimTokens,
        address _recipient
    ) external override onlyKalaMangController returns (uint256) {
        KalaMang storage kalamang = kalamangs[_kalamangId];
        require(kalamang.creator != address(0), "Kalamang does not exist");
        require(kalamang.isactive, "Kalamang is not active");
        require(!kalamang.hasClaimed[_recipient], "Already claimed");
        require(
            !kalamang.isRequireWhitelist || kalamang.whitelist[_recipient],
            "Address is not in whitelist"
        );
        require(
            kycBitkubChain.kycsLevel(_recipient) >= kalamang.acceptedKYCLevel,
            "KYC level is not accepted"
        );
        require(
            kalamang.claimedRecipients < kalamang.maxRecipients,
            "All tokens have been claimed"
        );

        kalamang.hasClaimed[_recipient] = true;
        kalamang.claimedRecipients++;
        kalamang.claimedTokens += _claimTokens;

        uint256 fee = feeStorage.getFee();

        if (fee > 0) {
            uint256 feeAmount = (_claimTokens * fee) / 10000;
            require(
                token.transfer(address(feeStorage), feeAmount),
                "Transfer fee failed"
            );
            _claimTokens -= feeAmount;
        }

        claimedHistory[_kalamangId].push(
            KalaMangClaimedHistory({
                claimedAddress: _recipient,
                claimedAmount: _claimTokens
            })
        );

        require(token.transfer(_recipient, _claimTokens), "Transfer failed");

        return _claimTokens;
    }

    function abortKalamang(
        string calldata _kalamangId,
        address _creator
    ) external override ownerOrKalaMangController returns (uint256) {
        KalaMang storage kalamang = kalamangs[_kalamangId];
        require(kalamang.creator != address(0), "Kalamang does not exist");
        require(kalamang.creator == _creator, "Invalid creator");
        require(kalamang.isactive == true, "Already aborted");

        uint256 amount = kalamang.totalTokens - kalamang.claimedTokens;

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

            uint256 amount = kalamang.totalTokens - kalamang.claimedTokens;

            require(
                token.transfer(kalamang.creator, amount),
                "Token transfer failed"
            );

            kalamang.isactive = false;
        }
    }

    function getKalamangInfo(
        string calldata kalamangId
    ) public view virtual override returns (KalaMangInfo memory) {
        KalaMang storage kalamang = kalamangs[kalamangId];
        require(kalamang.creator != address(0), "Kalamang does not exist");

        KalaMangInfo memory info;
        info.creator = kalamang.creator;
        info.kalamangId = kalamangId;
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

    function getMyKalamangs(
        address _kalamangOwnerAddress,
        uint256 _page,
        uint256 _pageLength
    ) public view virtual returns (string[] memory) {
        uint256[] memory kalamangIdIndexes = kalamangsOwner[
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

        for (uint256 i = start; i > end; i--) {
            myKalamangIds[index] = kalamangIds[kalamangIdIndexes[i - 1]]; // Access element before decrementing
            index++;
        }

        return myKalamangIds;
    }

    function getKalamangWhitelist(
        string calldata kalamangId
    ) public view virtual returns (address[] memory) {
        KalaMang storage kalamang = kalamangs[kalamangId];
        if (kalamang.creator == address(0)) {
            return new address[](0);
        }

        return kalamang.whitelistArray;
    }

    function isInWhitelist(
        string calldata kalamangId,
        address _target
    ) public view virtual returns (bool) {
        KalaMang storage kalamang = kalamangs[kalamangId];
        return kalamang.creator != address(0) && kalamang.whitelist[_target];
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

    function updateWhitelist(
        string calldata _kalamangId,
        bool _isRequireWhitelist,
        address[] calldata _whitelist,
        address _creator
    ) external override onlyKalaMangController {
        KalaMang storage kalamang = kalamangs[_kalamangId];
        require(kalamang.creator == _creator, "Invalid creator");
        require(kalamang.isactive, "Kalamang is not active");

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
    ) external override onlyKalaMangController {
        KalaMang storage kalamang = kalamangs[_kalamangId];
        require(kalamang.creator == _creator, "Invalid creator");
        require(kalamang.isactive, "Kalamang is not active");

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
    ) external override onlyKalaMangController {
        KalaMang storage kalamang = kalamangs[_kalamangId];
        require(kalamang.creator == _creator, "Invalid creator");
        require(kalamang.isactive, "Kalamang is not active");

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

    function setKalaMangController(
        address _kalaMangController
    ) external onlyOwner {
        kalamangController = _kalaMangController;
    }

    function setToken(address _token) external onlyOwner {
        token = IKAP20(_token);
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

    function setKalamangName(string calldata _kalamangName) external onlyOwner {
        kalamangName = _kalamangName;
    }
}
