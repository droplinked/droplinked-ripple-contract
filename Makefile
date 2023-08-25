deployPolygonMumbai:
	npx hardhat run --network polygon_mumbai scripts/deploy.ts
deployBinanceTestnet:
	npx hardhat run --network binance_testnet scripts/deploy.ts
deployHederaTestnet:
	npx hardhat run --network HederaTest scripts/deployHedera.ts