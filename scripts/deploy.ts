import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();

  console.log("Deploying contracts with the account:", deployer.address);

  const Calculator = await ethers.getContractFactory("Calculator");
  const contract = await Calculator.deploy(
    "0x96f4C25E4fEB02c8BCbAdb80d0088E0112F728Bc"
  );

  console.log("Contract deployed at:", contract.target);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
