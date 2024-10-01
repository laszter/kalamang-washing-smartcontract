// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./interfaces/IKalaMangWashingStorage.sol";

contract KalaMangWashingControllerTestV2 {
    address public owner;
    address public sdkCallHelperRouter;
    IKalaMangWashingStorage public kalaMangWashingStorage;
    bool public isPaused;

    constructor(address _sdkCallHelperRouter, address _kalaMangWashingStorage) {
        sdkCallHelperRouter = _sdkCallHelperRouter;
        kalaMangWashingStorage = IKalaMangWashingStorage(
            _kalaMangWashingStorage
        );
        owner = msg.sender;
        isPaused = false;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    modifier onlySdkCallHelperRouter() {
        require(
            msg.sender == sdkCallHelperRouter,
            "Only sdkCallHelperRouter can call this function"
        );
        _;
    }

    modifier whenNotPaused() {
        require(!isPaused, "The contract pause create kalamang");
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
        IKalaMangWashingStorage.KalaMangInfo
            memory kalamangInfo = kalaMangWashingStorage.getKalamangInfo(
                _kalamangId
            );

        uint256 claimAmount = 0;

        if (!kalamangInfo.isactive) {
            return claimAmount;
        }

        if (kalamangInfo.claimedRecipients + 1 == kalamangInfo.maxRecipients) {
            claimAmount = kalamangInfo.remainingAmounts;
        } else if (kalamangInfo.isRandom) {
            // Distribute random amounts

            uint256 randomSetSize = 10;
            uint256[] memory randomSets = new uint256[](randomSetSize);

            for (uint256 j = 0; j < randomSetSize; j++) {
                uint256 randomFactor = uint256(
                    keccak256(
                        abi.encodePacked(
                            block.timestamp,
                            _recipient,
                            _kalamangId,
                            j
                        )
                    )
                );

                uint256 randomValueInRange = (randomFactor %
                    (kalamangInfo.maxRandom - kalamangInfo.minRandom + 1)) +
                    kalamangInfo.minRandom;

                randomSets[j] =
                    ((kalamangInfo.remainingAmounts * randomValueInRange) /
                        ((kalamangInfo.maxRecipients -
                            kalamangInfo.claimedRecipients) / 2)) /
                    100;
            }

            uint256 randomAmount = randomSets[
                (uint256(
                    keccak256(
                        abi.encodePacked(
                            block.timestamp,
                            _recipient,
                            _kalamangId,
                            block.number
                        )
                    )
                ) % randomSetSize)
            ];

            if (randomAmount > kalamangInfo.remainingAmounts) {
                randomAmount = kalamangInfo.remainingAmounts;
            }

            claimAmount = randomAmount;
        } else {
            // Distribute equal amounts
            claimAmount = kalamangInfo.totalTokens / kalamangInfo.maxRecipients;

            if (claimAmount > kalamangInfo.remainingAmounts) {
                claimAmount = kalamangInfo.remainingAmounts;
            }
        }

        return claimAmount;
    }

    function createKalamang(
        uint256 _totalTokens,
        uint256 _maxRecipients,
        bool _isRandom,
        uint256 _minRandom,
        uint256 _maxRandom,
        bool _isRequireWhitelist,
        uint256 _acceptedKYCLevel,
        address[] calldata _whitelist
    ) external whenNotPaused {
        require(_totalTokens > 0, "Total tokens must be greater than zero");
        require(_maxRecipients > 0, "Max recipients must be greater than zero");

        string memory kalamangId = generateRandomString(64);

        IKalaMangWashingStorage.KalaMangConfig
            memory kalamangConfig = IKalaMangWashingStorage.KalaMangConfig(
                kalamangId,
                msg.sender,
                _totalTokens,
                _maxRecipients,
                _isRandom,
                _minRandom,
                _maxRandom,
                _acceptedKYCLevel,
                _isRequireWhitelist,
                _whitelist,
                false
            );

        kalaMangWashingStorage.createKalamang(kalamangConfig);

        emit KalamangCreated(
            kalamangId,
            msg.sender,
            _totalTokens,
            _maxRecipients
        );
    }

    function createKalamangBySdk(
        uint256 _totalTokens,
        uint256 _maxRecipients,
        bool _isRandom,
        uint256 _minRandom,
        uint256 _maxRandom,
        bool _isRequireWhitelist,
        uint256 _acceptedKYCLevel,
        bytes memory _whitelist,
        address _bitkubNext
    ) external onlySdkCallHelperRouter whenNotPaused {
        require(_totalTokens > 0, "Total tokens must be greater than zero");
        require(_maxRecipients > 0, "Max recipients must be greater than zero");

        string memory kalamangId = generateRandomString(64);

        address[] memory _whitelistArr;
        (_whitelistArr) = abi.decode(_whitelist, (address[]));

        IKalaMangWashingStorage.KalaMangConfig
            memory kalamangConfig = IKalaMangWashingStorage.KalaMangConfig(
                kalamangId,
                _bitkubNext,
                _totalTokens,
                _maxRecipients,
                _isRandom,
                _minRandom,
                _maxRandom,
                _acceptedKYCLevel,
                _isRequireWhitelist,
                _whitelistArr,
                true
            );

        kalaMangWashingStorage.createKalamang(kalamangConfig);

        emit KalamangCreated(
            kalamangId,
            _bitkubNext,
            _totalTokens,
            _maxRecipients
        );
    }

    function claimToken(string calldata _kalamangId) external {
        uint256 claimAmount = getAmountToClaim(_kalamangId, msg.sender);

        uint256 amount = kalaMangWashingStorage.claimToken(
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

        uint256 amount = kalaMangWashingStorage.claimToken(
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
        kalaMangWashingStorage.updateWhitelist(
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

        kalaMangWashingStorage.updateWhitelist(
            _kalamangId,
            _isRequireWhitelist,
            _whitelistArr,
            _bitkubNext
        );
    }

    function abortKalamang(string calldata _kalamangId) external {
        uint256 amount = kalaMangWashingStorage.abortKalamang(
            _kalamangId,
            msg.sender
        );
        emit KalamangAborted(_kalamangId, amount);
    }

    function abortKalamangBySdk(
        string calldata _kalamangId,
        address _bitkubNext
    ) external onlySdkCallHelperRouter {
        uint256 amount = kalaMangWashingStorage.abortKalamang(
            _kalamangId,
            _bitkubNext
        );
        emit KalamangAborted(_kalamangId, amount);
    }

    function setPause(bool _isPaused) external onlyOwner {
        isPaused = _isPaused;
    }

    function setSdkCallHelperRouter(
        address _sdkCallHelperRouter
    ) external onlyOwner {
        sdkCallHelperRouter = _sdkCallHelperRouter;
    }

    function setKalaMangWashingStorage(
        address _kalaMangWashingStorage
    ) external onlyOwner {
        kalaMangWashingStorage = IKalaMangWashingStorage(
            _kalaMangWashingStorage
        );
    }
}
