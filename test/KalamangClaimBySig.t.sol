// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../Contracts/kalamangV2.sol";
import "../Contracts/kalamangStorageV2.sol";
import "../Contracts/kalamangFeeStorage.sol";
import "./Mocks.sol";

interface Vm {
    function sign(
        uint256 privateKey,
        bytes32 digest
    ) external pure returns (uint8 v, bytes32 r, bytes32 s);

    function addr(uint256 privateKey) external pure returns (address);
}

contract RelayerCaller {
    function relay(
        KalamangV2 _controller,
        string memory _id,
        address _recipient,
        uint256 _deadline,
        bytes memory _signature
    ) external {
        _controller.claimTokenBySig(_id, _recipient, _deadline, _signature);
    }
}

contract KalamangClaimBySigTest {
    Vm constant vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    bytes32 private constant CLAIM_TYPEHASH =
        keccak256("Claim(string kalamangId,address recipient,uint256 deadline)");

    uint256 constant RECIPIENT_PK = 0xA11CE;

    KalamangV2 controller;
    KalamangStorageV2 store;
    KalamangFeeStorage feeStorage;
    MockKYC kyc;
    MockToken token;

    function setUp() public {
        kyc = new MockKYC();
        token = new MockToken();
        feeStorage = new KalamangFeeStorage();
        feeStorage.setFee(100); // 1%
        store = new KalamangStorageV2(
            address(0),
            address(feeStorage),
            address(kyc),
            address(0)
        );
        controller = new KalamangV2(address(0), address(store));
        store.setKalamangController(address(controller));
        store.setIsAllowAllTokens(true);

        // the test contract acts as the platform relayer
        controller.setTrustedRelayer(address(this), true);
    }

    function createKalamang(
        uint256 _totalTokens,
        uint256 _maxRecipients
    ) internal returns (string memory) {
        token.mint(address(this), _totalTokens);
        token.approve(address(store), _totalTokens);

        address[] memory emptyWhitelist;
        controller.createKalamang(
            address(token),
            _totalTokens,
            _maxRecipients,
            false, // isRandom
            0,
            0,
            0, // acceptedKYCLevel
            false, // isRequireWhitelist
            emptyWhitelist,
            true, // isClaimable
            false // requireVoucher (gasless path is not voucher-gated)
        );

        string[] memory ids = store.getAllMyKalamangs();
        // Flag the kalamang as gas-sponsored so the claimTokenBySig path is
        // allowed. The test contract deployed `store`, so it is the owner.
        store.setKalamangGasless(ids[0], true);
        return ids[0];
    }

    function signClaim(
        uint256 _privateKey,
        string memory _kalamangId,
        address _recipient,
        uint256 _deadline
    ) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(
            abi.encode(
                CLAIM_TYPEHASH,
                keccak256(bytes(_kalamangId)),
                _recipient,
                _deadline
            )
        );
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes("KalamangV2")),
                keccak256(bytes("1")),
                block.chainid,
                address(controller)
            )
        );
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    // The recipient only signs; the relayer submits the tx and the tokens
    // land on the recipient address (minus the kalamang fee)
    function testRelayerClaimsForSigner() public {
        string memory id = createKalamang(4_000_000, 400);
        address recipient = vm.addr(RECIPIENT_PK);
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory sig = signClaim(RECIPIENT_PK, id, recipient, deadline);
        controller.claimTokenBySig(id, recipient, deadline, sig);

        require(
            token.balanceOf(recipient) == 9_900,
            "recipient should receive 9900"
        );
        require(
            token.balanceOf(address(feeStorage)) == 100,
            "fee should be 100"
        );
        require(
            store.isClaimed(id, recipient),
            "recipient should be marked as claimed"
        );
    }

    function testRejectsUntrustedRelayer() public {
        string memory id = createKalamang(4_000_000, 400);
        address recipient = vm.addr(RECIPIENT_PK);
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = signClaim(RECIPIENT_PK, id, recipient, deadline);

        RelayerCaller untrusted = new RelayerCaller();
        try untrusted.relay(controller, id, recipient, deadline, sig) {
            revert("untrusted relayer must be rejected");
        } catch {}
    }

    function testRejectsExpiredSignature() public {
        string memory id = createKalamang(4_000_000, 400);
        address recipient = vm.addr(RECIPIENT_PK);
        uint256 deadline = block.timestamp - 1;
        bytes memory sig = signClaim(RECIPIENT_PK, id, recipient, deadline);

        try controller.claimTokenBySig(id, recipient, deadline, sig) {
            revert("expired signature must be rejected");
        } catch {}
    }

    // A signature from one key cannot claim for another recipient address
    function testRejectsSignerRecipientMismatch() public {
        string memory id = createKalamang(4_000_000, 400);
        address recipient = vm.addr(RECIPIENT_PK);
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory sig = signClaim(0xB0B, id, recipient, deadline);
        try controller.claimTokenBySig(id, recipient, deadline, sig) {
            revert("signature from another key must be rejected");
        } catch {}
    }

    // hasClaimed still guards the sig path: the same signature (or a fresh
    // one) cannot claim twice
    function testRejectsDoubleClaim() public {
        string memory id = createKalamang(4_000_000, 400);
        address recipient = vm.addr(RECIPIENT_PK);
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory sig = signClaim(RECIPIENT_PK, id, recipient, deadline);
        controller.claimTokenBySig(id, recipient, deadline, sig);

        try controller.claimTokenBySig(id, recipient, deadline, sig) {
            revert("second claim must be rejected");
        } catch {}

        require(
            token.balanceOf(recipient) == 9_900,
            "balance should be unchanged after the rejected second claim"
        );
    }

    // A signature is bound to its kalamangId and cannot be replayed on
    // another kalamang
    function testSignatureIsBoundToKalamang() public {
        string memory id1 = createKalamang(4_000_000, 400);

        Creator creator2 = new Creator();
        string memory id2 = creator2.create(
            controller,
            store,
            token,
            4_000_000,
            400
        );
        // Flag id2 gasless so the rejection below is due to signature binding,
        // not the gasless gate.
        store.setKalamangGasless(id2, true);

        address recipient = vm.addr(RECIPIENT_PK);
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = signClaim(RECIPIENT_PK, id1, recipient, deadline);

        try controller.claimTokenBySig(id2, recipient, deadline, sig) {
            revert("signature for another kalamang must be rejected");
        } catch {}
    }

    // A kalamang that has NOT been flagged gas-sponsored cannot be claimed
    // through the gasless (signature) path, even by a trusted relayer with a
    // valid signature.
    function testRejectsNonGaslessKalamang() public {
        // create a kalamang and explicitly leave it non-gasless
        token.mint(address(this), 4_000_000);
        token.approve(address(store), 4_000_000);
        address[] memory emptyWhitelist;
        controller.createKalamang(
            address(token),
            4_000_000,
            400,
            false,
            0,
            0,
            0,
            false,
            emptyWhitelist,
            true,
            false // requireVoucher
        );
        string[] memory ids = store.getAllMyKalamangs();
        string memory id = ids[0];

        address recipient = vm.addr(RECIPIENT_PK);
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = signClaim(RECIPIENT_PK, id, recipient, deadline);

        try controller.claimTokenBySig(id, recipient, deadline, sig) {
            revert("non-gasless kalamang must reject the sig claim");
        } catch {}

        require(
            token.balanceOf(recipient) == 0,
            "recipient must not receive tokens for a non-gasless kalamang"
        );

        // once flagged gasless, the same signature succeeds
        store.setKalamangGasless(id, true);
        controller.claimTokenBySig(id, recipient, deadline, sig);
        require(
            store.isClaimed(id, recipient),
            "recipient should be claimed after flagging gasless"
        );
    }

    function testOnlyOwnerCanSetTrustedRelayer() public {
        NonOwnerRelayerSetter nonOwner = new NonOwnerRelayerSetter();
        try nonOwner.trySet(controller, address(this), true) {
            revert("non-owner must not be able to set trusted relayer");
        } catch {}
    }
}

contract NonOwnerRelayerSetter {
    function trySet(
        KalamangV2 _controller,
        address _relayer,
        bool _isTrusted
    ) external {
        _controller.setTrustedRelayer(_relayer, _isTrusted);
    }
}
