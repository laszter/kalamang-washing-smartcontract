import type { HardhatUserConfig } from "hardhat/config";
import { configVariable } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox-mocha-ethers";

const config: HardhatUserConfig = {
  solidity: {
    profiles: {
      default: {
        version: "0.8.19",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    },
  },
  networks: {
    bkctestnet: {
      type: "http",
      url: "https://rpc-testnet.bitkubchain.io",
      chainId: 25925,
      accounts: [configVariable("DEPLOYER_PRIVATE_KEY")],
    },
    bkcmainnet: {
      type: "http",
      url: "https://rpc.bitkubchain.io",
      chainId: 96,
      accounts: [configVariable("DEPLOYER_PRIVATE_KEY")],
    },
  },
};

export default config;
