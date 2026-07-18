// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./interfaces/IKAP20.sol";
import "./interfaces/IKYCBitkubChain.sol";
import "./interfaces/ISdkTransferRouter.sol";
import "./interfaces/IKalamangStorageV2.sol";
import "./interfaces/IKalamangFeeStorage.sol";

contract KalamangStorageV2 is IKalamangStorageV2 {
    // Readable version identifier of this contract.
    uint256 public constant VERSION = 2;

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

    event KalamangFeeUpdated(string kalamangId, uint256 fee);
    event KalamangGaslessUpdated(string kalamangId, bool isGasless);
    event KalamangRequireVoucherUpdated(string kalamangId, bool requireVoucher);

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
        newKalamang.isActive = true;
        newKalamang.isRandom = _config.isRandom;
        newKalamang.minRandom = _config.minRandom;
        newKalamang.maxRandom = _config.maxRandom;
        newKalamang.acceptedKYCLevel = _config.acceptedKYCLevel;
        newKalamang.isClaimable = _config.isClaimable;
        // Anti-Sybil (Layer 3): the creator chooses whether direct EOA claims need a
        // server-issued voucher (the web defaults this to true). Gasless
        // (claimTokenBySig) and Bitkub Next (claimTokenBySdk) paths are unaffected.
        newKalamang.requireVoucher = _config.requireVoucher;
        // V2: snapshot the global fee onto the kalamang at creation time, so a
        // later change to the global fee never affects existing kalamangs.
        newKalamang.fee = feeStorage.getFee();
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
        require(kalamang.isActive, "KalamangStorage : Kalamang is not active");
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

        // V2: use the fee snapshotted on this kalamang instead of the global fee.
        uint256 _fee = kalamang.fee;

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
        require(kalamang.isActive == true, "KalamangStorage : Already aborted");

        IKAP20 _token = IKAP20(kalamang.tokenAddress);

        uint256 _amount = kalamang.totalTokens - kalamang.claimedTokens;

        require(
            _token.transfer(kalamang.creator, _amount),
            "KalamangStorage : Token transfer failed"
        );

        kalamang.isActive = false;

        return _amount;
    }

    function abortAllKalamang() external onlyOwner {
        for (uint256 i = 0; i < totalKalaMangs; i++) {
            Kalamang storage kalamang = kalamangs[i];

            if (
                !kalamang.isActive ||
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

            kalamang.isActive = false;
        }
    }

    function unlockKalamang(
        string calldata _kalamangId,
        address _creator
    ) external override ownerOrKalamangController {
        Kalamang storage kalamang = kalamangs[kalamangIds[_kalamangId]];
        require(
            kalamang.creator != address(0),
            "KalamangStorage : Kalamang does not exist"
        );
        require(
            kalamang.creator == _creator,
            "KalamangStorage : Invalid creator"
        );
        require(kalamang.isActive, "KalamangStorage : Kalamang is aborted");
        require(!kalamang.isClaimable, "KalamangStorage : Already unlocked");

        kalamang.isClaimable = true;
    }

    function getKalamangInfo(
        string calldata _kalamangId
    ) public view virtual returns (KalamangInfo memory) {
        Kalamang storage kalamang = kalamangs[kalamangIds[_kalamangId]];
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
        info.isActive = kalamang.isActive;
        info.isRandom = kalamang.isRandom;
        info.minRandom = kalamang.minRandom;
        info.maxRandom = kalamang.maxRandom;
        info.isRequireWhitelist = kalamang.isRequireWhitelist;
        info.acceptedKYCLevel = kalamang.acceptedKYCLevel;
        info.isClaimable = kalamang.isClaimable;
        info.remainingAmounts = kalamang.totalTokens - kalamang.claimedTokens;
        info.fee = kalamang.fee;
        info.isGasless = kalamang.isGasless;
        info.requireVoucher = kalamang.requireVoucher;

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

    function isClaimable(
        string calldata _kalamangId
    ) public view virtual returns (bool) {
        Kalamang storage kalamang = kalamangs[kalamangIds[_kalamangId]];
        return kalamang.creator != address(0) && kalamang.isClaimable;
    }

    function isClaimed(
        string calldata _kalamangId,
        address _target
    ) public view virtual returns (bool) {
        Kalamang storage kalamang = kalamangs[kalamangIds[_kalamangId]];
        return kalamang.creator != address(0) && kalamang.hasClaimed[_target];
    }

    // V2: cheap lookup used by the controller (to gate claimTokenBySig) and by
    // the frontend/relayer to decide whether a kalamang is gas-sponsored.
    function isKalamangGasless(
        string calldata _kalamangId
    ) public view virtual returns (bool) {
        Kalamang storage kalamang = kalamangs[kalamangIds[_kalamangId]];
        return kalamang.creator != address(0) && kalamang.isGasless;
    }

    // V2 (anti-Sybil Layer 3): cheap lookup used by the controller (to gate the
    // direct claimToken path) and by the frontend/server to decide whether a
    // kalamang must be claimed with a server-issued voucher.
    function isVoucherRequired(
        string calldata _kalamangId
    ) public view virtual returns (bool) {
        Kalamang storage kalamang = kalamangs[kalamangIds[_kalamangId]];
        return kalamang.creator != address(0) && kalamang.requireVoucher;
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
        require(kalamang.isActive, "KalamangStorage : Kalamang is not active");

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
        require(kalamang.isActive, "KalamangStorage : Kalamang is not active");

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
        require(kalamang.isActive, "KalamangStorage : Kalamang is not active");

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

    // V2: allow the owner to override the fee of a specific kalamang, e.g. set
    // it to 0 to make a particular kalamang fee-free.
    function setKalamangFee(
        string calldata _kalamangId,
        uint256 _fee
    ) external override onlyOwner {
        Kalamang storage kalamang = kalamangs[kalamangIds[_kalamangId]];
        require(
            kalamang.creator != address(0),
            "KalamangStorage : Kalamang does not exist"
        );
        require(kalamang.isActive, "KalamangStorage : Kalamang is not active");
        require(_fee <= 10000, "KalamangStorage : Fee exceeds 100%");

        kalamang.fee = _fee;

        emit KalamangFeeUpdated(_kalamangId, _fee);
    }

    // V2: allow the owner to flag which kalamangs are gas-sponsored. Only
    // kalamangs flagged here can be claimed gaslessly through the controller's
    // claimTokenBySig path (the platform relayer pays the gas). Not every
    // kalamang is free-gas, so this defaults to false and is toggled per id.
    function setKalamangGasless(
        string calldata _kalamangId,
        bool _isGasless
    ) external override onlyOwner {
        Kalamang storage kalamang = kalamangs[kalamangIds[_kalamangId]];
        require(
            kalamang.creator != address(0),
            "KalamangStorage : Kalamang does not exist"
        );

        kalamang.isGasless = _isGasless;

        emit KalamangGaslessUpdated(_kalamangId, _isGasless);
    }

    // V2 (anti-Sybil Layer 3): flag which kalamangs require a server-issued
    // voucher to claim. When true, the controller rejects a direct claimToken and
    // only claimTokenWithVoucher (carrying an issuer signature) succeeds. Defaults
    // to false so open kalamangs are unaffected; toggled per id by the owner.
    function setKalamangRequireVoucher(
        string calldata _kalamangId,
        bool _requireVoucher
    ) external override onlyOwner {
        Kalamang storage kalamang = kalamangs[kalamangIds[_kalamangId]];
        require(
            kalamang.creator != address(0),
            "KalamangStorage : Kalamang does not exist"
        );

        kalamang.requireVoucher = _requireVoucher;

        emit KalamangRequireVoucherUpdated(_kalamangId, _requireVoucher);
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
