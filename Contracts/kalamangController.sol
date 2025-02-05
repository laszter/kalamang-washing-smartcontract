// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./interfaces/IKalamangStorage.sol";

contract KalamangController {
    address public owner;
    address public sdkCallHelperRouter;
    IKalamangStorage public kalamangStorage;
    bool public isPaused;
    uint256 public randomSetSize;

    constructor(address _sdkCallHelperRouter, address _kalamangStorage) {
        sdkCallHelperRouter = _sdkCallHelperRouter;
        kalamangStorage = IKalamangStorage(_kalamangStorage);
        owner = msg.sender;
        isPaused = false;
        randomSetSize = 5;
    }

    modifier onlyOwner() {
        require(
            msg.sender == owner,
            "KalamangController : Only owner can call this function"
        );
        _;
    }

    modifier onlySdkCallHelperRouter() {
        require(
            msg.sender == sdkCallHelperRouter,
            "KalamangController : Only sdkCallHelperRouter can call this function"
        );
        _;
    }

    modifier whenNotPaused() {
        require(
            !isPaused,
            "KalamangController : The contract pause create kalamang"
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
        IKalamangStorage.KalamangInfo memory kalamangInfo = kalamangStorage
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
        bool _isClaimable
    ) external whenNotPaused {
        require(
            _totalTokens > 0,
            "KalamangController : Total tokens must be greater than zero"
        );
        require(
            _maxRecipients > 0,
            "KalamangController : Max recipients must be greater than zero"
        );

        string memory kalamangId = generateRandomString(64);

        IKalamangStorage.KalamangConfig memory kalamangConfig = IKalamangStorage
            .KalamangConfig(
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
                false
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
            "KalamangController : Total tokens must be greater than zero"
        );
        require(
            _maxRecipients > 0,
            "KalamangController : Max recipients must be greater than zero"
        );

        string memory kalamangId = generateRandomString(64);

        address[] memory _whitelistArr;
        (_whitelistArr) = abi.decode(_whitelist, (address[]));

        IKalamangStorage.KalamangConfig memory kalamangConfig = IKalamangStorage
            .KalamangConfig(
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
                true
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

    function setSdkCallHelperRouter(
        address _sdkCallHelperRouter
    ) external onlyOwner {
        sdkCallHelperRouter = _sdkCallHelperRouter;
    }

    function setkalamangStorage(address _kalamangStorage) external onlyOwner {
        kalamangStorage = IKalamangStorage(_kalamangStorage);
    }
}
