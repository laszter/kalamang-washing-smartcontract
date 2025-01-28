async function main() {

    const [deployer] = await ethers.getSigners();

    console.log(
        "Deploying contracts with the account:",
        deployer.address
    );

    const StickyMan = await ethers.getContractFactory("KalamangWashing");
    // const contract = await StickyMan.deploy(
    //     "0x70E7702bE0D8Bbe746C2fd521F6260Af8Ec9b70A",
    //     "0x0Fe7773B44b2CFE4C9778616Db526359Ccda16bE",
    //     "0x99166455989a868d5151799c716B3c1Be95D5114",
    //     deployer.address,
    //     0
    // );

    // await contract.waitForDeployment();

    // console.log("Contract deployed at:", contract.target);

    const contract = StickyMan.attach("0xfDdF940B30929c2C5825607c7439f73B7FFb753c");

    const tx = await contract.mintWithMetadata(deployer.address, JSON.stringify({
        "description": "ตัวก่างมีปีก",
        "name": "Sticky Man Wing",
        "attributes": [
            {
                "trait_type": "Rarity",
                "value": "Rare"
            },
            {
                "trait_type": "Power",
                "value": "10",
            },
            {
                "trait_type": "Speed",
                "value": "30",
            },
            {
                "trait_type": "Defense",
                "value": "10",
            },
            {
                "trait_type": "HP",
                "value": "50",
            }
        ],
        "image": "https://bafybeibe7fghstg3zo2egbmp7vdxoxkaxo4bguxonktmqmlazrrdckw2ki.ipfs.dweb.link"
    }), 8);
    await tx.wait();
    console.log("NFT minted with metadata");
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });