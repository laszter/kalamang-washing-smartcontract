// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../Contracts/kalamangV2.sol";
import "../Contracts/kalamangStorageV2.sol";
import "../Contracts/kalamangFeeStorage.sol";
import "./Mocks.sol";

contract KalamangFeeTest {
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
            false // requireVoucher: fee tests use the direct claim path
        );

        string[] memory ids = store.getAllMyKalamangs();
        return ids[0];
    }

    // Both V2 contracts expose a readable version number
    function testVersionIsTwo() public view {
        require(controller.VERSION() == 2, "controller version should be 2");
        require(store.VERSION() == 2, "storage version should be 2");
    }

    // Fee 1% of the gross claim amount: 4,000,000 / 400 = 10,000 per claim,
    // fee 100, recipient receives 9,900
    function testFeeIsOnePercentOfGrossClaim() public {
        string memory id = createKalamang(4_000_000, 400);

        Recipient recipient = new Recipient();
        recipient.claim(controller, id);

        require(
            token.balanceOf(address(recipient)) == 9_900,
            "recipient should receive 9900"
        );
        require(
            token.balanceOf(address(feeStorage)) == 100,
            "fee should be 100"
        );
    }

    // The fee is snapshotted at creation: changing the global fee later
    // must not affect an already-created kalamang
    function testFeeIsSnapshottedAtCreation() public {
        string memory id = createKalamang(4_000_000, 400);

        feeStorage.setFee(500); // 5%, after creation

        Recipient recipient = new Recipient();
        recipient.claim(controller, id);

        require(
            token.balanceOf(address(recipient)) == 9_900,
            "recipient should still pay the 1% fee from creation time"
        );

        // a kalamang created after the change uses the new global fee
        // (created from another address: the kalamang id is derived from
        // block.timestamp/number + msg.sender, so the same creator cannot
        // create twice in one block)
        Creator creator2 = new Creator();
        string memory id2 = creator2.create(
            controller,
            store,
            token,
            4_000_000,
            400
        );

        Recipient recipient2 = new Recipient();
        recipient2.claim(controller, id2);

        require(
            token.balanceOf(address(recipient2)) == 9_500,
            "new kalamang should use the new 5% fee"
        );
    }

    // Admin can override the fee of a specific kalamang, e.g. to zero
    // to make it fee-free
    function testAdminCanSetKalamangFeeToZero() public {
        string memory id = createKalamang(4_000_000, 400);

        store.setKalamangFee(id, 0);

        require(
            store.getKalamangInfo(id).fee == 0,
            "kalamang fee should be 0"
        );

        Recipient recipient = new Recipient();
        recipient.claim(controller, id);

        require(
            token.balanceOf(address(recipient)) == 10_000,
            "recipient should receive the full 10000 with no fee"
        );
        require(
            token.balanceOf(address(feeStorage)) == 0,
            "no fee should be collected"
        );
    }

    function testNonOwnerCannotSetKalamangFee() public {
        string memory id = createKalamang(4_000_000, 400);

        NonOwner nonOwner = new NonOwner();
        try nonOwner.trySetFee(store, id, 0) {
            revert("non-owner must not be able to set kalamang fee");
        } catch {}
    }

    function testCannotSetFeeAboveHundredPercent() public {
        string memory id = createKalamang(4_000_000, 400);

        try store.setKalamangFee(id, 10001) {
            revert("fee above 100% must be rejected");
        } catch {}
    }

    // All 400 claims drain the kalamang exactly: 9,900 x 400 to recipients,
    // 100 x 400 to the fee storage, nothing stuck in the storage contract
    function testAllClaimsDrainPotExactly() public {
        string memory id = createKalamang(4_000_000, 400);

        for (uint256 i = 0; i < 400; i++) {
            Recipient recipient = new Recipient();
            recipient.claim(controller, id);
            require(
                token.balanceOf(address(recipient)) == 9_900,
                "every recipient should receive exactly 9900"
            );
        }

        require(
            token.balanceOf(address(feeStorage)) == 40_000,
            "total fee should be exactly 40000"
        );
        require(
            token.balanceOf(address(store)) == 0,
            "storage should be fully drained"
        );
    }
}

