import hardhat from "hardhat";

async function main() {
  const connection = await hardhat.network.connect();
  const { ethers } = connection;

  const [deployer] = await ethers.getSigners();

  console.log("Deploying contracts with the account:", deployer.address);

  const TheOasis = await ethers.getContractFactory("TheOasis");
  const contract = await TheOasis.deploy();

  console.log("Contract deployed at:", contract.target);

  await contract.waitForDeployment();

  const tx = await contract.fillWater({ value: ethers.parseEther("0.005") });
  await tx.wait();
  console.log("fillWater function called");

  const tx2 = await contract.sendDrinkWater(
    "0x51317321Ac7E96583010fD8d97F52eC0Bb833456"
  );
  await tx2.wait();
  console.log("sendDrinkWater function called");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
