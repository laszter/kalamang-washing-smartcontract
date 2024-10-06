const { ethers } = require("hardhat");

async function main() {

    const [deployer] = await ethers.getSigners();

    console.log(
        "Deploying contracts with the account:",
        deployer.address
    );

    const kycBitkubChainAddress = '0x99166455989a868d5151799c716B3c1Be95D5114';
    const sdkTransferRouterAddress = '0xAE7D33f10f09669A86e45BAA6342377aFf4cF728';
    const kkubAddress = '0x1BbE34CF9fd2E0669deEE34c68282ec1e6c44ab0';
    const sdkCallHelperRouterAddress = '0x96f4C25E4fEB02c8BCbAdb80d0088E0112F728Bc';

    const KalaMangWashingStorageTestV2 = await ethers.getContractFactory("KalaMangWashingStorageTestV2");
    const storageContract = await KalaMangWashingStorageTestV2.deploy(ethers.ZeroAddress, kycBitkubChainAddress, sdkTransferRouterAddress, kkubAddress);
    console.log("KalaMangWashingStorageTestV2 deployed at:", storageContract.target);

    const KalaMangWashingControllerTestV2 = await ethers.getContractFactory("KalaMangWashingControllerTestV2");
    const controllerContract = await KalaMangWashingControllerTestV2.deploy(sdkCallHelperRouterAddress, storageContract.target);
    console.log("KalaMangWashingControllerTestV2 deployed at:", controllerContract.target);

    await storageContract.waitForDeployment();
    await controllerContract.waitForDeployment();

    // Call setKalaMangController in KalaMangWashingStorageTestV2 to set the address of KalaMangWashingControllerTestV2
    const tx = await storageContract.setKalaMangController(controllerContract.target);
    await tx.wait();
    console.log("KalaMangWashingControllerTestV2 address set in KalaMangWashingStorageTestV2");
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });