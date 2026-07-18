// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IKalamangStorageV2 {
    // Field order is chosen for storage packing: `creator` (20 bytes) shares
    // slot 0 with all six bool flags (1 byte each), so a fresh createKalamang
    // writes them in one SSTORE and a claim reads them alongside `creator`.
    struct Kalamang {
        address creator;
        bool isRandom;
        bool isClaimable;
        bool isRequireWhitelist;
        bool isActive;
        // V2: when true, this kalamang can be claimed gaslessly (the platform
        // relayer pays the gas via claimTokenBySig). Set per-kalamang by the
        // owner; defaults to false so gas sponsorship is opt-in per kalamang.
        bool isGasless;
        // V2 (anti-Sybil Layer 3): when true, a direct claimToken is rejected and
        // the claimer must present a server-issued voucher (see KalamangV2
        // .claimTokenWithVoucher). Set per-kalamang by the owner; defaults to
        // false so open kalamangs are unaffected.
        bool requireVoucher;
        string kalamangId;
        address tokenAddress;
        uint256 totalTokens;
        uint256 claimedTokens;
        uint256 maxRecipients;
        uint256 claimedRecipients;
        uint256 minRandom;
        uint256 maxRandom;
        uint256 acceptedKYCLevel;
        uint256 fee;
        mapping(address => bool) hasClaimed;
        mapping(address => bool) whitelist;
        address[] whitelistArray;
    }

    struct KalamangInfo {
        address creator;
        string kalamangId;
        address tokenAddress;
        string tokenSymbol;
        uint256 maxRecipients;
        uint256 claimedRecipients;
        bool isRandom;
        uint256 minRandom;
        uint256 maxRandom;
        uint256 acceptedKYCLevel;
        bool isRequireWhitelist;
        bool isClaimable;
        uint256 totalTokens;
        uint256 remainingAmounts;
        uint256 fee;
        bool isActive;
        bool isGasless;
        bool requireVoucher;
    }

    struct KalamangConfig {
        string kalamangId;
        address creator;
        address tokenAddress;
        uint256 totalTokens;
        uint256 maxRecipients;
        bool isRandom;
        uint256 minRandom;
        uint256 maxRandom;
        uint256 acceptedKYCLevel;
        bool isClaimable;
        bool isRequireWhitelist;
        address[] whitelist;
        bool isSdkCallerHelper;
        bool requireVoucher;
    }

    function createKalamang(KalamangConfig calldata _config) external;

    // V2 (gas): the controller passes only (kalamangId, recipient, enforceGate);
    // storage computes the claim amount from its own struct read and returns the
    // net (post-fee) amount paid. `_enforceVoucherGate` is true only on the
    // direct EOA claimToken path (bySig / withVoucher / bySdk pass false).
    function claimToken(
        string calldata _kalamangId,
        address _recipient,
        bool _enforceVoucherGate
    ) external returns (uint256);

    function abortKalamang(
        string calldata _kalamangId,
        address _creator
    ) external returns (uint256);

    function unlockKalamang(
        string calldata _kalamangId,
        address _creator
    ) external;

    function getKalamangInfo(
        string calldata _kalamangId
    ) external view returns (KalamangInfo memory);

    function setKalamangFee(
        string calldata _kalamangId,
        uint256 _fee
    ) external;

    function setKalamangGasless(
        string calldata _kalamangId,
        bool _isGasless
    ) external;

    function isKalamangGasless(
        string calldata _kalamangId
    ) external view returns (bool);

    function setKalamangRequireVoucher(
        string calldata _kalamangId,
        bool _requireVoucher
    ) external;

    function isVoucherRequired(
        string calldata _kalamangId
    ) external view returns (bool);

    function updateWhitelist(
        string calldata _kalamangId,
        bool _isRequireWhitelist,
        address[] calldata _whitelist,
        address _creator
    ) external;

    function addWhitelist(
        string calldata _kalamangId,
        address[] calldata _whitelist,
        address _creator
    ) external;

    function removeWhitelist(
        string calldata _kalamangId,
        address[] calldata _whitelist,
        address _creator
    ) external;
}
