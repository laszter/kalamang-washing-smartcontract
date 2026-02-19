import hardhat from "hardhat";

async function main() {
  const connection = await hardhat.network.connect();
  const { ethers } = connection;

  const [deployer] = await ethers.getSigners();

  console.log("Deploying contracts with the account:", deployer.address);

  const KalamangKAP20 = await ethers.getContractFactory("KalamangKAP20");
  const contract = await KalamangKAP20.deploy(
    "KalamangKAP20",
    "KK",
    "KalamangWashingHappyHours",
    18,
    "0x99166455989a868d5151799c716B3c1Be95D5114",
    "0x0Fe7773B44b2CFE4C9778616Db526359Ccda16bE",
    deployer.address,
    "0xe23fbAd6E1b18258AE1a964E17b1908e0690DdD4",
    4
  );

  console.log("Contract deployed at:", contract.target);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
