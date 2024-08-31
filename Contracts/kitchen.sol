// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IKYCBitkubChain {
    function kycsLevel(address _addr) external view returns (uint256);
}

interface ISdkTransferRouter {
    event KTokenAddrAdded(address indexed kTokenAddr);

    event KTokenAddrRemoved(address indexed kTokenAddr);

    event ApprovalKAP20(
        address indexed tokenAddr,
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    event ApprovalNFT(
        address indexed tokenAddr,
        address indexed owner,
        address indexed spender,
        bool approved
    );

    event TransferKAP20(
        address indexed tokenAddr,
        address indexed sender,
        address indexed recipient,
        uint256 amount
    );
    event TransferKAP721(
        address indexed tokenAddr,
        address indexed sender,
        address indexed recipient,
        uint256 tokenId
    );
    event TransferKAP1155(
        address indexed tokenAddr,
        address indexed sender,
        address indexed recipient,
        uint256 id,
        uint256 amount
    );

    function transferKAP20(
        address _tokenAddr,
        address _recipient,
        uint256 _amount,
        address _bitkubNext
    ) external;

    function transferKAP20(
        address _callerAddr,
        address _tokenAddr,
        address _recipient,
        uint256 _amount,
        address _bitkubNext
    ) external;

    function transferKAP721(
        address _tokenAddr,
        address _recipient,
        uint256 _tokenId,
        address _bitkubNext
    ) external;

    function transferKAP1155(
        address _tokenAddr,
        address _recipient,
        uint256 _id,
        uint256 _amount,
        address _bitkubNext
    ) external;
}

interface IKAP20 {
    function totalSupply() external view returns (uint256);

    function decimals() external view returns (uint8);

    function symbol() external view returns (string memory);

    function name() external view returns (string memory);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address recipient, uint256 amount) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function adminApprove(address owner, address spender, uint256 amount) external returns (bool);

    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    function adminTransfer(address sender, address recipient, uint256 amount) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);

    event Approval(address indexed owner, address indexed spender, uint256 value);
}

