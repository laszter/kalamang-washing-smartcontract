// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IKalamangStorage {
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
        mapping(address => bool) hasClaimed;
        bool isRequireWhitelist;
        mapping(address => bool) whitelist;
        address[] whitelistArray;
        bool isActive;
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
        bool isActive;
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
