async function main() {

    const [deployer] = await ethers.getSigners();

    console.log(
        "Deploying contracts with the account:",
        deployer.address
    );

    const KalaMangWashingHappyHoursTestV5 = await ethers.getContractFactory("KalaMangWashingHappyHoursTestV5");
    const contract = await KalaMangWashingHappyHoursTestV5.deploy("0x1BbE34CF9fd2E0669deEE34c68282ec1e6c44ab0", "0x96f4C25E4fEB02c8BCbAdb80d0088E0112F728Bc", "0x4Bf8a52cC1AE2F17F56b274adaF76B4A648eD155");

    console.log("Contract deployed at:", contract.target);
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });