async function main() {

    const [deployer] = await ethers.getSigners();

    console.log(
        "Deploying contracts with the account:",
        deployer.address
    );

    const Calculator = await ethers.getContractFactory("RandomRateExperiment");
    const contract = await Calculator.deploy();

    console.log("Contract deployed at:", contract.target);
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });