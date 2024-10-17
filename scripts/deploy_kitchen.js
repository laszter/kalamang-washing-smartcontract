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

    const KalamangFeeStorage = await ethers.getContractFactory("KalamangFeeStorageTestV1");
    const feeContract = await KalamangFeeStorage.deploy(kkubAddress);
    console.log("KalamangFeeStorage deployed at:", feeContract.target);

    const KalaMangWashingStorage = await ethers.getContractFactory("KalaMangWashingStorageTestV2");
    const storageContract = await KalaMangWashingStorage.deploy("Kalamang_KKUB", ethers.ZeroAddress, feeContract.target, kycBitkubChainAddress, sdkTransferRouterAddress, kkubAddress);
    console.log("KalaMangWashingStorage deployed at:", storageContract.target);

    const KalaMangWashingController = await ethers.getContractFactory("KalaMangWashingControllerTestV2");
    const controllerContract = await KalaMangWashingController.deploy(sdkCallHelperRouterAddress, storageContract.target);
    console.log("KalaMangWashingController deployed at:", controllerContract.target);

    await feeContract.waitForDeployment();
    await storageContract.waitForDeployment();
    await controllerContract.waitForDeployment();

    // Call setKalaMangController in KalaMangWashingStorageTestV2 to set the address of KalaMangWashingControllerTestV2
    const tx = await storageContract.setKalaMangController(controllerContract.target);
    await tx.wait();
    console.log("KalaMangWashingController address set in KalaMangWashingStorage");
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });