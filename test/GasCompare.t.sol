// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "hardhat/console.sol";

// V1 stack
import "../Contracts/kalamangController.sol";
import "../Contracts/kalamangStorage.sol";
// V2 stack
import "../Contracts/kalamangV2.sol";
import "../Contracts/kalamangStorageV2.sol";
// shared
import "../Contracts/kalamangFeeStorage.sol";
import "./Mocks.sol";

// Apples-to-apples gas comparison of the SAME operation — the direct EOA
// claimToken(string) path — on the V1 stack vs the V2 stack.
//
// Both kalamangs are identical: non-random (equal split), no whitelist, KYC 0,
// same 1% fee, same total/maxRecipients. Only the contract implementation
// differs, so the gas delta is purely the V1 vs V2 refactor.
contract GasCompareTest {
    // ---- V1 ----
    KalamangController cV1;
    KalamangStorage sV1;
    KalamangFeeStorage feeV1;
    MockKYC kycV1;
    MockToken tokV1;
    string idV1;

    // ---- V2 ----
    KalamangV2 cV2;
    KalamangStorageV2 sV2;
    KalamangFeeStorage feeV2;
    MockKYC kycV2;
    MockToken tokV2;
    string idV2;

    uint256 constant TOTAL = 4_000_000;
    uint256 constant MAXR = 400;

    function setUp() public {
        // ---------- deploy V1 ----------
        kycV1 = new MockKYC();
        tokV1 = new MockToken();
        feeV1 = new KalamangFeeStorage();
        feeV1.setFee(100); // 1%
        sV1 = new KalamangStorage(address(0), address(feeV1), address(kycV1), address(0));
        cV1 = new KalamangController(address(0), address(sV1));
        sV1.setKalamangController(address(cV1));
        sV1.setIsAllowAllTokens(true);

        tokV1.mint(address(this), TOTAL);
        tokV1.approve(address(sV1), TOTAL);
        address[] memory wl1;
        cV1.createKalamang(address(tokV1), TOTAL, MAXR, false, 0, 0, 0, false, wl1, true);
        idV1 = sV1.getAllMyKalamangs()[0];

        // ---------- deploy V2 ----------
        kycV2 = new MockKYC();
        tokV2 = new MockToken();
        feeV2 = new KalamangFeeStorage();
        feeV2.setFee(100); // 1%
        sV2 = new KalamangStorageV2(address(0), address(feeV2), address(kycV2), address(0));
        cV2 = new KalamangV2(address(0), address(sV2));
        sV2.setKalamangController(address(cV2));
        sV2.setIsAllowAllTokens(true);

        tokV2.mint(address(this), TOTAL);
        tokV2.approve(address(sV2), TOTAL);
        address[] memory wl2;
        cV2.createKalamang(
            address(tokV2), TOTAL, MAXR, false, 0, 0, 0, false, wl2,
            true,  // isClaimable
            false  // requireVoucher = false -> direct claimToken path
        );
        idV2 = sV2.getAllMyKalamangs()[0];
    }

    // Measured in one tx with fully independent V1/V2 instances (no shared
    // storage between the two stacks), so the two claims don't warm each
    // other's slots. First claim on each kalamang = realistic cold "first
    // claimer" gas.
    function testCompareClaimGas() public {
        uint256 g0 = gasleft();
        cV1.claimToken(idV1);
        uint256 gasV1 = g0 - gasleft();

        uint256 g1 = gasleft();
        cV2.claimToken(idV2);
        uint256 gasV2 = g1 - gasleft();

        console.log("=========================================");
        console.log("claimToken(string) execution gas (first claimer)");
        console.log("V1 :", gasV1);
        console.log("V2 :", gasV2);
        if (gasV1 >= gasV2) {
            console.log("V2 saves :", gasV1 - gasV2);
            console.log("V2 saves pct (x100):", ((gasV1 - gasV2) * 10000) / gasV1);
        } else {
            console.log("V2 COSTS MORE :", gasV2 - gasV1);
        }
        console.log("=========================================");

        // sanity: both delivered the same amount (10000 - 1% = 9900)
        require(tokV1.balanceOf(address(this)) == 9_900, "V1 amount");
        require(tokV2.balanceOf(address(this)) == 9_900, "V2 amount");
    }

    // Also measure the SECOND claimer (a different address) — this is the
    // steady-state cost once per-kalamang slots are warm/initialised, which is
    // what most real claims look like.
    function testCompareSecondClaimGas() public {
        // first claim by this contract (warms shared per-kalamang slots)
        cV1.claimToken(idV1);
        cV2.claimToken(idV2);

        V1Claimer r1 = new V1Claimer(); // claims V1 via its own address
        SecondClaimer r2 = new SecondClaimer(); // claims V2 via its own address

        uint256 g0 = gasleft();
        r1.claimV1(cV1, idV1);
        uint256 gasV1 = g0 - gasleft();

        uint256 g1 = gasleft();
        r2.claimV2(cV2, idV2);
        uint256 gasV2 = g1 - gasleft();

        console.log("=========================================");
        console.log("claimToken(string) execution gas (2nd claimer, warm)");
        console.log("V1 :", gasV1);
        console.log("V2 :", gasV2);
        if (gasV1 >= gasV2) {
            console.log("V2 saves :", gasV1 - gasV2);
        } else {
            console.log("V2 COSTS MORE :", gasV2 - gasV1);
        }
        console.log("=========================================");
    }
}

// helper that claims a V1 kalamang using its own address as recipient
// (Recipient in Mocks.sol targets KalamangV2, so we need a V1 one)
contract V1Claimer {
    function claimV1(KalamangController c, string memory id) external {
        c.claimToken(id);
    }
}

contract SecondClaimer {
    function claimV2(KalamangV2 c, string memory id) external {
        c.claimToken(id);
    }
}