contract KalaMangWashingHappyHoursTestV5 {
    struct KalaMang {
        address creator;
        uint256 totalTokens;
        uint256 maxRecipients;
        uint256 claimedRecipients;
        bool isRandom;
        mapping(address => bool) hasClaimed;
        uint256[] remainingAmounts;
        bool isactive;
    }

    struct KalaMangInfo {
        address creator;
        string kalamangId;
        uint256 maxRecipients;
        uint256 claimedRecipients;
        uint256 totalTokens;
        uint256 remainingAmounts;
        bool isactive;
    }

    struct KalaMangClaimedHistory {
        address claimedAddress;
        uint claimedAmount;
    }

    mapping(string => KalaMang) private kalamangs;
    mapping(string => KalaMangClaimedHistory[]) private claimedHistory;
    mapping(string => bool) private kalamangsExists;
    mapping(address => uint256[]) private kalamangsOwner;
    string[] private kalamangIds;

    address public owner;
    address public sdkCallHelperRouter;
    uint256 public kalamangCount;
    address public tokenAddress;
    IKAP20 public token;
    ISdkTransferRouter public sdkTransferRouter;
    bool public pause;

    constructor(address _tokenAddress, address _sdkCallHelperRouter, address _sdkTransferRouter) {
        tokenAddress = _tokenAddress;
        token = IKAP20(_tokenAddress);
        sdkTransferRouter = ISdkTransferRouter(_sdkTransferRouter);
        sdkCallHelperRouter = _sdkCallHelperRouter;
        owner = msg.sender;
        pause = false;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    modifier onlySdkCallHelperRouter() {
        require(msg.sender == sdkCallHelperRouter, "Only sdkCallHelperRouter can call this function");
        _;
    }

    event KalamangCreated(string kalamangId, address indexed creator, uint256 totalTokens, uint256 maxRecipients);
    event TokenClaimed(string kalamangId, address indexed recipient, uint256 amount);
    event KalamangPasswordUpdated(string kalamangId);
    event KalamangAborted(string kalamangId, uint256 returnAmount);
    
    // Function to generate a random string
    function generateRandomString(uint256 _length) private view returns (string memory) {
        bytes memory randomString = new bytes(_length);
        string memory charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
        
        for (uint256 i = 0; i < _length; i++) {
            randomString[i] = bytes(charset)[uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty, msg.sender, i))) % bytes(charset).length];
        }

        return string(randomString);
    }

    // Function to generate a unique random string
    function generateUniqueRandomString(uint256 _length) private returns (string memory) {
        require(kalamangIds.length < 2**256 - 1, "All unique strings have been generated");

        string memory randomString = generateRandomString(_length);
        while (kalamangsExists[randomString]) {
            randomString = generateRandomString(_length);
        }

        kalamangsExists[randomString] = true;
        kalamangIds.push(randomString);

        return randomString;
    }

    function createKalamang(uint256 _totalTokens, uint256 _maxRecipients, bool _isRandom) external {
        require(!pause, "The contract pause create kalamang");
        require(_totalTokens > 0, "Total tokens must be greater than zero");
        require(_maxRecipients > 0, "Max recipients must be greater than zero");

        kalamangCount++;
        string memory kalamangId = generateUniqueRandomString(64);
        kalamangsOwner[msg.sender].push(kalamangCount - 1);
        kalamangIds[kalamangCount - 1] = kalamangId;

        KalaMang storage newKalamang = kalamangs[kalamangId];
        newKalamang.creator = msg.sender;
        newKalamang.totalTokens = _totalTokens;
        newKalamang.maxRecipients = _maxRecipients;
        newKalamang.claimedRecipients = 0;
        newKalamang.isactive = true;
        newKalamang.isRandom = _isRandom;

        uint256 remainingTokens = _totalTokens;

        if (_isRandom) {
            // Distribute random amounts
            for (uint256 i = 0; i < _maxRecipients - 1; i++) {
                uint256 randomAmount = (remainingTokens / (_maxRecipients - i)) * (uint256(keccak256(abi.encodePacked(block.timestamp, msg.sender, i))) % 100) / 100;
                if(randomAmount > remainingTokens) {
                    randomAmount = remainingTokens;
                }

                newKalamang.remainingAmounts.push(randomAmount);
                remainingTokens -= randomAmount;
            }
        } else {
            // Distribute equal amounts
            for (uint256 i = 0; i < _maxRecipients - 1; i++) {
                newKalamang.remainingAmounts.push(_totalTokens / _maxRecipients);
                remainingTokens -= _totalTokens / _maxRecipients;
            }
        }

        newKalamang.remainingAmounts.push(remainingTokens);

        require(token.transferFrom(msg.sender, address(this), _totalTokens), "Token transfer failed");

        emit KalamangCreated(kalamangId, msg.sender, _totalTokens, _maxRecipients);
    }

    function createKalamangBySdk(uint256 _totalTokens, uint256 _maxRecipients, bool _isRandom, address _bitkubNext) external onlySdkCallHelperRouter {
        require(!pause, "The contract pause create kalamang");
        require(_totalTokens > 0, "Total tokens must be greater than zero");
        require(_maxRecipients > 0, "Max recipients must be greater than zero");

        kalamangCount++;
        string memory kalamangId = generateUniqueRandomString(64);
        kalamangsOwner[_bitkubNext].push(kalamangCount - 1);
        kalamangIds[kalamangCount - 1] = kalamangId;

        KalaMang storage newKalamang = kalamangs[kalamangId];
        newKalamang.creator = _bitkubNext;
        newKalamang.totalTokens = _totalTokens;
        newKalamang.maxRecipients = _maxRecipients;
        newKalamang.claimedRecipients = 0;
        newKalamang.isactive = true;
        newKalamang.isRandom = _isRandom;

        uint256 remainingTokens = _totalTokens;

        if (_isRandom) {
            // Distribute random amounts
            for (uint256 i = 0; i < _maxRecipients - 1; i++) {
                uint256 randomAmount = (remainingTokens / (_maxRecipients - i)) * (uint256(keccak256(abi.encodePacked(block.timestamp, msg.sender, i))) % 100) / 100;
                if(randomAmount > remainingTokens) {
                    randomAmount = remainingTokens;
                }

                newKalamang.remainingAmounts.push(randomAmount);
                remainingTokens -= randomAmount;
            }
        } else {
            // Distribute equal amounts
            for (uint256 i = 0; i < _maxRecipients - 1; i++) {
                newKalamang.remainingAmounts.push(_totalTokens / _maxRecipients);
                remainingTokens -= _totalTokens / _maxRecipients;
            }
        }

        newKalamang.remainingAmounts.push(remainingTokens);

        sdkTransferRouter.transferKAP20(tokenAddress, address(this), _totalTokens, _bitkubNext);

        emit KalamangCreated(kalamangId, msg.sender, _totalTokens, _maxRecipients);
    }

    function claimToken(string calldata _kalamangId) external {
        KalaMang storage kalamang = kalamangs[_kalamangId];
        require(kalamang.creator != address(0), "Kalamang does not exist");
        require(!kalamang.hasClaimed[msg.sender], "You have already claimed");
        require(kalamang.claimedRecipients < kalamang.maxRecipients, "All tokens have been claimed");
        require(kalamang.isactive == true, "Already aborted");

        uint256 randomIndex = uint256(keccak256(abi.encodePacked(block.timestamp, msg.sender, kalamang.claimedRecipients))) % kalamang.remainingAmounts.length;
        uint256 amount = kalamang.remainingAmounts[randomIndex];

        kalamang.hasClaimed[msg.sender] = true;
        kalamang.claimedRecipients++;
        kalamang.remainingAmounts[randomIndex] = kalamang.remainingAmounts[kalamang.remainingAmounts.length - 1];
        kalamang.remainingAmounts.pop();

        KalaMangClaimedHistory[] storage claimeds = claimedHistory[_kalamangId];
        KalaMangClaimedHistory storage claimed = claimeds.push();
        claimed.claimedAddress = msg.sender;
        claimed.claimedAmount = amount;

        require(token.transfer(msg.sender, amount), "Token transfer failed");

        emit TokenClaimed(_kalamangId, msg.sender, amount);
    }

    function claimTokenBySdk(string calldata _kalamangId, address _bitkubNext) external onlySdkCallHelperRouter {
        KalaMang storage kalamang = kalamangs[_kalamangId];
        require(kalamang.creator != address(0), "Kalamang does not exist");
        require(!kalamang.hasClaimed[_bitkubNext], "You have already claimed");
        require(kalamang.claimedRecipients < kalamang.maxRecipients, "All tokens have been claimed");
        require(kalamang.isactive == true, "Already aborted");

        uint256 randomIndex = uint256(keccak256(abi.encodePacked(block.timestamp, _bitkubNext, kalamang.claimedRecipients))) % kalamang.remainingAmounts.length;
        uint256 amount = kalamang.remainingAmounts[randomIndex];

        kalamang.hasClaimed[_bitkubNext] = true;
        kalamang.claimedRecipients++;
        kalamang.remainingAmounts[randomIndex] = kalamang.remainingAmounts[kalamang.remainingAmounts.length - 1];
        kalamang.remainingAmounts.pop();

        KalaMangClaimedHistory[] storage claimeds = claimedHistory[_kalamangId];
        KalaMangClaimedHistory storage claimed = claimeds.push();
        claimed.claimedAddress = _bitkubNext;
        claimed.claimedAmount = amount;

        require(token.transfer(_bitkubNext, amount), "Token transfer failed");

        emit TokenClaimed(_kalamangId, _bitkubNext, amount);
    }

    function getKalamangClaimedHistory(string calldata _kalamangId) public view returns (KalaMangClaimedHistory[] memory) {
        KalaMang storage kalamang = kalamangs[_kalamangId];
        require(kalamang.creator != address(0), "Kalamang does not exist");

        return claimedHistory[_kalamangId];
    }

    function abortKalamang(string calldata _kalamangId) external {
        KalaMang storage kalamang = kalamangs[_kalamangId];
        require(kalamang.creator == msg.sender || owner == msg.sender, "Only creator or owner");
        require(kalamang.isactive == true, "Already aborted");

        uint256 amount = 0;
        for (uint256 i = 0; i < kalamang.remainingAmounts.length; i++) {
            amount += kalamang.remainingAmounts[i];
        }

        require(token.transfer(kalamang.creator, amount), "Token transfer failed");
        kalamang.isactive = false;

        emit KalamangAborted(_kalamangId, amount);
    }

    function abortKalamangBySdk(string calldata _kalamangId, address _bitkubNext) external onlySdkCallHelperRouter {
        KalaMang storage kalamang = kalamangs[_kalamangId];
        require(kalamang.creator == _bitkubNext, "Only creator");
        require(kalamang.isactive == true, "Already aborted");

        uint256 amount = 0;
        for (uint256 i = 0; i < kalamang.remainingAmounts.length; i++) {
            amount += kalamang.remainingAmounts[i];
        }

        require(token.transfer(kalamang.creator, amount), "Token transfer failed");
        kalamang.isactive = false;

        emit KalamangAborted(_kalamangId, amount);
    }

    function abortAllKalamang() external onlyOwner {
        for (uint256 i = 0; i < kalamangIds.length; i++){
            KalaMang storage kalamang = kalamangs[kalamangIds[i]];

            if (!kalamang.isactive) {
                continue ;
            }

            uint256 amount = 0;
            for (uint256 j = 0; j < kalamang.remainingAmounts.length; j++) {
                amount += kalamang.remainingAmounts[j];
            }

            require(token.transfer(kalamang.creator, amount), "Token transfer failed");
            kalamang.isactive = false;
        }
    }

    function getKalamangInfo(string calldata kalamangId) public view returns (KalaMangInfo memory) {
        KalaMang storage kalamang = kalamangs[kalamangId];
        require(kalamang.creator != address(0), "Kalamang does not exist");

        KalaMangInfo memory info;
        info.creator = kalamang.creator;
        info.kalamangId = kalamangId;
        info.maxRecipients = kalamang.maxRecipients;
        info.totalTokens = kalamang.totalTokens;
        info.claimedRecipients = kalamang.claimedRecipients;
        info.isactive = kalamang.isactive;
        info.remainingAmounts = 0;

        for (uint256 i = 0; i < kalamang.remainingAmounts.length; i++) {
            info.remainingAmounts += kalamang.remainingAmounts[i];
        }
        
        return info;
    }

    function getMyKalamangs() public view returns (string[] memory) {
        uint256 length = kalamangsOwner[msg.sender].length;
        string[] memory myKalamangIds = new string[](length);

        for (uint256 i = 0; i < length; i++) {
            myKalamangIds[i] = kalamangIds[kalamangsOwner[msg.sender][i]];
        }

        return myKalamangIds;
    }

    function setPause(bool value) external onlyOwner {        
        pause = value;
    }

    function isClaimed(string calldata kalamangId, address _target) public view returns (bool){
        KalaMang storage kalamang = kalamangs[kalamangId];
        return kalamang.creator != address(0) && kalamang.hasClaimed[_target];
    }

    function setSdkCallHelperRouter(address _sdkCallHelperRouter) external onlyOwner {
        sdkCallHelperRouter = _sdkCallHelperRouter;
    }

    function setSdkTransferRouter(address _sdkTransferRouter) external onlyOwner {
        sdkTransferRouter = ISdkTransferRouter(_sdkTransferRouter);
    }
}