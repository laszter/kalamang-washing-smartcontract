// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IKalaMangWashingStorage {
    struct KalaMang {
        address creator;
        uint256 totalTokens;
        uint256 claimedTokens;
        uint256 maxRecipients;
        uint256 claimedRecipients;
        bool isRandom;
        uint256 acceptedKYCLevel;
        mapping(address => bool) hasClaimed;
        bool isRequireWhitelist;
        mapping(address => bool) whitelist;
        address[] whitelistArray;
        bool isactive;
    }

    struct KalaMangInfo {
        address creator;
        string kalamangId;
        uint256 maxRecipients;
        uint256 claimedRecipients;
        bool isRandom;
        bool isRequireWhitelist;
        uint256 acceptedKYCLevel;
        uint256 totalTokens;
        uint256 remainingAmounts;
        bool isactive;
    }

    struct KalaMangClaimedHistory {
        address claimedAddress;
        uint claimedAmount;
    }

    struct KalaMangConfig {
        string kalamangId;
        address creator;
        uint256 totalTokens;
        uint256 maxRecipients;
        bool isRandom;
        uint256 acceptedKYCLevel;
        bool isRequireWhitelist;
        uint256[] remainingAmounts;
        address[] whitelist;
        bool isSdkCallerHelper;
    }

    function createKalamang(KalaMangConfig calldata _config) external;

    function claimToken(
        string calldata _kalamangId,
        uint256 _claimIndex,
        address _recipient
    ) external returns (uint256);

    function abortKalamang(
        string calldata _kalamangId,
        address _creator
    ) external returns (uint256);

    function getKalamangRemainingRecipients(
        string calldata _kalamangId
    ) external view returns (uint256);

    function updateWhitelist(
        string calldata _kalamangId,
        bool _isRequireWhitelist,
        address[] calldata _whitelist,
        address _creator
    ) external;
}
