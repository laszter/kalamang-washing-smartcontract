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

    // Custom errors (cheaper than require-strings: smaller bytecode + cheaper
    // revert path). One error per distinct old message, so the frontend can map
    // each 4-byte selector back to a specific user-facing message.
    error NotOwner();
    error NotController();
    error NotOwnerOrController();
    error Paused();
    error TokenNotAllowed();
    error KalamangExists();
    error KalamangNotFound();
    error TokenTransferFailed();
    error KalamangNotActive();
    error VoucherRequired();
    error AlreadyClaimed();
    error AllClaimed();
    error NotWhitelisted();
    error KycTooLow();
    error FeeTransferFailed();
    error TransferFailed();
    error InvalidCreator();
    error AlreadyAborted();
    error KalamangAborted();
    error AlreadyUnlocked();
    error FeeTooHigh();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyKalamangController() {
        if (msg.sender != kalamangController) revert NotController();
        _;
    }

    modifier ownerOrKalamangController() {
        if (msg.sender != owner && msg.sender != kalamangController) {
            revert NotOwnerOrController();
        }
        _;
    }

    modifier whenNotPaused() {
        if (isPaused) revert Paused();
        _;
    }

    // Packed: `owner` (20 bytes) + `isPaused` + `isAllowAllTokens` (1 byte each)
    // share slot 0, so the pause/allow flags are read warm during create/claim.
    address public owner;
    bool public isPaused;
    bool public isAllowAllTokens;
    address public kalamangController;
    uint256 public totalKalaMangs;
    IKYCBitkubChain public kycBitkubChain;
    ISdkTransferRouter public sdkTransferRouter;
    IKalamangFeeStorage public feeStorage;

    mapping(string => uint256) private kalamangIds;
    mapping(uint256 => Kalamang) private kalamangs;
    mapping(string => bool) private kalamangsExists;
    mapping(address => uint256[]) private kalamangsOwner;

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
        if (!allowTokenAddress[_config.tokenAddress] && !isAllowAllTokens) {
            revert TokenNotAllowed();
        }
        if (kalamangsExists[_config.kalamangId]) revert KalamangExists();

        kalamangsExists[_config.kalamangId] = true;
        kalamangIds[_config.kalamangId] = totalKalaMangs;

        Kalamang storage newKalamang = kalamangs[totalKalaMangs];
        // A fresh struct slot is already zero, so claimedTokens/claimedRecipients
        // are left unset (writing 0 to a fresh slot would just waste gas).
        newKalamang.creator = _config.creator;
        newKalamang.kalamangId = _config.kalamangId;
        newKalamang.tokenAddress = _config.tokenAddress;
        newKalamang.totalTokens = _config.totalTokens;
        newKalamang.maxRecipients = _config.maxRecipients;
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

        address[] calldata _wl = _config.whitelist;
        uint256 _wlLen = _wl.length;
        for (uint256 i = 0; i < _wlLen; ) {
            newKalamang.whitelist[_wl[i]] = true;
            unchecked {
                ++i;
            }
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
            if (
                !_token.transferFrom(
                    _config.creator,
                    address(this),
                    _config.totalTokens
                )
            ) {
                revert TokenTransferFailed();
            }
        }
    }

    // V2 (gas): the controller passes only (kalamangId, recipient, enforceGate)
    // and this single call validates, computes the amount, updates state and
    // transfers — folding what used to be three separate storage round-trips
    // (isVoucherRequired + getKalamangInfo + claimToken) into one. The claim
    // amount is derived from the pre-increment state below.
    function claimToken(
        string calldata _kalamangId,
        address _recipient,
        bool _enforceVoucherGate
    ) external override onlyKalamangController returns (uint256) {
        Kalamang storage kalamang = kalamangs[kalamangIds[_kalamangId]];
        if (kalamang.creator == address(0)) revert KalamangNotFound();
        if (!kalamang.isActive) revert KalamangNotActive();
        // Anti-Sybil (Layer 3): only the direct EOA claimToken path enforces the
        // voucher gate. claimTokenBySig / claimTokenWithVoucher / claimTokenBySdk
        // pass false because they carry their own authorization.
        if (_enforceVoucherGate && kalamang.requireVoucher) {
            revert VoucherRequired();
        }
        if (kalamang.hasClaimed[_recipient]) revert AlreadyClaimed();
        if (kalamang.claimedRecipients >= kalamang.maxRecipients) {
            revert AllClaimed();
        }
        if (
            kalamang.isRequireWhitelist && !kalamang.whitelist[_recipient]
        ) {
            revert NotWhitelisted();
        }
        // KYC is an external staticcall — checked last so cheaper checks fail
        // first, and skipped entirely for open (level 0) kalamangs.
        if (
            kalamang.acceptedKYCLevel != 0 &&
            kycBitkubChain.kycsLevel(_recipient) < kalamang.acceptedKYCLevel
        ) {
            revert KycTooLow();
        }

        // Amount is computed from pre-increment counters (mirrors the old
        // controller getAmountToClaim exactly, same RNG seed).
        uint256 _claimTokens = _computeClaimAmount(
            kalamang,
            _kalamangId,
            _recipient
        );

        IKAP20 _token = IKAP20(kalamang.tokenAddress);

        kalamang.hasClaimed[_recipient] = true;
        // Counters can never exceed the token supply / recipient cap they track.
        unchecked {
            kalamang.claimedRecipients++;
            // Accumulate GROSS (pre-fee) so remainingAmounts tracks the escrow.
            kalamang.claimedTokens += _claimTokens;
        }

        // V2: use the fee snapshotted on this kalamang instead of the global fee.
        uint256 _fee = kalamang.fee;

        if (_fee > 0) {
            uint256 feeAmount = (_claimTokens * _fee) / 10000;
            if (!_token.transfer(address(feeStorage), feeAmount)) {
                revert FeeTransferFailed();
            }
            _claimTokens -= feeAmount;
        }

        if (!_token.transfer(_recipient, _claimTokens)) revert TransferFailed();

        // Per-claim history now lives in the KalamangV2.TokenClaimed event
        // (emitted by the controller) instead of an on-chain array.
        return _claimTokens;
    }

    // V2 (gas): claim-amount math moved here from the controller so it reads the
    // same struct the claim already loads (no getKalamangInfo round-trip, no
    // wasted token.symbol() call). Behaviour is identical to the old
    // getAmountToClaim, using pre-increment claimedRecipients/claimedTokens.
    function _computeClaimAmount(
        Kalamang storage kalamang,
        string calldata _kalamangId,
        address _recipient
    ) private view returns (uint256) {
        uint256 remaining = kalamang.totalTokens - kalamang.claimedTokens;
        uint256 claimedRecipients = kalamang.claimedRecipients;
        uint256 maxRecipients = kalamang.maxRecipients;

        // Last recipient sweeps whatever is left.
        if (claimedRecipients + 1 == maxRecipients) {
            return remaining;
        }

        if (kalamang.isRandom) {
            uint256 recipientsLeft = maxRecipients - claimedRecipients;
            uint256 fairControlFactor = (remaining * 2) / recipientsLeft;
            uint256 range = (kalamang.maxRandom - kalamang.minRandom) *
                100 +
                1;
            uint256 minRandomScaled = kalamang.minRandom * 100;
            uint256 randomFactor = uint256(
                keccak256(
                    abi.encodePacked(block.timestamp, _recipient, _kalamangId)
                )
            );
            uint256 randomValueInRange = (randomFactor % range) +
                minRandomScaled;
            uint256 randomAmount = (fairControlFactor * randomValueInRange) /
                10000;
            if (randomAmount > remaining) {
                randomAmount = remaining;
            }
            return randomAmount;
        }

        uint256 claimAmount = kalamang.totalTokens / maxRecipients;
        if (claimAmount > remaining) {
            claimAmount = remaining;
        }
        return claimAmount;
    }

    function abortKalamang(
        string calldata _kalamangId,
        address _creator
    ) external override ownerOrKalamangController returns (uint256) {
        Kalamang storage kalamang = kalamangs[kalamangIds[_kalamangId]];
        address creator = kalamang.creator;
        if (creator == address(0)) revert KalamangNotFound();
        if (creator != _creator) revert InvalidCreator();
        if (!kalamang.isActive) revert AlreadyAborted();

        IKAP20 _token = IKAP20(kalamang.tokenAddress);

        uint256 _amount = kalamang.totalTokens - kalamang.claimedTokens;

        if (!_token.transfer(creator, _amount)) revert TokenTransferFailed();

        kalamang.isActive = false;

        return _amount;
    }

    function abortAllKalamang() external onlyOwner {
        uint256 _total = totalKalaMangs;
        for (uint256 i = 0; i < _total; ) {
            Kalamang storage kalamang = kalamangs[i];

            if (
                kalamang.isActive &&
                kalamang.maxRecipients != kalamang.claimedRecipients
            ) {
                IKAP20 _token = IKAP20(kalamang.tokenAddress);

                uint256 _amount = kalamang.totalTokens -
                    kalamang.claimedTokens;

                if (!_token.transfer(kalamang.creator, _amount)) {
                    revert TokenTransferFailed();
                }

                kalamang.isActive = false;
            }

            unchecked {
                ++i;
            }
        }
    }

    function unlockKalamang(
        string calldata _kalamangId,
        address _creator
    ) external override ownerOrKalamangController {
        Kalamang storage kalamang = kalamangs[kalamangIds[_kalamangId]];
        address creator = kalamang.creator;
        if (creator == address(0)) revert KalamangNotFound();
        if (creator != _creator) revert InvalidCreator();
        if (!kalamang.isActive) revert KalamangAborted();
        if (kalamang.isClaimable) revert AlreadyUnlocked();

        kalamang.isClaimable = true;
    }

    function getKalamangInfo(
        string calldata _kalamangId
    ) public view virtual returns (KalamangInfo memory) {
        Kalamang storage kalamang = kalamangs[kalamangIds[_kalamangId]];
        // NOTE: must keep reverting on an unknown id — the frontend's
        // getKalamangVersion probe relies on this revert to tell V1 from V2.
        if (kalamang.creator == address(0)) revert KalamangNotFound();

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

    // V2 (anti-Sybil Layer 3): cheap lookup used by the frontend/server to decide
    // whether a kalamang must be claimed with a server-issued voucher. (The
    // direct-claim gate itself is now enforced inside claimToken via the
    // enforceVoucherGate flag, so the controller no longer needs to call this.)
    function isVoucherRequired(
        string calldata _kalamangId
    ) public view virtual returns (bool) {
        Kalamang storage kalamang = kalamangs[kalamangIds[_kalamangId]];
        return kalamang.creator != address(0) && kalamang.requireVoucher;
    }

    function updateWhitelist(
        string calldata _kalamangId,
        bool _isRequireWhitelist,
        address[] calldata _whitelist,
        address _creator
    ) external override onlyKalamangController {
        Kalamang storage kalamang = kalamangs[kalamangIds[_kalamangId]];
        if (kalamang.creator != _creator) revert InvalidCreator();
        if (!kalamang.isActive) revert KalamangNotActive();

        kalamang.isRequireWhitelist = _isRequireWhitelist;

        address[] storage _old = kalamang.whitelistArray;
        uint256 _oldLen = _old.length;
        for (uint256 i = 0; i < _oldLen; ) {
            kalamang.whitelist[_old[i]] = false;
            unchecked {
                ++i;
            }
        }

        kalamang.whitelistArray = _whitelist;

        uint256 _newLen = _whitelist.length;
        for (uint256 i = 0; i < _newLen; ) {
            kalamang.whitelist[_whitelist[i]] = true;
            unchecked {
                ++i;
            }
        }
    }

    function addWhitelist(
        string calldata _kalamangId,
        address[] calldata _whitelist,
        address _creator
    ) external override onlyKalamangController {
        Kalamang storage kalamang = kalamangs[kalamangIds[_kalamangId]];
        if (kalamang.creator != _creator) revert InvalidCreator();
        if (!kalamang.isActive) revert KalamangNotActive();

        uint256 _len = _whitelist.length;
        for (uint256 i = 0; i < _len; ) {
            address _addr = _whitelist[i];
            // Positive guard (not `continue`) so the unchecked ++i below is
            // always reached — a `continue` before it would loop forever.
            if (!kalamang.whitelist[_addr]) {
                kalamang.whitelist[_addr] = true;
                kalamang.whitelistArray.push(_addr);
            }
            unchecked {
                ++i;
            }
        }
    }

    function removeWhitelist(
        string calldata _kalamangId,
        address[] calldata _whitelist,
        address _creator
    ) external override onlyKalamangController {
        Kalamang storage kalamang = kalamangs[kalamangIds[_kalamangId]];
        if (kalamang.creator != _creator) revert InvalidCreator();
        if (!kalamang.isActive) revert KalamangNotActive();

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
        if (kalamang.creator == address(0)) revert KalamangNotFound();
        if (!kalamang.isActive) revert KalamangNotActive();
        if (_fee > 10000) revert FeeTooHigh();

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
        if (kalamang.creator == address(0)) revert KalamangNotFound();

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
        if (kalamang.creator == address(0)) revert KalamangNotFound();

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
