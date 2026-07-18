// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./interfaces/IKalamangStorageV2.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract KalamangV2 is EIP712 {
    // Readable version identifier of this contract.
    uint256 public constant VERSION = 2;

    bytes32 private constant CLAIM_TYPEHASH =
        keccak256("Claim(string kalamangId,address recipient,uint256 deadline)");

    // V2 (anti-Sybil Layer 3): typehash for a server-issued claim voucher. The
    // issuer signs (kalamangId, recipient, deadline); the recipient submits it
    // via claimTokenWithVoucher and pays the gas themselves.
    bytes32 private constant VOUCHER_TYPEHASH =
        keccak256("ClaimVoucher(string kalamangId,address recipient,uint256 deadline)");

    address public owner;
    address public sdkCallHelperRouter;
    IKalamangStorageV2 public kalamangStorage;
    bool public isPaused;
    uint256 public randomSetSize;
    // V2: addresses allowed to submit gasless (relayed) claims on behalf of a
    // signer via claimTokenBySig.
    mapping(address => bool) public trustedRelayers;
    // V2 (anti-Sybil Layer 3): the server key that signs claim vouchers. Only
    // vouchers signed by this address are accepted by claimTokenWithVoucher. Set
    // to address(0) to disable voucher claims entirely. Rotating it instantly
    // invalidates every previously issued voucher.
    address public claimIssuer;

    constructor(
        address _sdkCallHelperRouter,
        address _kalamangStorage
    ) EIP712("KalamangV2", "1") {
        sdkCallHelperRouter = _sdkCallHelperRouter;
        kalamangStorage = IKalamangStorageV2(_kalamangStorage);
        owner = msg.sender;
        isPaused = false;
        randomSetSize = 5;
    }

    modifier onlyOwner() {
        require(
            msg.sender == owner,
            "KalamangV2 : Only owner can call this function"
        );
        _;
    }

    modifier onlySdkCallHelperRouter() {
        require(
            msg.sender == sdkCallHelperRouter,
            "KalamangV2 : Only sdkCallHelperRouter can call this function"
        );
        _;
    }

    modifier whenNotPaused() {
        require(
            !isPaused,
            "KalamangV2 : The contract pause create kalamang"
        );
        _;
    }

    event KalamangCreated(
        string kalamangId,
        address indexed creator,
        uint256 totalTokens,
        uint256 maxRecipients
    );
    event TokenClaimed(
        string kalamangId,
        address indexed recipient,
        uint256 amount
    );
    event KalamangAborted(string kalamangId, uint256 returnAmount);
    event KalamangUnlocked(string kalamangId);
    event TrustedRelayerUpdated(address indexed relayer, bool isTrusted);
    event ClaimIssuerUpdated(address indexed issuer);

    // Function to generate a random string
    function generateRandomString(
        uint256 _length
    ) private view returns (string memory) {
        bytes memory randomString = new bytes(_length);
        string
            memory charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";

        for (uint256 i = 0; i < _length; i++) {
            randomString[i] = bytes(charset)[
                uint256(
                    keccak256(
                        abi.encodePacked(
                            block.timestamp,
                            block.number,
                            msg.sender,
                            i
                        )
                    )
                ) % bytes(charset).length
            ];
        }

        return string(randomString);
    }

    function getAmountToClaim(
        string calldata _kalamangId,
        address _recipient
    ) private view returns (uint256) {
        IKalamangStorageV2.KalamangInfo memory kalamangInfo = kalamangStorage
            .getKalamangInfo(_kalamangId);

        if (!kalamangInfo.isActive) {
            return 0;
        }

        uint256 claimAmount;

        if (kalamangInfo.claimedRecipients + 1 == kalamangInfo.maxRecipients) {
            // Directly assign remaining amounts if it’s the last recipient
            return kalamangInfo.remainingAmounts;
        }

        if (kalamangInfo.isRandom) {
            // Precompute constants and minimize repetitive calculations
            uint256 recipientsLeft = kalamangInfo.maxRecipients -
                kalamangInfo.claimedRecipients;
            uint256 fairControlFactor = (kalamangInfo.remainingAmounts * 2) /
                recipientsLeft;
            uint256 range = (kalamangInfo.maxRandom - kalamangInfo.minRandom) *
                100 +
                1;
            uint256 minRandomScaled = kalamangInfo.minRandom * 100;

            uint256 randomFactor = uint256(
                keccak256(
                    abi.encodePacked(block.timestamp, _recipient, _kalamangId)
                )
            );

            uint256 randomValueInRange = (randomFactor % range) +
                minRandomScaled;
            uint256 randomAmount = (fairControlFactor * randomValueInRange) /
                10000;

            if (randomAmount > kalamangInfo.remainingAmounts) {
                randomAmount = kalamangInfo.remainingAmounts;
            }

            claimAmount = randomAmount;
        } else {
            // Distribute equal amounts directly
            claimAmount = kalamangInfo.totalTokens / kalamangInfo.maxRecipients;

            if (claimAmount > kalamangInfo.remainingAmounts) {
                claimAmount = kalamangInfo.remainingAmounts;
            }
        }

        return claimAmount;
    }

    function createKalamang(
        address _tokenAddress,
        uint256 _totalTokens,
        uint256 _maxRecipients,
        bool _isRandom,
        uint256 _minRandom,
        uint256 _maxRandom,
        uint256 _acceptedKYCLevel,
        bool _isRequireWhitelist,
        address[] calldata _whitelist,
        bool _isClaimable,
        bool _requireVoucher
    ) external whenNotPaused {
        require(
            _totalTokens > 0,
            "KalamangV2 : Total tokens must be greater than zero"
        );
        require(
            _maxRecipients > 0,
            "KalamangV2 : Max recipients must be greater than zero"
        );

        string memory kalamangId = generateRandomString(64);

        IKalamangStorageV2.KalamangConfig
            memory kalamangConfig = IKalamangStorageV2.KalamangConfig(
                kalamangId,
                msg.sender,
                _tokenAddress,
                _totalTokens,
                _maxRecipients,
                _isRandom,
                _minRandom,
                _maxRandom,
                _acceptedKYCLevel,
                _isClaimable,
                _isRequireWhitelist,
                _whitelist,
                false,
                _requireVoucher
            );

        kalamangStorage.createKalamang(kalamangConfig);

        emit KalamangCreated(
            kalamangId,
            msg.sender,
            _totalTokens,
            _maxRecipients
        );
    }

    function createKalamangBySdk(
        address _tokenAddress,
        uint256 _totalTokens,
        uint256 _maxRecipients,
        bool _isRandom,
        uint256 _minRandom,
        uint256 _maxRandom,
        uint256 _acceptedKYCLevel,
        bool _isRequireWhitelist,
        bytes memory _whitelist,
        bool _isClaimable,
        address _bitkubNext
    ) external onlySdkCallHelperRouter whenNotPaused {
        require(
            _totalTokens > 0,
            "KalamangV2 : Total tokens must be greater than zero"
        );
        require(
            _maxRecipients > 0,
            "KalamangV2 : Max recipients must be greater than zero"
        );

        string memory kalamangId = generateRandomString(64);

        address[] memory _whitelistArr;
        (_whitelistArr) = abi.decode(_whitelist, (address[]));

        IKalamangStorageV2.KalamangConfig
            memory kalamangConfig = IKalamangStorageV2.KalamangConfig(
                kalamangId,
                _bitkubNext,
                _tokenAddress,
                _totalTokens,
                _maxRecipients,
                _isRandom,
                _minRandom,
                _maxRandom,
                _acceptedKYCLevel,
                _isClaimable,
                _isRequireWhitelist,
                _whitelistArr,
                true, // isSdkCallerHelper
                true // requireVoucher: SDK / Bitkub Next creates default to requiring a voucher
            );

        kalamangStorage.createKalamang(kalamangConfig);

        emit KalamangCreated(
            kalamangId,
            _bitkubNext,
            _totalTokens,
            _maxRecipients
        );
    }

    function claimToken(string calldata _kalamangId) external {
        // V2 (anti-Sybil Layer 3): a kalamang flagged requireVoucher cannot be
        // claimed by calling the contract directly — the claimer must go through
        // claimTokenWithVoucher with a server-issued voucher. This is what forces
        // bot traffic back through the server's off-chain checks.
        require(
            !kalamangStorage.isVoucherRequired(_kalamangId),
            "KalamangV2 : Voucher required"
        );

        uint256 claimAmount = getAmountToClaim(_kalamangId, msg.sender);

        uint256 amount = kalamangStorage.claimToken(
            _kalamangId,
            claimAmount,
            msg.sender
        );

        emit TokenClaimed(_kalamangId, msg.sender, amount);
    }

    // V2: gasless claim. The recipient signs an EIP-712 Claim message off-chain
    // (no gas, no KUB needed); a trusted relayer submits this tx and pays the
    // gas. Tokens are always sent to the signer (_recipient), so a relayer can
    // never divert them.
    function claimTokenBySig(
        string calldata _kalamangId,
        address _recipient,
        uint256 _deadline,
        bytes calldata _signature
    ) external {
        require(
            trustedRelayers[msg.sender],
            "KalamangV2 : Only trusted relayer can call this function"
        );
        // V2: gasless claims are only allowed for kalamangs the owner has
        // explicitly flagged as gas-sponsored. This keeps the relayer from
        // paying gas for kalamangs that are not meant to be free-gas, even if
        // an off-chain check is bypassed.
        require(
            kalamangStorage.isKalamangGasless(_kalamangId),
            "KalamangV2 : Kalamang is not gasless"
        );
        require(
            block.timestamp <= _deadline,
            "KalamangV2 : Signature expired"
        );

        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    CLAIM_TYPEHASH,
                    keccak256(bytes(_kalamangId)),
                    _recipient,
                    _deadline
                )
            )
        );
        require(
            ECDSA.recover(digest, _signature) == _recipient,
            "KalamangV2 : Invalid signature"
        );

        uint256 claimAmount = getAmountToClaim(_kalamangId, _recipient);

        uint256 amount = kalamangStorage.claimToken(
            _kalamangId,
            claimAmount,
            _recipient
        );

        emit TokenClaimed(_kalamangId, _recipient, amount);
    }

    // V2 (anti-Sybil Layer 3): direct claim that requires a server-issued
    // voucher. The recipient (msg.sender) pays their own gas; the server only
    // signs the voucher off-chain (free) after its captcha / dedup / velocity
    // checks pass. A bot calling this directly cannot forge a voucher because the
    // contract only accepts signatures from claimIssuer, whose key lives on the
    // server. Tokens go to msg.sender, so a voucher issued to one address is
    // useless to any other caller.
    function claimTokenWithVoucher(
        string calldata _kalamangId,
        uint256 _deadline,
        bytes calldata _voucherSig
    ) external {
        require(
            claimIssuer != address(0),
            "KalamangV2 : Voucher issuer not set"
        );
        require(
            block.timestamp <= _deadline,
            "KalamangV2 : Voucher expired"
        );

        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    VOUCHER_TYPEHASH,
                    keccak256(bytes(_kalamangId)),
                    msg.sender,
                    _deadline
                )
            )
        );
        require(
            ECDSA.recover(digest, _voucherSig) == claimIssuer,
            "KalamangV2 : Invalid voucher"
        );

        uint256 claimAmount = getAmountToClaim(_kalamangId, msg.sender);

        uint256 amount = kalamangStorage.claimToken(
            _kalamangId,
            claimAmount,
            msg.sender
        );

        emit TokenClaimed(_kalamangId, msg.sender, amount);
    }

    function claimTokenBySdk(
        string calldata _kalamangId,
        address _bitkubNext
    ) external onlySdkCallHelperRouter {
        uint256 claimAmount = getAmountToClaim(_kalamangId, _bitkubNext);

        uint256 amount = kalamangStorage.claimToken(
            _kalamangId,
            claimAmount,
            _bitkubNext
        );

        emit TokenClaimed(_kalamangId, _bitkubNext, amount);
    }

    function updateWhitelist(
        string calldata _kalamangId,
        bool _isRequireWhitelist,
        address[] calldata _whitelist
    ) external {
        kalamangStorage.updateWhitelist(
            _kalamangId,
            _isRequireWhitelist,
            _whitelist,
            msg.sender
        );
    }

    function updateWhitelistBySdk(
        string calldata _kalamangId,
        bool _isRequireWhitelist,
        bytes memory _whitelist,
        address _bitkubNext
    ) external onlySdkCallHelperRouter {
        address[] memory _whitelistArr;
        (_whitelistArr) = abi.decode(_whitelist, (address[]));

        kalamangStorage.updateWhitelist(
            _kalamangId,
            _isRequireWhitelist,
            _whitelistArr,
            _bitkubNext
        );
    }

    function addWhitelist(
        string calldata _kalamangId,
        address[] calldata _whitelist
    ) external {
        kalamangStorage.addWhitelist(_kalamangId, _whitelist, msg.sender);
    }

    function addWhitelistBySdk(
        string calldata _kalamangId,
        bytes memory _whitelist,
        address _bitkubNext
    ) external onlySdkCallHelperRouter {
        address[] memory _whitelistArr;
        (_whitelistArr) = abi.decode(_whitelist, (address[]));

        kalamangStorage.addWhitelist(_kalamangId, _whitelistArr, _bitkubNext);
    }

    function removeWhitelist(
        string calldata _kalamangId,
        address[] calldata _whitelist
    ) external {
        kalamangStorage.removeWhitelist(_kalamangId, _whitelist, msg.sender);
    }

    function removeWhitelistBySdk(
        string calldata _kalamangId,
        bytes memory _whitelist,
        address _bitkubNext
    ) external onlySdkCallHelperRouter {
        address[] memory _whitelistArr;
        (_whitelistArr) = abi.decode(_whitelist, (address[]));

        kalamangStorage.removeWhitelist(
            _kalamangId,
            _whitelistArr,
            _bitkubNext
        );
    }

    function abortKalamang(string calldata _kalamangId) external {
        uint256 amount = kalamangStorage.abortKalamang(_kalamangId, msg.sender);
        emit KalamangAborted(_kalamangId, amount);
    }

    function abortKalamangBySdk(
        string calldata _kalamangId,
        address _bitkubNext
    ) external onlySdkCallHelperRouter {
        uint256 amount = kalamangStorage.abortKalamang(
            _kalamangId,
            _bitkubNext
        );
        emit KalamangAborted(_kalamangId, amount);
    }

    function unlockKalamang(string calldata _kalamangId) external {
        kalamangStorage.unlockKalamang(_kalamangId, msg.sender);
        emit KalamangUnlocked(_kalamangId);
    }

    function unlockKalamangBySdk(
        string calldata _kalamangId,
        address _bitkubNext
    ) external onlySdkCallHelperRouter {
        kalamangStorage.unlockKalamang(_kalamangId, _bitkubNext);
        emit KalamangUnlocked(_kalamangId);
    }

    function setPause(bool _isPaused) external onlyOwner {
        isPaused = _isPaused;
    }

    // V2: register or revoke a trusted relayer for claimTokenBySig.
    function setTrustedRelayer(
        address _relayer,
        bool _isTrusted
    ) external onlyOwner {
        trustedRelayers[_relayer] = _isTrusted;
        emit TrustedRelayerUpdated(_relayer, _isTrusted);
    }

    // V2 (anti-Sybil Layer 3): set (or rotate) the claim voucher issuer. Setting
    // it to a new address instantly invalidates every voucher signed by the old
    // key; setting it to address(0) disables claimTokenWithVoucher entirely.
    function setClaimIssuer(address _issuer) external onlyOwner {
        claimIssuer = _issuer;
        emit ClaimIssuerUpdated(_issuer);
    }

    function setSdkCallHelperRouter(
        address _sdkCallHelperRouter
    ) external onlyOwner {
        sdkCallHelperRouter = _sdkCallHelperRouter;
    }

    function setkalamangStorage(address _kalamangStorage) external onlyOwner {
        kalamangStorage = IKalamangStorageV2(_kalamangStorage);
    }
}
