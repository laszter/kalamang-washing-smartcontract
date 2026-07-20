// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "hardhat/console.sol";
import "../Contracts/kalamangV2.sol";
import "../Contracts/kalamangStorageV2.sol";
import "../Contracts/kalamangController.sol";
import "../Contracts/kalamangStorage.sol";
import "../Contracts/kalamangFeeStorage.sol";
import "./Mocks.sol";

// Distinct msg.sender per claim -> each claimer has its own fresh
// hasClaimed + token-balance slots, so those cancel out and the ONLY thing
// that differs between "first" and "second" is the shared per-kalamang
// counters (claimedRecipients / claimedTokens / fee balance / [V1] history len).
contract ClaimerV2 {
    function claim(KalamangV2 c, string memory id) external { c.claimToken(id); }
}
contract ClaimerV1 {
    function claim(KalamangController c, string memory id) external { c.claimToken(id); }
}

abstract contract V2Base {
    KalamangV2 c; KalamangStorageV2 s; string id;
    function _deployV2() internal {
        MockKYC kyc = new MockKYC();
        MockToken tok = new MockToken();
        KalamangFeeStorage fee = new KalamangFeeStorage();
        fee.setFee(100);
        s = new KalamangStorageV2(address(0), address(fee), address(kyc), address(0));
        c = new KalamangV2(address(0), address(s));
        s.setKalamangController(address(c));
        s.setIsAllowAllTokens(true);
        tok.mint(address(this), 4_000_000);
        tok.approve(address(s), 4_000_000);
        address[] memory wl;
        c.createKalamang(address(tok), 4_000_000, 400, false, 0, 0, 0, false, wl, true, false);
        id = s.getAllMyKalamangs()[0];
    }
}

abstract contract V1Base {
    KalamangController c; KalamangStorage s; string id;
    function _deployV1() internal {
        MockKYC kyc = new MockKYC();
        MockToken tok = new MockToken();
        KalamangFeeStorage fee = new KalamangFeeStorage();
        fee.setFee(100);
        s = new KalamangStorage(address(0), address(fee), address(kyc), address(0));
        c = new KalamangController(address(0), address(s));
        s.setKalamangController(address(c));
        s.setIsAllowAllTokens(true);
        tok.mint(address(this), 4_000_000);
        tok.approve(address(s), 4_000_000);
        address[] memory wl;
        c.createKalamang(address(tok), 4_000_000, 400, false, 0, 0, 0, false, wl, true);
        id = s.getAllMyKalamangs()[0];
    }
}

// ---------------- V2 ----------------
contract V2First is V2Base {
    function setUp() public { _deployV2(); }
    function testGas() public {
        ClaimerV2 a = new ClaimerV2();
        uint256 g = gasleft();
        a.claim(c, id);
        console.log("V2 first  claim:", g - gasleft());
    }
}
contract V2Second is V2Base {
    function setUp() public {
        _deployV2();
        new ClaimerV2().claim(c, id); // 1 prior claim, persisted into state
    }
    function testGas() public {
        ClaimerV2 a = new ClaimerV2();
        uint256 g = gasleft();
        a.claim(c, id);
        console.log("V2 second claim:", g - gasleft());
    }
}

// ---------------- V1 ----------------
contract V1First is V1Base {
    function setUp() public { _deployV1(); }
    function testGas() public {
        ClaimerV1 a = new ClaimerV1();
        uint256 g = gasleft();
        a.claim(c, id);
        console.log("V1 first  claim:", g - gasleft());
    }
}
contract V1Second is V1Base {
    function setUp() public {
        _deployV1();
        new ClaimerV1().claim(c, id); // 1 prior claim, persisted into state
    }
    function testGas() public {
        ClaimerV1 a = new ClaimerV1();
        uint256 g = gasleft();
        a.claim(c, id);
        console.log("V1 second claim:", g - gasleft());
    }
}
