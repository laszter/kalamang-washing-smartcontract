import hardhat from "hardhat";

/**
 * Deploys the Kalamang V2 system:
 *   KalamangFeeStorage  ->  KalamangStorageV2  ->  KalamangV2 (controller)
 *
 * Usage:
 *   NETWORK=bkctestnet npx hardhat run scripts/deploy_v2.ts
 *   NETWORK=bkcmainnet npx hardhat run scripts/deploy_v2.ts
 *
 * The network name must match a network in hardhat.config.ts, and that network
 * must have DEPLOYER_PRIVATE_KEY configured. Solidity target is EVM "paris"
 * (KUB has no PUSH0), which the project already compiles with on solc 0.8.19.
 *
 * Optional env overrides:
 *   KYC_ADDRESS, KKUB_ADDRESS, SDK_TRANSFER_ROUTER, SDK_CALL_HELPER_ROUTER
 *   FEE_STORAGE_ADDRESS  reuse an existing KalamangFeeStorage (e.g. the V1 fee
 *                        storage) instead of deploying a new one. The fee
 *                        storage is version-agnostic, so V1 and V2 can share it.
 *   KALAMANG_FEE_BPS   global fee in basis points (100 = 1%) snapshotted onto
 *                      every kalamang at creation. Omit to leave it at 0.
 *                      (Only settable here if the deployer owns the fee storage.)
 *   TRUSTED_RELAYER    address allowed to submit gasless claimTokenBySig calls.
 *   CLAIM_ISSUER       address whose signature authorizes claimTokenWithVoucher
 *                      (anti-Sybil Layer 3). Set it to the /api/voucher issuer
 *                      key's address. Needs no KUB balance.
 *   ALLOW_ALL_TOKENS   defaults to true (storage allows any token after
 *                      deploy). Set "false" to restrict to KKUB only.
 */

const ZERO = "0x0000000000000000000000000000000000000000";

// KUB infrastructure addresses. Testnet values are prefilled (same as the V1
// deploy script); mainnet must be supplied via env. Every entry can be
// overridden with the matching env var above.
const INFRA: Record<
  string,
  {
    kyc: string;
    kkub: string;
    sdkTransferRouter: string;
    sdkCallHelperRouter: string;
  }
> = {
  bkctestnet: {
    kyc: "0x99166455989a868d5151799c716B3c1Be95D5114",
    kkub: "0x1BbE34CF9fd2E0669deEE34c68282ec1e6c44ab0",
    sdkTransferRouter: ZERO,
    sdkCallHelperRouter: ZERO,
  },
  bkcmainnet: {
    kyc: "0x409CF41ee862Df7024f289E9F2Ea2F5d0D7f3eb4",
    kkub: "0x67eBD850304c70d983B2d1b93ea79c7CD6c3F6b5",
    sdkTransferRouter: ZERO,
    sdkCallHelperRouter: ZERO,
  },
};

