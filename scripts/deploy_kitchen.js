const { ethers } = require("hardhat");

async function main() {

    const [deployer] = await ethers.getSigners();

    console.log(
        "Deploying contracts with the account:",
        deployer.address
    );

    const kycBitkubChainAddress = '0x99166455989a868d5151799c716B3c1Be95D5114';
    const sdkTransferRouterAddress = '0x4Bf8a52cC1AE2F17F56b274adaF76B4A648eD155';
    const kkubAddress = '0x1BbE34CF9fd2E0669deEE34c68282ec1e6c44ab0';
    const sdkCallHelperRouterAddress = '0x96f4C25E4fEB02c8BCbAdb80d0088E0112F728Bc';

    const KalaMangWashingStorageTestV1 = await ethers.getContractFactory("KalaMangWashingStorageTestV1");
    const contract = await KalaMangWashingStorageTestV1.deploy(ethers.ZeroAddress, kycBitkubChainAddress, sdkTransferRouterAddress, kkubAddress);

    console.log("KalaMangWashingStorageTestV1 deployed at:", contract.target);

    const KalaMangWashingControllerTestV1 = await ethers.getContractFactory("KalaMangWashingControllerTestV1");
    const contract2 = await KalaMangWashingControllerTestV1.deploy(sdkCallHelperRouterAddress, contract.target);
    console.log("KalaMangWashingControllerTestV1 deployed at:", contract2.target);
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });