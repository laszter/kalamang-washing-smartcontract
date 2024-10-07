import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";

const endpointUrl = "https://rpc-testnet.bitkubchain.io";
const privateKey = "";

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.19",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  networks: {
    bkctestnet: {
      url: endpointUrl,
      chainId: 25925,
      accounts: [privateKey],
    },
  },
};

export default config;
