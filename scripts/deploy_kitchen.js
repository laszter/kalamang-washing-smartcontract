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

    const KalamangFeeStorage = await ethers.getContractFactory("KalamangFeeStorage");
    const feeContract = await KalamangFeeStorage.deploy();
    console.log("KalamangFeeStorage deployed at:", feeContract.target);

    const KalaMangWashingStorage = await ethers.getContractFactory("KalaMangWashingStorage");
    const storageContract = await KalaMangWashingStorage.deploy(ethers.ZeroAddress, feeContract.target, kycBitkubChainAddress, sdkTransferRouterAddress);
    console.log("KalaMangWashingStorage deployed at:", storageContract.target);

    const KalaMangWashingController = await ethers.getContractFactory("KalaMangWashingController");
    const controllerContract = await KalaMangWashingController.deploy(sdkCallHelperRouterAddress, storageContract.target);
    console.log("KalaMangWashingController deployed at:", controllerContract.target);

    await feeContract.waitForDeployment();
    await storageContract.waitForDeployment();
    await controllerContract.waitForDeployment();

    // Call setKalaMangController in KalaMangWashingStorageTestV2 to set the address of KalaMangWashingControllerTestV2
    const tx = await storageContract.setKalaMangController(controllerContract.target);
    await tx.wait();
    console.log("KalaMangWashingController address set in KalaMangWashingStorage");

    // const storageContract = KalaMangWashingStorage.attach("0x314600B9D6e5F79a9BeaA92395b34CEBaa4593d0");

    const tx2 = await storageContract.setAllowTokenAddress(kkubAddress, true);
    await tx2.wait();
    console.log("KKUB address set allow in KalaMangWashingStorage");

    const tx3 = await storageContract.setAllowTokenAddress("0x24B271FA748504241b20473249fcA14983C76D7d", true);
    await tx3.wait();
    console.log("KK address set allow in KalaMangWashingStorage");
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });