import { ethers } from "hardhat";

async function main() {
  // First deploy the Payment contract
  const payment = await ethers.deployContract("DroplinkedPayment", [], {
    value: 0,
  });
  await payment.waitForDeployment();
  console.log(`[ ✅ ] Payment Contract deployed to: ${await payment.getAddress()}`);
  const droplinked = await ethers.deployContract("Droplinked", [await payment.getAddress()], {
    value: 0,
  });
  await droplinked.waitForDeployment();
  console.log(
    `[ ✅ ] Droplinked deployed to: ${await droplinked.getAddress()} with fee: ${100}`
  );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
