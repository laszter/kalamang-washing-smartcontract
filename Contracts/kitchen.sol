// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces/IKalaMangWashingStorage.sol";

contract KalaMangWashingControllerTestV1 {
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
                            block.difficulty,
                            msg.sender,
                            i
                        )
                    )
                ) % bytes(charset).length
            ];
        }

        return string(randomString);
    }

    function createKalamang(
        uint256 _totalTokens,
        uint256 _maxRecipients,
        bool _isRandom,
        bool _isRequireWhitelist,
        uint256 _acceptedKYCLevel,
        address[] calldata _whitelist
    ) external whenNotPaused {
        require(_totalTokens > 0, "Total tokens must be greater than zero");
        require(_maxRecipients > 0, "Max recipients must be greater than zero");

        string memory kalamangId = generateRandomString(64);

        uint256[] memory remainingAmounts = new uint256[](_maxRecipients);
        uint256 remainingTokens = _totalTokens;

        if (_isRandom) {
            // Distribute random amounts
            for (uint256 i = 0; i < _maxRecipients - 1; i++) {
                uint256 randomAmount = ((remainingTokens /
                    (_maxRecipients - i)) *
                    (uint256(
                        keccak256(
                            abi.encodePacked(block.timestamp, msg.sender, i)
                        )
                    ) % 100)) / 100;
                if (randomAmount > remainingTokens) {
                    randomAmount = remainingTokens;
                }

                remainingAmounts[i] = randomAmount;
                remainingTokens -= randomAmount;
            }
        } else {
            // Distribute equal amounts
            for (uint256 i = 0; i < _maxRecipients - 1; i++) {
                remainingAmounts[i] = _totalTokens / _maxRecipients;
                remainingTokens -= _totalTokens / _maxRecipients;
            }
        }

        remainingAmounts[_maxRecipients - 1] = remainingTokens;

        IKalaMangWashingStorage.KalaMangConfig
            memory kalamangConfig = IKalaMangWashingStorage.KalaMangConfig(
                kalamangId,
                msg.sender,
                _totalTokens,
                _maxRecipients,
                _isRandom,
                _acceptedKYCLevel,
                _isRequireWhitelist,
                remainingAmounts,
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
        bool _isRequireWhitelist,
        uint256 _acceptedKYCLevel,
        bytes memory _whitelist,
        address _bitkubNext
    ) external onlySdkCallHelperRouter whenNotPaused {
        require(_totalTokens > 0, "Total tokens must be greater than zero");
        require(_maxRecipients > 0, "Max recipients must be greater than zero");

        string memory kalamangId = generateRandomString(64);

        uint256[] memory remainingAmounts = new uint256[](_maxRecipients);
        uint256 remainingTokens = _totalTokens;

        if (_isRandom) {
            // Distribute random amounts
            for (uint256 i = 0; i < _maxRecipients - 1; i++) {
                uint256 randomAmount = ((remainingTokens /
                    (_maxRecipients - i)) *
                    (uint256(
                        keccak256(
                            abi.encodePacked(block.timestamp, msg.sender, i)
                        )
                    ) % 100)) / 100;
                if (randomAmount > remainingTokens) {
                    randomAmount = remainingTokens;
                }

                remainingAmounts[i] = randomAmount;
                remainingTokens -= randomAmount;
            }
        } else {
            // Distribute equal amounts
            for (uint256 i = 0; i < _maxRecipients - 1; i++) {
                remainingAmounts[i] = _totalTokens / _maxRecipients;
                remainingTokens -= _totalTokens / _maxRecipients;
            }
        }

        remainingAmounts[_maxRecipients - 1] = remainingTokens;

        address[] memory _whitelistArr;
        (_whitelistArr) = abi.decode(_whitelist, (address[]));

        IKalaMangWashingStorage.KalaMangConfig
            memory kalamangConfig = IKalaMangWashingStorage.KalaMangConfig(
                kalamangId,
                _bitkubNext,
                _totalTokens,
                _maxRecipients,
                _isRandom,
                _acceptedKYCLevel,
                _isRequireWhitelist,
                remainingAmounts,
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
        uint256 randomIndex = uint256(
            keccak256(
                abi.encodePacked(block.timestamp, msg.sender, _kalamangId)
            )
        ) % kalaMangWashingStorage.getKalamangRemainingRecipients(_kalamangId);

        uint256 amount = kalaMangWashingStorage.claimToken(
            _kalamangId,
            randomIndex,
            msg.sender
        );

        emit TokenClaimed(_kalamangId, msg.sender, amount);
    }

    function claimTokenBySdk(
        string calldata _kalamangId,
        address _bitkubNext
    ) external onlySdkCallHelperRouter {
        uint256 randomIndex = uint256(
            keccak256(
                abi.encodePacked(block.timestamp, _bitkubNext, _kalamangId)
            )
        ) % kalaMangWashingStorage.getKalamangRemainingRecipients(_kalamangId);

        uint256 amount = kalaMangWashingStorage.claimToken(
            _kalamangId,
            randomIndex,
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
}
