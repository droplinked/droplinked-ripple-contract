import { HardhatUserConfig } from "hardhat/config";
require("dotenv").config();
import "@nomicfoundation/hardhat-toolbox";

const config: HardhatUserConfig = {
  networks: {
    hardhat: {
    },
    XRPSideChain : {
      url: process.env.XRP_TESTNET_ENDPOINT,
      accounts: [
        process.env.XRP_TESTNET_OPERATOR_PRIVATE_KEY as string,
      ],
    }
  },
  solidity: {
    version: "0.8.18",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  etherscan:{
    apiKey: (process.env.POLYGONSCAN_API_KEY) as string
  }
};

export default config;
