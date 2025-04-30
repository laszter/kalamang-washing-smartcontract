const { ethers } = require("hardhat");

async function main() {

    const [deployer] = await ethers.getSigners();

    console.log(
        "Deploying contracts with the account:",
        deployer.address
    );

    const TheOasis = await ethers.getContractFactory("TheOasis");
    // const contract = TheOasis.attach("0x99a1ED0A60522610dFdaf9337b992911dCd4ea01");
    const contract = await TheOasis.deploy();

    console.log("Contract deployed at:", contract.target);

    await contract.waitForDeployment();

    const tx = await contract.fillWater({ value: ethers.parseEther("0.1") });
    await tx.wait();
    console.log("fillWater function called");

    // const tx2 = await contract.sendDrinkWater("0x51317321Ac7E96583010fD8d97F52eC0Bb833456");
    // await tx2.wait();
    // console.log("sendDrinkWater function called");

    // const tx3 = await contract.nextAvailableCallTime("0x51317321Ac7E96583010fD8d97F52eC0Bb833456");
    // console.log("nextAvailableCallTime function called", tx3.toString());

    // const tx4 = await contract.setWaitingTime(7 * 24 * 60 * 60);
    // await tx4.wait();
    // console.log("setWaitingTime function called");
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });