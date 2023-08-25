# Droplinked Solidity Contracts
This repository contains the droplinked's smart-contract source code for Ripple sidechain.

## Run tests
To run the tests on the contract you can run the following command
```bash
npx hardhat test test/test.ts
```

## Deploy
To deploy the contract to a network, follow these steps: 
1. Add your network to the `hardhat.config.ts` file, by simply looking at the exapmles that are there
2. Put your etherscan api key in the `etherscan` part
3. Run the following command to deploy :
```bash
npx hardhat run scripts/deploy.ts --network XRPSideChain
```

It would result in something like this
```bash
[ ✅ ] Payment Contract deployed to: 0x5b080b9dDAc04FAD620a92Cd3484767a38a10593
[ ✅ ] Droplinked deployed to: 0x34C4db97cE4cA2cce48757F85C954C5647124106 with fee: 100
```

## Contracts
You can find the contract source codes for 2 types of chains in the Contracts folder, 
- `DrpPayment.sol` file contains the payment contract source code
- `DrpContractSg.sol` file contains the Droplinked-contract source code for chains which ChainLink doen't have price feeds on them. Ripple sidechain is this kind at this time. (Also we have contract code for chains which support chainlink, you can check [here](https://github.com/droplinked/Droplinked-evm-contracts))
