import hardhat from "hardhat";

/**
 * Updates the `isAllowAllTokens` flag on an already-deployed KalamangStorageV2.
 *
 * Usage:
 *   STORAGE_ADDRESS=0x... NETWORK=bkctestnet npx hardhat run scripts/set_allow_all_tokens.ts
 *   STORAGE_ADDRESS=0x... ALLOW_ALL_TOKENS=false NETWORK=bkcmainnet npx hardhat run scripts/set_allow_all_tokens.ts
 *
 * Env:
 *   STORAGE_ADDRESS   (required) address of the deployed KalamangStorageV2.
 *   ALLOW_ALL_TOKENS  "false" to restrict to explicitly-allowed tokens only.
 *                     Any other value (or omitted) sets it to true.
 *   NETWORK           network name from hardhat.config.ts (default bkctestnet).
 *                     Must have DEPLOYER_PRIVATE_KEY configured; the signer must
 *                     be the storage owner or setIsAllowAllTokens reverts.
 */

const ZERO = "0x0000000000000000000000000000000000000000";

async function main() {
  const networkName = process.env.NETWORK ?? "bkctestnet";
  const connection = await hardhat.network.create(networkName);
  const { ethers } = connection;

  const storageAddress = process.env.STORAGE_ADDRESS;
  if (!storageAddress || !ethers.isAddress(storageAddress) || storageAddress === ZERO) {
    throw new Error("Set STORAGE_ADDRESS to the deployed KalamangStorageV2 address");
  }
  const allow = process.env.ALLOW_ALL_TOKENS !== "false";

  const [deployer] = await ethers.getSigners();
  console.log(`Network : ${networkName}`);
  console.log(`Signer  : ${deployer.address}`);
  console.log(`Storage : ${storageAddress}`);

  const KalamangStorageV2 =
    await ethers.getContractFactory("KalamangStorageV2");
  const storageContract = KalamangStorageV2.attach(storageAddress) as unknown as
    InstanceType<typeof ethers.Contract>;

  const owner: string = await storageContract.owner();
  const current: boolean = await storageContract.isAllowAllTokens();
  console.log(`Owner   : ${owner}`);
  console.log(`isAllowAllTokens : ${current} -> ${allow}`);

  if (owner.toLowerCase() !== deployer.address.toLowerCase()) {
    throw new Error(
      `Signer is not the storage owner (${owner}); setIsAllowAllTokens would revert`
    );
  }
  if (current === allow) {
    console.log("Already set to the desired value; nothing to do.");
    return;
  }

  await (await storageContract.setIsAllowAllTokens(allow)).wait();
  const updated: boolean = await storageContract.isAllowAllTokens();
  console.log(`-> storage.setIsAllowAllTokens(${allow}) done (now ${updated})`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