async function main() {
  const networkName = process.env.NETWORK ?? "bkctestnet";
  const connection = await hardhat.network.create(networkName);
  const { ethers } = connection;

  const [deployer] = await ethers.getSigners();
  console.log(`Network : ${networkName}`);
  console.log(`Deployer: ${deployer.address}`);

  // Resolve infra addresses (env overrides win over the built-in defaults).
  const base = INFRA[networkName] ?? {
    kyc: "",
    kkub: "",
    sdkTransferRouter: ZERO,
    sdkCallHelperRouter: ZERO,
  };
  const kycAddress = process.env.KYC_ADDRESS ?? base.kyc;
  const kkubAddress = process.env.KKUB_ADDRESS ?? base.kkub;
  const sdkTransferRouterAddress =
    process.env.SDK_TRANSFER_ROUTER ?? base.sdkTransferRouter;
  const sdkCallHelperRouterAddress =
    process.env.SDK_CALL_HELPER_ROUTER ?? base.sdkCallHelperRouter;

  if (!ethers.isAddress(kycAddress) || kycAddress === ZERO) {
    throw new Error(
      `Missing KYC address for network "${networkName}". Set KYC_ADDRESS.`
    );
  }
  const allowAllTokens = process.env.ALLOW_ALL_TOKENS !== "false";
  if (!allowAllTokens && (!ethers.isAddress(kkubAddress) || kkubAddress === ZERO)) {
    throw new Error(
      `Missing KKUB address for network "${networkName}". Set KKUB_ADDRESS or ALLOW_ALL_TOKENS=true.`
    );
  }

  // The V2 contracts are not in the committed typechain output (types/
  // ethers-contracts), so getContractFactory returns untyped factories. Treat
  // the deployed instances as ethers.Contract, which resolves method calls
  // dynamically from the ABI at runtime.
  //
  // 1. Fee storage (holds the global fee that V2 snapshots at creation time).
  //    The fee storage is a passive, version-agnostic contract, so V2 can reuse
  //    an existing instance (e.g. the V1 fee storage) via FEE_STORAGE_ADDRESS
  //    instead of deploying a new one.
  const KalamangFeeStorage =
    await ethers.getContractFactory("KalamangFeeStorage");
  let feeContract: InstanceType<typeof ethers.Contract>;
  const existingFeeStorage: string = "0xe1C8FaD37e6CdeF517Ddf0D7a6EeFf3f6D278e03";
  if (existingFeeStorage) {
    if (!ethers.isAddress(existingFeeStorage) || existingFeeStorage === ZERO) {
      throw new Error("FEE_STORAGE_ADDRESS must be a valid non-zero address");
    }
    feeContract = KalamangFeeStorage.attach(existingFeeStorage) as unknown as
      InstanceType<typeof ethers.Contract>;
    console.log("KalamangFeeStorage : (reusing existing)", existingFeeStorage);
  } else {
    feeContract = (await KalamangFeeStorage.deploy()) as unknown as
      InstanceType<typeof ethers.Contract>;
    await feeContract.waitForDeployment();
    console.log("KalamangFeeStorage : (newly deployed)", feeContract.target);
  }

  // 2. Storage. Controller is wired in afterwards (circular dependency), so it
  //    is deployed with the zero address here.
  const KalamangStorageV2 =
    await ethers.getContractFactory("KalamangStorageV2");
  const storageContract = (await KalamangStorageV2.deploy(
    ZERO,
    feeContract.target,
    kycAddress,
    sdkTransferRouterAddress
  )) as unknown as InstanceType<typeof ethers.Contract>;
  await storageContract.waitForDeployment();
  console.log("KalamangStorageV2  :", storageContract.target);

  // 3. Controller (KalamangV2).
  const KalamangV2 = await ethers.getContractFactory("KalamangV2");
  const controllerContract = (await KalamangV2.deploy(
    sdkCallHelperRouterAddress,
    storageContract.target
  )) as unknown as InstanceType<typeof ethers.Contract>;
  await controllerContract.waitForDeployment();
  console.log("KalamangV2         :", controllerContract.target);

  // 4. Wire the controller into the storage.
  await (
    await storageContract.setKalamangController(controllerContract.target)
  ).wait();
  console.log("-> storage.setKalamangController done");

  // 5. Allow the token(s) that kalamangs may be created with.
  if (allowAllTokens) {
    await (await storageContract.setIsAllowAllTokens(true)).wait();
    console.log("-> storage.setIsAllowAllTokens(true) done");
  } else {
    await (
      await storageContract.setAllowTokenAddress(kkubAddress, true)
    ).wait();
    console.log(`-> storage.setAllowTokenAddress(${kkubAddress}) done`);
  }

  // 6. Optional: set the global fee (basis points). V2 snapshots this onto each
  //    kalamang at creation; the owner can still override per kalamang later
  //    with storage.setKalamangFee.
  if (process.env.KALAMANG_FEE_BPS !== undefined) {
    const feeBps = Number(process.env.KALAMANG_FEE_BPS);
    if (!Number.isInteger(feeBps) || feeBps < 0 || feeBps > 10000) {
      throw new Error("KALAMANG_FEE_BPS must be an integer between 0 and 10000");
    }
    await (await feeContract.setFee(feeBps)).wait();
    console.log(`-> feeStorage.setFee(${feeBps}) done`);
  }

  // 7. Optional: register a trusted relayer for gasless (signed) claims.
  const relayer = process.env.TRUSTED_RELAYER;
  if (relayer) {
    if (!ethers.isAddress(relayer) || relayer === ZERO) {
      throw new Error("TRUSTED_RELAYER must be a valid non-zero address");
    }
    await (
      await controllerContract.setTrustedRelayer(relayer, true)
    ).wait();
    console.log(`-> controller.setTrustedRelayer(${relayer}) done`);
  }

  // 8. Optional: register the anti-Sybil voucher issuer (claimTokenWithVoucher).
  const claimIssuer = process.env.CLAIM_ISSUER;
  if (claimIssuer) {
    if (!ethers.isAddress(claimIssuer) || claimIssuer === ZERO) {
      throw new Error("CLAIM_ISSUER must be a valid non-zero address");
    }
    await (await controllerContract.setClaimIssuer(claimIssuer)).wait();
    console.log(`-> controller.setClaimIssuer(${claimIssuer}) done`);
  }

  console.log("\nDeployment complete:");
  console.log(`  KalamangFeeStorage : ${feeContract.target}`);
  console.log(`  KalamangStorageV2  : ${storageContract.target}`);
  console.log(`  KalamangV2         : ${controllerContract.target}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
