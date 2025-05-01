import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";

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
      url: "https://rpc-testnet.bitkubchain.io",
      chainId: 25925,
      accounts: [privateKey],
    },
    bkcmainnet: {
      url: "https://rpc.bitkubchain.io",
      chainId: 96,
      accounts: [privateKey],
    },
  },
};

export default config;
