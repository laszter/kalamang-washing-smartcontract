const { ethers } = require("hardhat");

async function main() {

    const [deployer] = await ethers.getSigners();

    console.log(
        "Deploying contracts with the account:",
        deployer.address
    );

    const kycBitkubChainAddress = '0x409CF41ee862Df7024f289E9F2Ea2F5d0D7f3eb4';
    const sdkTransferRouterAddress = ethers.ZeroAddress;
    const kkubAddress = '0x67eBD850304c70d983B2d1b93ea79c7CD6c3F6b5';
    const sdkCallHelperRouterAddress = ethers.ZeroAddress;

    const KalamangFeeStorage = await ethers.getContractFactory("KalamangFeeStorage");
    const feeContract = await KalamangFeeStorage.deploy();
    console.log("KalamangFeeStorage deployed at:", feeContract.target);

    const KalamangStorage = await ethers.getContractFactory("KalamangStorage");
    const storageContract = await KalamangStorage.deploy(ethers.ZeroAddress, feeContract.target, kycBitkubChainAddress, sdkTransferRouterAddress);
    console.log("KalamangStorage deployed at:", storageContract.target);

    const KalamangController = await ethers.getContractFactory("KalamangController");
    const controllerContract = await KalamangController.deploy(sdkCallHelperRouterAddress, storageContract.target);
    console.log("KalamangController deployed at:", controllerContract.target);

    await feeContract.waitForDeployment();
    await storageContract.waitForDeployment();
    await controllerContract.waitForDeployment();

    // const storageContract = KalamangStorage.attach("0x68D8563Bfd2ebcDfB164Be94327cB6aEE3b16616");
    // const tx = await storageContract.setFeeStorage("0x99E0e6E1FD00B59746caaF84521d9c8B9e617334");
    // await tx.wait();
    // console.log("KalamangFeeStorage address set in KalamangStorage");

    // Call setKalaMangController in KalamangStorage to set the address of KalamangControllerTestV2
    const tx = await storageContract.setKalamangController(controllerContract.target);
    await tx.wait();
    console.log("KalamangController address set in KalamangStorage");


    const tx2 = await storageContract.setAllowTokenAddress(kkubAddress, true);
    await tx2.wait();
    console.log("KKUB address set allow in KalamangStorage");
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });