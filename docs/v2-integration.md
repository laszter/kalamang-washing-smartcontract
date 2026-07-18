# Kalamang V2 — Website Integration Guide

เอกสารสำหรับทีม frontend / backend ที่จะนำ Kalamang V2 ไปทำต่อบนเว็บ ครอบคลุมโครงสร้าง contract, การอ่าน/เขียนข้อมูล, ระบบ fee แบบใหม่, และ **gasless claim** (ผู้รับแค่เซ็นลายเซ็น ไม่ต้องมี KUB / ไม่ต้องเสีย gas)

> เครือข่าย: Bitkub Chain (KUB) — Mainnet chainId `96`, Testnet chainId `25925`
> Solidity `0.8.19`, EVM target `paris` (KUB ไม่รองรับ opcode `PUSH0`)

---

## สารบัญ

1. [ภาพรวม contract](#1-ภาพรวม-contract)
2. [Deployment addresses](#2-deployment-addresses)
3. [แนวคิดหลัก](#3-แนวคิดหลัก)
4. [Frontend: การอ่านข้อมูล](#4-frontend-การอ่านข้อมูล)
5. [Frontend: สร้าง Kalamang](#5-frontend-สร้าง-kalamang)
6. [Frontend: การ Claim (3 แบบ)](#6-frontend-การ-claim-3-แบบ)
7. [Gasless Claim: รายละเอียดเต็ม](#7-gasless-claim-รายละเอียดเต็ม)
8. [Backend: Relayer Service](#8-backend-relayer-service)
9. [Admin operations](#9-admin-operations)
10. [Events](#10-events)
11. [หมายเหตุเฉพาะ KUB](#11-หมายเหตุเฉพาะ-kub)
12. [Function reference](#12-function-reference)

---

## 1. ภาพรวม contract

Kalamang V2 ประกอบด้วย 3 contract:

| Contract | ไฟล์ | หน้าที่ |
|----------|------|--------|
| **KalamangV2** | `Contracts/kalamangV2.sol` | Controller — จุดที่ frontend/relayer เรียกใช้ทั้งหมด (สร้าง, claim, whitelist, abort) |
| **KalamangStorageV2** | `Contracts/kalamangStorageV2.sol` | เก็บ state ของ kalamang ทุกอัน + ถือ token + คิด fee + ฟังก์ชัน view สำหรับอ่านข้อมูล |
| **KalamangFeeStorage** | `Contracts/kalamangFeeStorage.sol` | เก็บ **global fee** ปัจจุบัน + เก็บ token ที่หักเป็น fee ไว้ให้ admin ถอน |

ทั้งสองตัวมี read parameter บอกเวอร์ชัน:

```solidity
KalamangV2.VERSION()        // => 2
KalamangStorageV2.VERSION() // => 2
```

**ทิศทางการเรียก:**
```
Frontend / Relayer ──▶ KalamangV2 (controller) ──▶ KalamangStorageV2 ──▶ KAP20 token
                                                          │
                                                          └──▶ KalamangFeeStorage (เก็บ fee)
```

Frontend อ่านข้อมูล view ได้จาก **KalamangStorageV2** โดยตรง แต่การเขียน (สร้าง/claim) ต้องผ่าน **KalamangV2** เท่านั้น (storage มี modifier `onlyKalamangController`)

---

## 2. Deployment addresses

> เติมค่าหลัง deploy (ดู `scripts/deploy_v2.ts`)

| Contract | Testnet (25925) | Mainnet (96) |
|----------|-----------------|--------------|
| KalamangV2 (controller) | `0x...` | `0x...` |
| KalamangStorageV2 | `0x...` | `0x...` |
| KalamangFeeStorage | `0x...` | `0x...` |

**Infra addresses ของ KUB ที่ระบบพึ่งพา** (ตั้งตอน deploy):

| | Testnet | หมายเหตุ |
|---|---------|---------|
| KYC (`IKYCBitkubChain`) | `0x409CF41ee862Df7024f289E9F2Ea2F5d0D7f3eb4` | ใช้เช็ค `kycsLevel` |
| KKUB | `0x67eBD850304c70d983B2d1b93ea79c7CD6c3F6b5` | token ตัวอย่างที่ allow |

**ABI:** เอาจาก `artifacts/Contracts/kalamangV2.sol/KalamangV2.json` และ `.../kalamangStorageV2.sol/KalamangStorageV2.json` (field `abi`) หลังรัน `npx hardhat compile`

---

## 3. แนวคิดหลัก

### 3.1 ระบบ Fee (เปลี่ยนใน V2)

- Fee เป็น **basis points**: `100 = 1%`, `250 = 2.5%`, สูงสุด `10000 = 100%`
- คิดจาก **ยอด claim ต่อครั้ง (gross)**: `feeAmount = claimAmount * fee / 10000` แล้วผู้รับได้ `claimAmount - feeAmount`
- **V2: fee ถูก snapshot ตอนสร้าง** — ตอน `createKalamang` ระบบดึงค่า global fee ปัจจุบันจาก `KalamangFeeStorage` มาเก็บไว้ที่ตัว kalamang เอง เปลี่ยน global fee ทีหลัง **ไม่กระทบ** kalamang ที่สร้างไปแล้ว
- **Admin ปรับ fee รายตัวได้** ผ่าน `KalamangStorageV2.setKalamangFee(kalamangId, fee)` เช่นตั้งเป็น `0` เพื่อทำ kalamang ปลอด fee
- อ่าน fee ของ kalamang ได้จาก `getKalamangInfo(id).fee`

> ตัวอย่าง: อยากให้ผู้รับได้ครบ 10,000 พอดี โดยเก็บ fee 1% → creator ต้องฝากเผื่อ fee: `10,100 × จำนวนคน` (เพราะ fee คิดจาก gross)

### 3.2 โหมดการแจก

- **Fixed** (`isRandom = false`): แต่ละคนได้เท่ากัน = `totalTokens / maxRecipients`
- **Random** (`isRandom = true`): สุ่มในช่วง โดยใช้ `minRandom`–`maxRandom` เป็นตัวคุมสัดส่วน (คนสุดท้ายได้ยอดที่เหลือทั้งหมด)

### 3.3 เงื่อนไขการ claim (ทุกโหมดเช็คเหมือนกัน)

ทุก path ของการ claim จะผ่านเงื่อนไขเดียวกันใน storage:
1. kalamang ต้อง active
2. ผู้รับต้องยังไม่เคย claim (`hasClaimed`) — **กัน claim ซ้ำ**
3. ถ้า `isRequireWhitelist` ผู้รับต้องอยู่ใน whitelist
4. `kycsLevel(ผู้รับ) >= acceptedKYCLevel`
5. ยังมีสิทธิ์เหลือ (`claimedRecipients < maxRecipients`)

---

## 4. Frontend: การอ่านข้อมูล

อ่านจาก **KalamangStorageV2** (view functions ฟรี ไม่เสีย gas)

### `getKalamangInfo(kalamangId)` → struct

ลำดับ field สำคัญตอน decode (struct `KalamangInfo`):

| # | field | type | หมายเหตุ |
|---|-------|------|---------|
| 0 | creator | address | |
| 1 | kalamangId | string | |
| 2 | tokenAddress | address | |
| 3 | tokenSymbol | string | |
| 4 | maxRecipients | uint256 | |
| 5 | claimedRecipients | uint256 | claim ไปแล้วกี่คน |
| 6 | isRandom | bool | |
| 7 | minRandom | uint256 | |
| 8 | maxRandom | uint256 | |
| 9 | acceptedKYCLevel | uint256 | |
| 10 | isRequireWhitelist | bool | |
| 11 | isClaimable | bool | |
| 12 | totalTokens | uint256 | |
| 13 | remainingAmounts | uint256 | เหลือให้แจกเท่าไหร่ |
| 14 | **fee** | uint256 | **ใหม่ใน V2** — fee ของ kalamang นี้ (bps) |
| 15 | isActive | bool | |

### View อื่น ๆ

```solidity
isClaimed(kalamangId, address) → bool      // เช็คว่า address นี้ claim แล้วหรือยัง
isClaimable(kalamangId)        → bool
isInWhitelist(kalamangId, addr)→ bool
getKalamangWhitelist(kalamangId) → address[]
getKalamangClaimedHistory(kalamangId) → {claimedAddress, claimedAmount}[]
getAllMyKalamangs()            → string[]  // ของ msg.sender
getKalamangsByPage(owner, page, pageLength) → string[]
```

```ts
// ethers v6 (read-only, ไม่ต้อง connect wallet ก็อ่านได้)
const storage = new ethers.Contract(STORAGE_V2_ADDRESS, STORAGE_V2_ABI, provider);
const info = await storage.getKalamangInfo(kalamangId);
console.log("fee (bps):", info.fee, "| เหลือ:", info.remainingAmounts);
const claimed = await storage.isClaimed(kalamangId, userAddress);
```

---

## 5. Frontend: สร้าง Kalamang

ต้อง **approve token ให้ storage ก่อน** แล้วเรียก `createKalamang` ที่ controller (token ถูกดึงจาก creator ตอนสร้าง)

```ts
const token = new ethers.Contract(TOKEN_ADDRESS, KAP20_ABI, signer);
await (await token.approve(STORAGE_V2_ADDRESS, totalTokens)).wait();

const controller = new ethers.Contract(CONTROLLER_ADDRESS, CONTROLLER_ABI, signer);
await (await controller.createKalamang(
  TOKEN_ADDRESS,   // _tokenAddress   (ต้องเป็น token ที่ถูก allow)
  totalTokens,     // _totalTokens
  maxRecipients,   // _maxRecipients
  false,           // _isRandom
  0,               // _minRandom
  0,               // _maxRandom
  0,               // _acceptedKYCLevel  (0 = ไม่ต้อง KYC)
  false,           // _isRequireWhitelist
  [],              // _whitelist (address[])
  true             // _isClaimable
)).wait();
```

- `kalamangId` ถูก generate ขึ้นเองใน contract (สุ่ม 64 ตัวอักษร) — อ่านได้จาก event `KalamangCreated` หรือ `getAllMyKalamangs()`
- fee ของ kalamang นี้ = global fee ณ ตอนที่เรียก (snapshot)

> **ข้อควรระวัง:** `kalamangId` สุ่มจาก `block.timestamp + block.number + msg.sender` — creator คนเดียวกันสร้าง 2 อันใน block เดียวกันจะได้ id ชนกันแล้ว revert `"Kalamang exists"` ฝั่ง UX ควรกันไม่ให้กดสร้างรัว ๆ ใน block เดียว

---

## 6. Frontend: การ Claim (3 แบบ)

| แบบ | ฟังก์ชัน | ใครส่ง tx | ใครจ่าย gas | wallet |
|-----|----------|-----------|-------------|--------|
| **Direct** | `claimToken(id)` | ผู้รับ | ผู้รับ | ทุก wallet (MetaMask ฯลฯ) |
| **Gasless (sig)** ⭐ | `claimTokenBySig(...)` | Relayer เรา | **เรา** | ทุก wallet ที่ sign EIP-712 ได้ |
| **Bitkub Next (SDK)** | `claimTokenBySdk(...)` | SDK CallHelper | Bitkub | เฉพาะ KUB Wallet |

### แบบ Direct

```ts
const controller = new ethers.Contract(CONTROLLER_ADDRESS, CONTROLLER_ABI, signer);
await (await controller.claimToken(kalamangId)).wait();
```

### แบบ Gasless — ดูหัวข้อถัดไป (นี่คือ feature หลักของ V2)

---

## 7. Gasless Claim: รายละเอียดเต็ม

**เป้าหมาย:** ผู้รับ **แค่เซ็นลายเซ็น** (ฟรี ไม่ใช่ transaction) → backend เรา relay tx และจ่าย gas แทน → token เข้ากระเป๋าผู้รับ โดยผู้รับไม่ต้องมี KUB เลย

```
ผู้รับ (ไม่มี KUB)          Backend เรา (มี KUB)              Chain
   │ 1. sign EIP-712 (ฟรี)      │                              │
   │──── signature ───────────▶│ 2. ตรวจ + rate limit          │
   │                           │ 3. relayer ส่ง tx จ่าย gas ──▶│ claimTokenBySig
   │                           │                              │ 4. ตรวจลายเซ็น + claim
   │◀───────────────── token เข้ากระเป๋าผู้รับ ──────────────────│
```

### 7.1 EIP-712 domain + types (ฝั่ง frontend)

> ⚠️ **สำคัญมาก:** domain `name` คือ **`"KalamangV2"`** — ค่านี้ hardcode ไว้ใน constructor ของ contract (`EIP712("KalamangV2", "1")`) ถ้าใส่ผิด ลายเซ็นจะ verify ไม่ผ่านและ tx จะ revert `"Invalid signature"`

```ts
const domain = {
  name: "KalamangV2",               // ⚠️ ต้องเป๊ะตรงกับ constructor ของ contract
  version: "1",
  chainId: 96,                      // 96 mainnet / 25925 testnet
  verifyingContract: CONTROLLER_ADDRESS, // address ของ KalamangV2
};

const types = {
  Claim: [
    { name: "kalamangId", type: "string"  },
    { name: "recipient",  type: "address" },
    { name: "deadline",   type: "uint256" },
  ],
};

const value = {
  kalamangId,
  recipient: userAddress,                       // ต้อง = คนเซ็น
  deadline: Math.floor(Date.now() / 1000) + 3600, // อีก 1 ชม. (วินาที)
};

// เซ็นในเบราว์เซอร์ — ฟรี ไม่ใช่ transaction ไม่ต้องมี KUB
const signature = await signer.signTypedData(domain, types, value);

// ส่ง { kalamangId, recipient, deadline, signature } ไป backend ผ่าน API ปกติ
```

### 7.2 Replay protection (ครบโดยไม่ต้องมี nonce)

| ความเสี่ยง | กันด้วย |
|-----------|--------|
| claim ซ้ำ kalamang เดิม | `hasClaimed` ใน storage (ของเดิม) |
| เอาลายเซ็นไปยิง kalamang อื่น | `kalamangId` อยู่ในลายเซ็น |
| ข้าม chain / ข้าม contract | domain ผูก `chainId` + `verifyingContract` |
| ลายเซ็นเก่าถูกใช้ทีหลัง | `deadline` |
| relayer/คนอื่นขโมย token | ไม่ได้ — token เข้า `recipient` ที่ฝังในลายเซ็นเสมอ |

### 7.3 ฝั่ง contract ทำอะไร

```solidity
function claimTokenBySig(string _kalamangId, address _recipient, uint256 _deadline, bytes _signature)
```
1. `require(trustedRelayers[msg.sender])` — เฉพาะ relayer ที่ลงทะเบียน
2. `require(block.timestamp <= _deadline)` — ยังไม่หมดอายุ
3. `ecrecover(digest, _signature) == _recipient` — ผู้รับเซ็นจริง
4. เข้า claim path เดิม (hasClaimed / whitelist / KYC / fee snapshot)

---

## 8. Backend: Relayer Service

Relayer คือ **backend service ธรรมดา ไม่ใช่ smart contract** — ถือ private key ของ wallet (EOA) ที่เติม KUB ไว้ แล้วเรียก contract เหมือน dapp ทั่วไป

### 8.1 ขั้นตอน

1. รับ `{ kalamangId, recipient, deadline, signature }` จาก frontend (REST/RPC)
2. **ตรวจก่อนจ่าย gas** (ประหยัด gas กับ tx ที่จะ revert แน่ ๆ):
   - rate limit / captcha ต่อ IP / ต่อ address (สำคัญ — เราจ่าย gas แทนทุกคน)
   - เช็ค off-chain: `isClaimed(id, recipient) == false`, kalamang ยัง active, ผ่าน whitelist/KYC
   - (แนะนำ) `recover` ลายเซ็นซ้ำที่ backend ก่อน ให้ตรงกับ recipient
3. Relayer wallet ส่ง tx: `controller.claimTokenBySig(kalamangId, recipient, deadline, signature)`
4. รอ receipt แล้วตอบ frontend

### 8.2 ตัวอย่าง (Node.js + ethers v6)

```ts
import { ethers } from "ethers";

const provider = new ethers.JsonRpcProvider("https://rpc.bitkubchain.io"); // mainnet
const relayer  = new ethers.Wallet(process.env.RELAYER_PRIVATE_KEY, provider);
const controller = new ethers.Contract(CONTROLLER_ADDRESS, CONTROLLER_ABI, relayer);

async function handleClaim({ kalamangId, recipient, deadline, signature }) {
  // 1) ตรวจซ้ำก่อน (กัน gas เสียเปล่า)
  const storage = new ethers.Contract(STORAGE_V2_ADDRESS, STORAGE_V2_ABI, provider);
  if (await storage.isClaimed(kalamangId, recipient)) throw new Error("already claimed");

  // 2) ⚠️ KUB ไม่รองรับ EIP-1559 → ต้องส่งแบบ legacy gasPrice
  const gasPrice = (await provider.getFeeData()).gasPrice;

  const tx = await controller.claimTokenBySig(
    kalamangId, recipient, deadline, signature,
    { gasPrice }               // legacy tx (type 0)
  );
  const receipt = await tx.wait();
  return receipt.hash;
}
```

### 8.3 สิ่งที่ต้องดูแล (ops)

- **เติม KUB ใน relayer wallet** + alert เมื่อยอดใกล้หมด (หมด = ไม่มีใคร claim ได้)
- **จัดคิว nonce** — wallet เดียวยิงหลาย tx พร้อมกัน nonce จะชนกัน ควร serialize หรือ manage nonce เอง
- **Legacy gas** — ส่ง `gasPrice` เสมอ อย่าใช้ `maxFeePerGas`/`maxPriorityFeePerGas` (EIP-1559 KUB ไม่รองรับ)
- **Rate limit / anti-sybil** — ทุก request = เงินเราจริง
- **ลงทะเบียน relayer address** ก่อน: `controller.setTrustedRelayer(RELAYER_ADDRESS, true)` (owner call, ครั้งเดียว)

---

## 9. Admin operations

ทุกอันเรียกจาก `owner` (deployer) — ไม่เปิดให้ frontend ทั่วไป

| งาน | contract | ฟังก์ชัน |
|-----|----------|---------|
| ตั้ง global fee (default ของ kalamang ที่จะสร้างใหม่) | FeeStorage | `setFee(bps)` |
| ปรับ fee เฉพาะ kalamang | StorageV2 | `setKalamangFee(id, bps)` |
| ลงทะเบียน/ถอด relayer | KalamangV2 | `setTrustedRelayer(addr, bool)` |
| allow token | StorageV2 | `setAllowTokenAddress(token, true)` / `setIsAllowAllTokens(true)` |
| ถอน fee ที่เก็บได้ | FeeStorage | `withdrawFee(tokenAddresses[])` |
| pause | StorageV2 / KalamangV2 | `setPause(bool)` |

```ts
// ทำ kalamang หนึ่งให้ปลอด fee
await storage.setKalamangFee(kalamangId, 0);
```

---

## 10. Events

ฟัง event เพื่อ sync UI / index ข้อมูล

```solidity
// KalamangV2 (controller)
event KalamangCreated(string kalamangId, address indexed creator, uint256 totalTokens, uint256 maxRecipients);
event TokenClaimed(string kalamangId, address indexed recipient, uint256 amount); // amount = ยอดหลังหัก fee
event KalamangAborted(string kalamangId, uint256 returnAmount);
event KalamangUnlocked(string kalamangId);
event TrustedRelayerUpdated(address indexed relayer, bool isTrusted);

// KalamangStorageV2
event KalamangFeeUpdated(string kalamangId, uint256 fee);

// KalamangFeeStorage
event ChangeFee(address indexed caller, uint256 fee);
event WithdrawFee(address indexed caller);
```

> `TokenClaimed.amount` คือยอด **สุทธิที่ผู้รับได้จริง** (หลังหัก fee แล้ว)

---

## 11. หมายเหตุเฉพาะ KUB

- **ไม่มี EIP-1559** — ทุก tx ต้องเป็น legacy (ส่ง `gasPrice`) ทั้ง relayer และ frontend flow
- **EVM = paris** — contract compile ด้วย solc 0.8.19 (ไม่มี PUSH0)
- **KYC** — `acceptedKYCLevel` เทียบกับ `kycsLevel(address)` ของ Bitkub; `0` = ไม่ต้อง KYC
- **Token ต้องเป็น KAP20** และถูก allow ใน storage ก่อนถึงจะสร้าง kalamang ด้วย token นั้นได้
- **Bitkub Next (KUB Wallet)** ใช้ path `*BySdk` แยกต่างหาก (มี `_bitkubNext` ต่อท้าย) — ดู NEXT SDK ของ KUB; gasless แบบลายเซ็น (หัวข้อ 7) ใช้กับ wallet ทั่วไป

---

## 12. Function reference

### KalamangV2 (controller) — write

```solidity
createKalamang(address tokenAddress, uint256 totalTokens, uint256 maxRecipients,
    bool isRandom, uint256 minRandom, uint256 maxRandom, uint256 acceptedKYCLevel,
    bool isRequireWhitelist, address[] whitelist, bool isClaimable)

claimToken(string kalamangId)                                    // direct
claimTokenBySig(string kalamangId, address recipient, uint256 deadline, bytes signature) // gasless
claimTokenBySdk(string kalamangId, address bitkubNext)           // Bitkub Next (onlySdkCallHelperRouter)

updateWhitelist(string kalamangId, bool isRequireWhitelist, address[] whitelist)
addWhitelist(string kalamangId, address[] whitelist)
removeWhitelist(string kalamangId, address[] whitelist)
abortKalamang(string kalamangId)
unlockKalamang(string kalamangId)

// admin (onlyOwner)
setTrustedRelayer(address relayer, bool isTrusted)
setPause(bool isPaused)
setSdkCallHelperRouter(address)
setkalamangStorage(address)

// read
VERSION() → uint256                    // = 2
trustedRelayers(address) → bool
```

### KalamangStorageV2 — read

```solidity
getKalamangInfo(string kalamangId) → KalamangInfo   // (ดู field ในหัวข้อ 4)
isClaimed(string kalamangId, address) → bool
isClaimable(string kalamangId) → bool
isInWhitelist(string kalamangId, address) → bool
getKalamangWhitelist(string kalamangId) → address[]
getKalamangClaimedHistory(string kalamangId) → KalamangClaimedHistory[]
getAllMyKalamangs() → string[]
getKalamangsByPage(address owner, uint256 page, uint256 pageLength) → string[]
VERSION() → uint256                    // = 2
```

### KalamangStorageV2 — write (admin, onlyOwner)

```solidity
setKalamangFee(string kalamangId, uint256 fee)   // fee เป็น bps, <= 10000
setAllowTokenAddress(address token, bool allow)
setIsAllowAllTokens(bool allow)
setPause(bool isPaused)
setFeeStorage(address) / setKycBitkubChain(address) / setSdkTransferRouter(address)
setKalamangController(address) / setOwner(address)
```

### KalamangFeeStorage

```solidity
getFee() → uint256                               // global fee ปัจจุบัน (bps)
setFee(uint256 fee)                              // onlyOwner
withdrawFee(address[] tokenAddresses)            // onlyOwner
```
