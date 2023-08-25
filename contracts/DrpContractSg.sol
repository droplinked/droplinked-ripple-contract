// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

interface IPaymentContract {
    function batchPay(
        address[] memory _recipients,
        uint256[] memory _amounts
    ) external payable;
}

contract DroplinkedSg is ERC1155 {
    IPaymentContract internal immutable paymentContract;
    // Using price feed of chainlink to get the price of MATIC/USD without external source or centralization
    // Binance : 0x2514895c72f50D8bd4B4F9b1110F0D6bD2c97526
    // Polygon : 0xd0D5e3DB44DE05E9F294BB0a3bEEaF030DE24Ada
    AggregatorV3Interface internal immutable priceFeed =
        AggregatorV3Interface(0xd0D5e3DB44DE05E9F294BB0a3bEEaF030DE24Ada);

    // HeartBeat is used to check if the price is updated or not (in seconds)
    // Polygon : 120
    // Binance : 3600
    uint16 public heartBeat = 120;

    error oldPrice();

    // This error will be used when transfering money to an account fails
    error WeiTransferFailed(string message);

    // NotEnoughBalance indicates the msg.value is less than expected
    error NotEnoughBalance();

    // NotEnoughtTokens indicates the amount of tokens you want to purchase is more than actual existing
    error NotEnoughtTokens();

    // AccessDenied indicates you want to do a operation (CancelRequest or Accept) that you are not allowed to do
    error AccessDenied();

    // AlreadyRequested indicates that you have already requested for the tokenId you are trying to request to again
    error AlreadyRequested();

    // RequestNotfound is thrown when the caller is not the person that is needed to accept the request
    error RequestNotfound();

    // RequestIsAccepted is thrown when the publisher tries to cancel its request but the request is accepted beforehand
    error RequestIsAccepted();

    // The Mint would be emitted on Minting new product
    event Mint_event(uint256 tokenId, address recipient, uint256 amount);

    // PublishRequest would be emitted when a new publish request is made
    event PulishRequest(uint256 tokenId, uint256 requestId);

    // AcceptRequest would be emitted when the `approve_request` function is called
    event AcceptRequest(uint256 requestId);

    // Cancelequest would be emitted when the `cancel_request` function is called
    event CancelRequest(uint256 requestId);

    // DisapproveRequest would be emitted when the `disapprove` function is called
    event DisapproveRequest(uint256 requestId);

    // DirectBuy would be emitted when the `direct_buy` function is called and the transfer is successful
    event DirectBuy(uint256 price, address from, address to);

    // RecordedBuy would be emitted when the `buy_recorded` function is called and the transfers are successful
    event RecordedBuy(
        address producer,
        uint256 tokenId,
        uint256 shipping,
        uint256 tax,
        uint256 amount,
        address buyer
    );

    // AffiliateBuy would be emitted when the `buy_affiliate` function is called and the transfers are successful
    event AffiliateBuy(
        uint256 requestId,
        uint256 amount,
        uint256 shipping,
        uint256 tax,
        address buyer
    );

    event HeartBeatUpdated(uint16 newHeartBeat);

    event FeeUpdated(uint256 newFee);

    // NFTMetadata Struct
    struct NFTMetadata {
        string ipfsUrl;
        uint256 price;
        uint256 comission;
    }

    // Request struct
    struct Request {
        uint256 tokenId;
        address producer;
        address publisher;
        bool accepted;
    }

    enum ItemType {
        Direct,
        Recorded,
        Affiliate
    }

    struct BuyItem {
        ItemType itemType;
        uint amount;
        uint tokenId;
        uint requestId;
        uint price;
        uint shipping;
        uint tax;
        address recipient;
        address producer;
    }


    // TokenID => ItsTotalSupply
    mapping(uint256 => uint256) tokenCnts;

    // Keeps the record of the minted tokens
    uint256 public tokenCnt;

    // Keeps the record of the requests made
    uint256 public requestCnt;

    // Keeps record of the totalSupply of the contract
    uint256 public totalSupply;

    // The ratio Verifier for payment methods
    address public immutable owner;

    // The fee (*100) for Droplinked Account (ratioVerifier)
    uint256 public fee;

    // The signer for Droplinked Account
    address public immutable signer = 0xe74CFa92DB1c8863c0103CC10cF363008348098c;

    // TokenID => metadata
    mapping(uint256 => NFTMetadata) public metadatas;

    // RequestID => Request
    mapping(uint256 => Request) public requests;

    // ProducerAddress => ( PublisherAddress => (TokenID => isRequested) )
    mapping(address => mapping(address => mapping(uint256 => bool)))
        public isRequested;

    // HashOfMetadata => TokenID
    mapping(bytes32 => uint256) public tokenIdByHash;

    // PublisherAddress => ( RequestID => boolean )
    mapping(address => mapping(uint256 => bool)) public publishersRequests;

    // ProducerAddress => ( RequestID => boolean )
    mapping(address => mapping(uint256 => bool)) public producerRequests;

    // TokenID => string URI
    mapping(uint256 => string) uris;

    mapping(uint256 => mapping(address => uint256)) private holders;

    modifier onlyOwner() {
        if (msg.sender != owner) revert AccessDenied();
        _;
    }

    string public name = "DropNFT";
    string public symbol = "DropNFT";

    constructor(address _paymentContract) ERC1155("") {
        fee = 100;
        owner = msg.sender;
        paymentContract = IPaymentContract(_paymentContract);
    }

    function setHeartBeat(uint16 _heartbeat) public onlyOwner {
        heartBeat = _heartbeat;
        emit HeartBeatUpdated(_heartbeat);
    }

    function setFee(uint256 _fee) public onlyOwner {
        fee = _fee;
        emit FeeUpdated(_fee);
    }

    // Get the latest price of MATIC/USD with 8 digits shift ( the actual price is 1e-8 times the returned price )
    function getLatestPrice(
        uint80 roundId
    ) public view returns (uint256, uint256) {
        (, int256 price, , uint256 timestamp, ) = priceFeed.getRoundData(
            roundId
        );
        return (uint256(price), timestamp);
    }

    function uri(
        uint256 tokenId
    ) public view virtual override returns (string memory) {
        return uris[tokenId];
    }

    function mint(
        string calldata _uri,
        uint256 _price,
        uint256 _comission,
        uint256 amount
    ) public {
        // Calculate the metadataHash using its IPFS uri, price, and comission
        bytes32 metadata_hash = keccak256(abi.encode(_uri, _price, _comission));
        // Get the TokenID from `tokenIdByHash` by its calculated hash
        uint256 tokenId = tokenIdByHash[metadata_hash];
        // If NOT FOUND
        if (tokenId == 0) {
            // Create a new tokenID
            tokenId = tokenCnt + 1;
            tokenCnt++;
            metadatas[tokenId].ipfsUrl = _uri;
            metadatas[tokenId].price = _price;
            metadatas[tokenId].comission = _comission;
            holders[tokenId][msg.sender] = amount;
            tokenIdByHash[metadata_hash] = tokenId;
        }
        // If FOUND
        else {
            // Update the old tokenIds amount
            holders[tokenId][msg.sender] += amount;
        }
        totalSupply += amount;
        tokenCnts[tokenId] += amount;
        _mint(msg.sender, tokenId, amount, "");
        uris[tokenId] = _uri;
        emit URI(_uri, tokenId);
        emit Mint_event(tokenId, msg.sender, amount);
    }

    function publish_request(address producer_account, uint256 tokenId) public {
        if (isRequested[producer_account][msg.sender][tokenId])
            revert AlreadyRequested();
        // Create a new requestId
        uint256 requestId = requestCnt + 1;
        // Update the requests_cnt
        requestCnt++;
        // Create the request and add it to producer's incoming reqs, and publishers outgoing reqs
        requests[requestId].tokenId = tokenId;
        requests[requestId].producer = producer_account;
        requests[requestId].publisher = msg.sender;
        requests[requestId].accepted = false;
        publishersRequests[msg.sender][requestId] = true;
        producerRequests[producer_account][requestId] = true;
        isRequested[producer_account][msg.sender][tokenId] = true;
        emit PulishRequest(tokenId, requestId);
    }

    // The overloading of the safeBatchTransferFrom from ERC1155 to update contract variables
    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) public virtual override {
        require(
            from == _msgSender() || isApprovedForAll(from, _msgSender()),
            "ERC1155: caller is not token owner or approved"
        );
        _safeBatchTransferFrom(from, to, ids, amounts, data);
        for (uint256 i = 0; i < ids.length; ++i) {
            uint256 id = ids[i];
            uint256 amount = amounts[i];
            holders[id][from] -= amount;
            holders[id][to] += amount;
        }
    }

    // ERC1155 overloading to update the contracts state when the safeTrasnferFrom is called
    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) public virtual override {
        require(
            from == _msgSender() || isApprovedForAll(from, _msgSender()),
            "ERC1155: caller is not token owner or approved"
        );
        _safeTransferFrom(from, to, id, amount, data);
        holders[id][from] -= amount;
        holders[id][to] += amount;
    }

    function approve_request(uint256 requestId) public {
        if (!producerRequests[msg.sender][requestId]) revert RequestNotfound();
        requests[requestId].accepted = true;
        emit AcceptRequest(requestId);
    }

    function cancel_request(uint256 requestId) public {
        if (msg.sender != requests[requestId].publisher) revert AccessDenied();
        if (requests[requestId].accepted) revert RequestIsAccepted();
        // remove the request from producer's incoming requests, and from publisher's outgoing requests
        producerRequests[requests[requestId].producer][requestId] = false;
        publishersRequests[msg.sender][requestId] = false;
        // Also set the isRequested to false since we deleted the request
        isRequested[requests[requestId].producer][msg.sender][
            requests[requestId].tokenId
        ] = false;
        emit CancelRequest(requestId);
    }

    function disapprove(uint256 requestId) public {
        if (msg.sender != requests[requestId].producer) revert AccessDenied();
        // remove the request from producer's incoming requests, and from publisher's outgoing requests
        producerRequests[msg.sender][requestId] = false;
        publishersRequests[requests[requestId].publisher][requestId] = false;
        // Also set the isRequested to false since we deleted the request
        isRequested[requests[requestId].producer][
            requests[requestId].publisher
        ][requests[requestId].tokenId] = false;
        // And set the `accepted` property of the request to false
        requests[requestId].accepted = false;
        emit DisapproveRequest(requestId);
    }

    bool private isInPayment = false;
    function buy_batch(
        BuyItem[] calldata items,
        uint256 latestAnswer,
        uint256 timestamp,
        bytes memory signature
    ) public payable {
        if(isInPayment){
            return;
        }
        isInPayment = true;
        if (items.length > 20) revert(); //todo
        if (ECDSA.recover(ECDSA.toEthSignedMessageHash(keccak256(abi.encodePacked(latestAnswer, timestamp, address(this)))), signature) != signer)
            revert AccessDenied();
        if (
            block.timestamp > timestamp &&
            block.timestamp - timestamp > 2 * heartBeat
        ) revert oldPrice();
        address[] memory recivers = new address[](items.length);
        uint256[] memory amounts = new uint256[](items.length);
        uint reciversCnt = 0;
        uint amountsCnt = 0;
        for (uint256 i = 0; i < items.length; ++i) {
            if (items[i].itemType == ItemType.Direct) {
                uint price = items[i].price;
                address recipient = items[i].recipient;
                uint totalAmount = (price * 1e24) / latestAnswer;
                uint droplinkedShare = (totalAmount * fee) / 1e4;
                if (msg.value < totalAmount) revert NotEnoughBalance();
                emit DirectBuy(price, msg.sender, recipient);
                recivers[reciversCnt++] = owner;
                recivers[reciversCnt++] = recipient;
                amounts[amountsCnt++] = droplinkedShare;
                amounts[amountsCnt++] = totalAmount - droplinkedShare;
            } else if (items[i].itemType == ItemType.Recorded) {
                uint amount = items[i].amount;
                uint tokenId = items[i].tokenId;
                uint shipping = items[i].shipping;
                uint tax = items[i].tax;
                address producer = items[i].producer;
                uint product_price = (amount *
                    metadatas[tokenId].price *
                    1e24) / latestAnswer;
                uint totalPrice = product_price +
                    (((shipping + tax) * 1e24) / latestAnswer);
                if (msg.value < totalPrice) revert NotEnoughBalance();
                uint droplinked_share = (product_price * fee) / 1e4;
                uint producer_share = totalPrice - droplinked_share;
                holders[tokenId][msg.sender] += amount;
                holders[tokenId][producer] -= amount;
                emit RecordedBuy(
                    producer,
                    tokenId,
                    shipping,
                    tax,
                    amount,
                    msg.sender
                );
                recivers[reciversCnt++] = owner;
                recivers[reciversCnt++] = producer;
                amounts[amountsCnt++] = droplinked_share;
                amounts[amountsCnt++] = producer_share;
            } else if (items[i].itemType == ItemType.Affiliate) {
                this.buy_affiliate(items[i].requestId, items[i].amount, items[i].shipping, items[i].tax, latestAnswer, timestamp, signature);
            } else {
                revert();
            }
        }
        paymentContract.batchPay{value: msg.value}(recivers, amounts);
        isInPayment = false;
    }

    function direct_buy(
        uint256 price,
        address recipient,
        uint256 latestAnswer,
        uint256 timestamp,
        bytes memory signature
    ) public payable{
        if (ECDSA.recover(ECDSA.toEthSignedMessageHash(keccak256(abi.encodePacked(latestAnswer, timestamp, address(this)))), signature) != signer)
            revert AccessDenied();

        // Calculations
        // check the timestamp
        if (
            block.timestamp > timestamp &&
            block.timestamp - timestamp > 2 * heartBeat
        ) revert oldPrice();
        uint256 totalAmount = (price * 1e24) / latestAnswer;
        uint256 droplinkedShare = (totalAmount * fee) / 1e4;
        // check if the sended amount is more than the needed
        if (msg.value < totalAmount) revert NotEnoughBalance();
        emit DirectBuy(price, msg.sender, recipient);
        // Transfer money & checks
        address[] memory recivers = new address[](2);
        recivers[0] = owner;
        recivers[1] = recipient;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = droplinkedShare;
        amounts[1] = totalAmount - droplinkedShare;
        paymentContract.batchPay{value: msg.value}(recivers, amounts);
    }

    function buy_recorded(
        address producer,
        uint256 tokenId,
        uint256 shipping,
        uint256 tax,
        uint256 amount,
        uint256 latestAnswer,
        uint256 timestamp,
        bytes memory signature
    ) public payable {
        if (ECDSA.recover(ECDSA.toEthSignedMessageHash(keccak256(abi.encodePacked(latestAnswer, timestamp, address(this)))), signature) != signer)
            revert AccessDenied();
        if (holders[tokenId][producer] < amount) revert NotEnoughtTokens();
        // Calculations
        // check the timestamp
        if (
            block.timestamp > timestamp &&
            block.timestamp - timestamp > 2 * heartBeat
        ) revert oldPrice();
        uint256 product_price = (amount * metadatas[tokenId].price * 1e24) /
            latestAnswer;
        uint256 totalPrice = product_price +
            (((shipping + tax) * 1e24) / latestAnswer);
        if (msg.value < totalPrice) revert NotEnoughBalance();
        uint256 droplinked_share = (product_price * fee) / 1e4;
        uint256 producer_share = totalPrice - droplinked_share;
        // Transfer the product on the contract state
        holders[tokenId][msg.sender] += amount;
        holders[tokenId][producer] -= amount;
        emit RecordedBuy(producer, tokenId, shipping, tax, amount, msg.sender);
        // Actual money transfers & checks
        address[] memory recivers = new address[](2);
        recivers[0] = owner;
        recivers[1] = producer;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = droplinked_share;
        amounts[1] = producer_share;
        paymentContract.batchPay{value: msg.value}(recivers, amounts);
    }

    function buy_affiliate(
        uint256 requestId,
        uint256 amount,
        uint256 shipping,
        uint256 tax,
        uint256 latestAnswer,
        uint256 timestamp,
        bytes memory signature
    ) public payable {
        if (ECDSA.recover(ECDSA.toEthSignedMessageHash(keccak256(abi.encodePacked(latestAnswer, timestamp, address(this)))), signature) != signer)
            revert AccessDenied();
        // checks and calculations
        address prod = requests[requestId].producer;
        address publ = requests[requestId].publisher;
        uint256 tokenId = requests[requestId].tokenId;
        // check the timestamp
        if (
            block.timestamp > timestamp &&
            block.timestamp - timestamp > 2 * heartBeat
        ) revert oldPrice();
        uint256 product_price = (amount * metadatas[tokenId].price * 1e24) /
            latestAnswer;
        uint256 total_amount = product_price +
            (((shipping + tax) * 1e24) / latestAnswer);
        if (msg.value < total_amount) revert NotEnoughBalance();

        if (holders[tokenId][prod] < amount) revert NotEnoughtTokens();
        uint256 droplinked_share = (product_price * fee) / 1e4;
        uint256 publisher_share = ((product_price - droplinked_share) *
            metadatas[tokenId].comission) / 1e4;
        uint256 producer_share = total_amount -
            (droplinked_share + publisher_share);
        // Transfer on contract
        holders[tokenId][msg.sender] += amount;
        holders[tokenId][prod] -= amount;
        emit AffiliateBuy(requestId, amount, shipping, tax, msg.sender);
        // Money transfer
        address[] memory recivers = new address[](3);
        recivers[0] = owner;
        recivers[1] = prod;
        recivers[2] = publ;
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = droplinked_share;
        amounts[1] = producer_share;
        amounts[2] = publisher_share;
        paymentContract.batchPay{value: msg.value}(recivers, amounts);
    }

    // Returns the totalSupply of the contract
    function totalSupplyOf(uint256 id) public view returns (uint256) {
        return tokenCnts[id];
    }

    // Returns the balance of the address for the tokenId
    function balanceOf(
        address account,
        uint256 id
    ) public view override returns (uint256) {
        return holders[id][account];
    }
}
