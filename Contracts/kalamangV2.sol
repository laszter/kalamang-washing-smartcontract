// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./interfaces/IKalamangStorageV2.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract KalamangV2 is EIP712 {
    // Readable version identifier of this contract.
    uint256 public constant VERSION = 2;

    // Custom errors (cheaper than require-strings). One per distinct old message
    // so the frontend can map each 4-byte selector to a user-facing message.
    error NotOwner();
    error NotPendingOwner();
    error NotSdkRouter();
    error CreatePaused();
    error ZeroTotalTokens();
    error ZeroMaxRecipients();
    error NotTrustedRelayer();
    error NotGasless();
    error SignatureExpired();
    error InvalidSignature();
    error IssuerNotSet();
    error VoucherExpired();
    error InvalidVoucher();

    bytes32 private constant CLAIM_TYPEHASH =
        keccak256("Claim(string kalamangId,address recipient,uint256 deadline)");

    // V2 (anti-Sybil Layer 3): typehash for a server-issued claim voucher. The
    // issuer signs (kalamangId, recipient, deadline); the recipient submits it
    // via claimTokenWithVoucher and pays the gas themselves.
    bytes32 private constant VOUCHER_TYPEHASH =
        keccak256("ClaimVoucher(string kalamangId,address recipient,uint256 deadline)");

    // V2 (safe ownership transfer): a two-step owner change — setOwner nominates,
    // acceptOwnership confirms — guards against handing ownership to a wrong or
    // dead address. No longer immutable, so onlyOwner now reads it from storage.
    address public owner;
    // Address nominated by setOwner; becomes owner only once it calls
    // acceptOwnership. address(0) means no transfer is pending.
    address public pendingOwner;
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
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlySdkCallHelperRouter() {
        if (msg.sender != sdkCallHelperRouter) revert NotSdkRouter();
        _;
    }

    modifier whenNotPaused() {
        if (isPaused) revert CreatePaused();
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
    // V2 (safe ownership transfer): emitted when setOwner nominates a new owner
    // and when acceptOwnership finalizes the move.
    event OwnershipTransferStarted(
        address indexed previousOwner,
        address indexed newOwner
    );
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    // Function to generate a random string
    function generateRandomString(
        uint256 _length
    ) private view returns (string memory) {
        bytes memory randomString = new bytes(_length);
        // Hoisted out of the loop: keep it as `bytes` so we index it directly
        // (no per-iteration `bytes(charset)` allocation) and read its length
        // once. The per-index keccak is unchanged, so the id is identical.
        bytes
            memory charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
        uint256 charsetLength = charset.length;

        for (uint256 i = 0; i < _length; ) {
            randomString[i] = charset[
                uint256(
                    keccak256(
                        abi.encodePacked(
                            block.timestamp,
                            block.number,
                            msg.sender,
                            i
                        )
                    )
                ) % charsetLength
            ];
            unchecked {
                ++i;
            }
        }

        return string(randomString);
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
    ) external whenNotPaused returns (string memory kalamangId) {
        if (_totalTokens == 0) revert ZeroTotalTokens();
        if (_maxRecipients == 0) revert ZeroMaxRecipients();

        kalamangId = generateRandomString(64);

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

        // V2 (feature): return the id so the caller doesn't have to scrape it
        // from the KalamangCreated log (on-chain callers get it directly; the
        // web reads it from the tx receipt's KalamangCreated event).
        return kalamangId;
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
        bytes calldata _whitelist,
        bool _isClaimable,
        address _bitkubNext
    )
        external
        onlySdkCallHelperRouter
        whenNotPaused
        returns (string memory kalamangId)
    {
        if (_totalTokens == 0) revert ZeroTotalTokens();
        if (_maxRecipients == 0) revert ZeroMaxRecipients();

        kalamangId = generateRandomString(64);

        // Build the config field-by-field (not the positional constructor) to
        // keep this function under the stack-too-deep limit without viaIR.
        IKalamangStorageV2.KalamangConfig memory kalamangConfig;
        kalamangConfig.kalamangId = kalamangId;
        kalamangConfig.creator = _bitkubNext;
        kalamangConfig.tokenAddress = _tokenAddress;
        kalamangConfig.totalTokens = _totalTokens;
        kalamangConfig.maxRecipients = _maxRecipients;
        kalamangConfig.isRandom = _isRandom;
        kalamangConfig.minRandom = _minRandom;
        kalamangConfig.maxRandom = _maxRandom;
        kalamangConfig.acceptedKYCLevel = _acceptedKYCLevel;
        kalamangConfig.isClaimable = _isClaimable;
        kalamangConfig.isRequireWhitelist = _isRequireWhitelist;
        kalamangConfig.whitelist = abi.decode(_whitelist, (address[]));
        kalamangConfig.isSdkCallerHelper = true;
        // SDK / Bitkub Next creates default to requiring a voucher.
        kalamangConfig.requireVoucher = true;

        kalamangStorage.createKalamang(kalamangConfig);

        emit KalamangCreated(
            kalamangId,
            _bitkubNext,
            _totalTokens,
            _maxRecipients
        );

        return kalamangId;
    }

    function claimToken(
        string calldata _kalamangId
    ) external returns (uint256) {
        // V2 (anti-Sybil Layer 3): a kalamang flagged requireVoucher cannot be
        // claimed directly — the storage layer enforces this when the last
        // argument is true (only this direct EOA path passes true). The claimer
        // must instead go through claimTokenWithVoucher with a server voucher.
        uint256 amount = kalamangStorage.claimToken(
            _kalamangId,
            msg.sender,
            true
        );

        emit TokenClaimed(_kalamangId, msg.sender, amount);
        return amount;
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
    ) external returns (uint256) {
        if (!trustedRelayers[msg.sender]) revert NotTrustedRelayer();
        // V2: gasless claims are only allowed for kalamangs the owner has
        // explicitly flagged as gas-sponsored. This keeps the relayer from
        // paying gas for kalamangs that are not meant to be free-gas, even if
        // an off-chain check is bypassed.
        if (!kalamangStorage.isKalamangGasless(_kalamangId)) revert NotGasless();
        if (block.timestamp > _deadline) revert SignatureExpired();

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
        if (ECDSA.recover(digest, _signature) != _recipient) {
            revert InvalidSignature();
        }

        // enforceVoucherGate = false: the EIP-712 signature is the authorization.
        uint256 amount = kalamangStorage.claimToken(
            _kalamangId,
            _recipient,
            false
        );

        emit TokenClaimed(_kalamangId, _recipient, amount);
        return amount;
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
    ) external returns (uint256) {
        if (claimIssuer == address(0)) revert IssuerNotSet();
        if (block.timestamp > _deadline) revert VoucherExpired();

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
        if (ECDSA.recover(digest, _voucherSig) != claimIssuer) {
            revert InvalidVoucher();
        }

        // enforceVoucherGate = false: the voucher signature already authorized
        // this claim; the direct-claim gate would double-reject it.
        uint256 amount = kalamangStorage.claimToken(
            _kalamangId,
            msg.sender,
            false
        );

        emit TokenClaimed(_kalamangId, msg.sender, amount);
        return amount;
    }

    function claimTokenBySdk(
        string calldata _kalamangId,
        address _bitkubNext
    ) external onlySdkCallHelperRouter returns (uint256) {
        uint256 amount = kalamangStorage.claimToken(
            _kalamangId,
            _bitkubNext,
            false
        );

        emit TokenClaimed(_kalamangId, _bitkubNext, amount);
        return amount;
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
        bytes calldata _whitelist,
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
        bytes calldata _whitelist,
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
        bytes calldata _whitelist,
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

    // V2 (safe ownership transfer): step 1 of 2 — the current owner nominates a
    // new owner. Ownership does NOT change here; the nominee must call
    // acceptOwnership to finalize the move. Pass address(0) to cancel a pending
    // nomination.
    function setOwner(address _owner) external onlyOwner {
        pendingOwner = _owner;
        emit OwnershipTransferStarted(owner, _owner);
    }

    // V2 (safe ownership transfer): step 2 of 2 — the nominated address claims
    // ownership. Only a wallet that can actually transact can accept, so
    // ownership can never be handed to a wrong or unusable address.
    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert NotPendingOwner();
        address previousOwner = owner;
        owner = pendingOwner;
        pendingOwner = address(0);
        emit OwnershipTransferred(previousOwner, owner);
    }
}
