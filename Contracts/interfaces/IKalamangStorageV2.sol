// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IKalamangStorageV2 {
    struct Kalamang {
        address creator;
        string kalamangId;
        address tokenAddress;
        uint256 totalTokens;
        uint256 claimedTokens;
        uint256 maxRecipients;
        uint256 claimedRecipients;
        bool isRandom;
        uint256 minRandom;
        uint256 maxRandom;
        uint256 acceptedKYCLevel;
        bool isClaimable;
        uint256 fee;
        mapping(address => bool) hasClaimed;
        bool isRequireWhitelist;
        mapping(address => bool) whitelist;
        address[] whitelistArray;
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

    struct KalamangClaimedHistory {
        address claimedAddress;
        uint claimedAmount;
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

    function claimToken(
        string calldata _kalamangId,
        uint256 _claimTokens,
        address _recipient
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
