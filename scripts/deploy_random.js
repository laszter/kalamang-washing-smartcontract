const { ethers } = require("hardhat");

async function main() {

    const [deployer] = await ethers.getSigners();

    console.log(
        "Deploying contracts with the account:",
        deployer.address
    );

    const Calculator = await ethers.getContractFactory("RandomRateExperiment");
    const contract = await Calculator.deploy();

    console.log("Contract deployed at:", contract.target);

    await contract.waitForDeployment();

    console.log(await contract.randomNormal(100, 1000));
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });