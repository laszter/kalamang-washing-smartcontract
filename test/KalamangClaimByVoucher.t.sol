// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../Contracts/kalamangV2.sol";
import "../Contracts/kalamangStorageV2.sol";
import "../Contracts/kalamangFeeStorage.sol";
import "./Mocks.sol";

interface VmV {
    function sign(
        uint256 privateKey,
        bytes32 digest
    ) external pure returns (uint8 v, bytes32 r, bytes32 s);

    function addr(uint256 privateKey) external pure returns (address);
}

// Calls claimTokenWithVoucher as a *different* msg.sender, to prove a voucher
// issued for one address cannot be redeemed by another caller.
contract VoucherClaimer {
    function claim(
        KalamangV2 _controller,
        string memory _id,
        uint256 _deadline,
        bytes memory _sig
    ) external {
        _controller.claimTokenWithVoucher(_id, _deadline, _sig);
    }
}

contract NonOwnerIssuerSetter {
    function trySet(KalamangV2 _controller, address _issuer) external {
        _controller.setClaimIssuer(_issuer);
    }
}

contract KalamangClaimByVoucherTest {
    VmV constant vm = VmV(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    bytes32 private constant VOUCHER_TYPEHASH =
        keccak256("ClaimVoucher(string kalamangId,address recipient,uint256 deadline)");

    // The server-side issuer key. Only vouchers signed by this key are accepted.
    uint256 constant ISSUER_PK = 0x1554E1;
    // An attacker key that is NOT the registered issuer.
    uint256 constant ATTACKER_PK = 0xBAD;

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

        // register the server issuer key
        controller.setClaimIssuer(vm.addr(ISSUER_PK));
    }

    // creates a kalamang owned by this test contract and flags it requireVoucher
    function createVoucherKalamang(
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
            true // requireVoucher
        );

        string[] memory ids = store.getAllMyKalamangs();
        return ids[0];
    }

    function signVoucher(
        uint256 _privateKey,
        string memory _kalamangId,
        address _recipient,
        uint256 _deadline
    ) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(
            abi.encode(
                VOUCHER_TYPEHASH,
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

    // A valid voucher signed by the issuer for this caller lets the direct claim
    // through; the caller pays their own gas and the tokens land on them.
    function testClaimWithValidVoucher() public {
        string memory id = createVoucherKalamang(4_000_000, 400);
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory voucher = signVoucher(ISSUER_PK, id, address(this), deadline);
        controller.claimTokenWithVoucher(id, deadline, voucher);

        require(
            token.balanceOf(address(this)) == 9_900,
            "claimer should receive 9900 (10000 - 1% fee)"
        );
        require(
            token.balanceOf(address(feeStorage)) == 100,
            "fee should be 100"
        );
        require(store.isClaimed(id, address(this)), "claimer should be marked claimed");
    }

    // A voucher signed by any key other than the registered issuer is rejected.
    function testRejectsForgedVoucher() public {
        string memory id = createVoucherKalamang(4_000_000, 400);
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory forged = signVoucher(ATTACKER_PK, id, address(this), deadline);
        try controller.claimTokenWithVoucher(id, deadline, forged) {
            revert("forged voucher must be rejected");
        } catch {}

        require(
            token.balanceOf(address(this)) == 0,
            "no tokens should move on a forged voucher"
        );
    }

    // The whole point: a direct claimToken on a requireVoucher kalamang reverts,
    // so a bot cannot bypass the server by calling the contract directly.
    function testRejectsDirectClaimWhenVoucherRequired() public {
        string memory id = createVoucherKalamang(4_000_000, 400);

        try controller.claimToken(id) {
            revert("direct claim must be rejected when voucher is required");
        } catch {}

        require(
            token.balanceOf(address(this)) == 0,
            "no tokens should move on a rejected direct claim"
        );
    }

    // An expired voucher is rejected even if correctly signed.
    function testRejectsExpiredVoucher() public {
        string memory id = createVoucherKalamang(4_000_000, 400);
        uint256 deadline = block.timestamp - 1;

        bytes memory voucher = signVoucher(ISSUER_PK, id, address(this), deadline);
        try controller.claimTokenWithVoucher(id, deadline, voucher) {
            revert("expired voucher must be rejected");
        } catch {}
    }

    // A voucher is bound to its recipient: a voucher issued for address(this)
    // cannot be redeemed by a different caller (msg.sender).
    function testVoucherBoundToRecipient() public {
        string memory id = createVoucherKalamang(4_000_000, 400);
        uint256 deadline = block.timestamp + 1 hours;

        // issuer signs a voucher whose recipient is this test contract
        bytes memory voucher = signVoucher(ISSUER_PK, id, address(this), deadline);

        // a different contract tries to redeem it (its own address becomes the
        // recipient in the digest, so recovery no longer matches the issuer)
        VoucherClaimer other = new VoucherClaimer();
        try other.claim(controller, id, deadline, voucher) {
            revert("voucher for another address must be rejected");
        } catch {}
    }

    // A voucher is bound to its kalamangId and cannot be replayed on another.
    function testVoucherBoundToKalamang() public {
        string memory id1 = createVoucherKalamang(4_000_000, 400);

        // Use a separate creator so the generated id differs (generateRandomString
        // is seeded by msg.sender, so two creates in one block by the same address
        // would collide).
        Creator creator2 = new Creator();
        string memory id2 = creator2.create(
            controller,
            store,
            token,
            4_000_000,
            400
        );
        store.setKalamangRequireVoucher(id2, true);

        uint256 deadline = block.timestamp + 1 hours;
        bytes memory voucher = signVoucher(ISSUER_PK, id1, address(this), deadline);
        try controller.claimTokenWithVoucher(id2, deadline, voucher) {
            revert("voucher for another kalamang must be rejected");
        } catch {}
    }

    // Rotating the issuer key instantly invalidates vouchers signed by the old
    // key — the emergency kill switch if the issuer key leaks.
    function testIssuerRotationInvalidatesOldVoucher() public {
        string memory id = createVoucherKalamang(4_000_000, 400);
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory oldVoucher = signVoucher(ISSUER_PK, id, address(this), deadline);

        // rotate to a new issuer key
        uint256 newIssuerPk = 0xC0FFEE;
        controller.setClaimIssuer(vm.addr(newIssuerPk));

        try controller.claimTokenWithVoucher(id, deadline, oldVoucher) {
            revert("voucher from the old issuer must be rejected after rotation");
        } catch {}

        // a voucher from the new issuer works
        bytes memory newVoucher = signVoucher(newIssuerPk, id, address(this), deadline);
        controller.claimTokenWithVoucher(id, deadline, newVoucher);
        require(store.isClaimed(id, address(this)), "claim with rotated issuer should succeed");
    }

    // When the issuer is unset (address(0)) voucher claims are disabled.
    function testRejectsWhenIssuerUnset() public {
        string memory id = createVoucherKalamang(4_000_000, 400);
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory voucher = signVoucher(ISSUER_PK, id, address(this), deadline);

        controller.setClaimIssuer(address(0));

        try controller.claimTokenWithVoucher(id, deadline, voucher) {
            revert("voucher claim must be rejected when issuer is unset");
        } catch {}
    }

    // Sanity: a kalamang that does NOT require a voucher is unaffected — the
    // normal direct claimToken path still works.
    function testDirectClaimStillWorksWithoutVoucher() public {
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
            false // requireVoucher: this test exercises the direct claim path
        );
        string[] memory ids = store.getAllMyKalamangs();
        string memory id = ids[0];

        controller.claimToken(id);
        require(store.isClaimed(id, address(this)), "normal direct claim should succeed");
    }

    function testOnlyOwnerCanSetClaimIssuer() public {
        NonOwnerIssuerSetter nonOwner = new NonOwnerIssuerSetter();
        try nonOwner.trySet(controller, address(nonOwner)) {
            revert("non-owner must not be able to set the claim issuer");
        } catch {}
    }
}
