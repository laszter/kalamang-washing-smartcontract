import hardhat from "hardhat";

/**
 * Inspect a kalamang's claim-routing state and (optionally) flip its
 * requireVoucher flag — the on-chain switch that makes the frontend route a
 * MetaMask/OKX claim through /api/voucher instead of a direct claimToken.
 *
 * Usage (inspect only):
 *   NETWORK=bkctestnet \
 *   STORAGE_ADDRESS=0xff419C714919954265cCf9Fa07bCfe892EBbb220 \
 *   CONTROLLER_ADDRESS=0x4A7513799fC1e7B3a91CFe90daE135DE98Bc9F8A \
 *   KALAMANG_ID=<the 64-char id> \
 *   npx hardhat run scripts/set_require_voucher.ts
 *
 * Add SET_REQUIRE_VOUCHER=true (or false) to actually toggle it. The signer
 * (DEPLOYER_PRIVATE_KEY for this network) must be the storage owner.
 */
async function main() {
  const networkName = process.env.NETWORK ?? "bkctestnet";
  const connection = await hardhat.network.connect(networkName);
  const { ethers } = connection;
  const [signer] = await ethers.getSigners();

  const storageAddr = process.env.STORAGE_ADDRESS;
  const controllerAddr = process.env.CONTROLLER_ADDRESS;
  const id = process.env.KALAMANG_ID;
  if (!storageAddr || !ethers.isAddress(storageAddr)) {
    throw new Error("Set STORAGE_ADDRESS to the deployed KalamangStorageV2 address");
  }
  if (!id) {
    throw new Error("Set KALAMANG_ID to the kalamang id to inspect");
  }

  const KalamangStorageV2 = await ethers.getContractFactory("KalamangStorageV2");
  const storage = KalamangStorageV2.attach(storageAddr).connect(signer) as any;

  console.log(`Network : ${networkName}`);
  console.log(`Signer  : ${signer.address}`);
  console.log(`Storage : ${storageAddr}`);
  console.log(`Kalamang: ${id}\n`);

  const info = await storage.getKalamangInfo(id);
  console.log("creator         :", info.creator);
  console.log("isActive        :", info.isActive);
  console.log("isGasless       :", info.isGasless);
  console.log("requireVoucher  :", info.requireVoucher);
  console.log("acceptedKYCLevel:", info.acceptedKYCLevel.toString());

  if (controllerAddr && ethers.isAddress(controllerAddr)) {
    const KalamangV2 = await ethers.getContractFactory("KalamangV2");
    const controller = KalamangV2.attach(controllerAddr).connect(signer) as any;
    console.log("claimIssuer     :", await controller.claimIssuer());
  }

  const want = process.env.SET_REQUIRE_VOUCHER;
  if (want === "true" || want === "false") {
    const target = want === "true";
    console.log(`\nSetting requireVoucher = ${target} ...`);
    await (await storage.setKalamangRequireVoucher(id, target)).wait();
    const after = await storage.getKalamangInfo(id);
    console.log("-> requireVoucher is now:", after.requireVoucher);
  } else {
    console.log("\n(inspect only — add SET_REQUIRE_VOUCHER=true to enable the voucher path)");
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
