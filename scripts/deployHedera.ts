import { ethers } from "hardhat";

async function main() {
  // First deploy the Payment contract
  let wallet = (await ethers.getSigners())[0];


//   const payment = await ethers.deployContract("DroplinkedPayment" as any, []);
//   await payment.waitForDeployment();
//   console.log(payment);
//   console.log(`[ ✅ ] Payment Contract deployed to: ${await payment.getAddress()}`);
  const droplinked = await ethers.deployContract("Droplinked", ["0x209F79Aed051C6236f2DC3cA17EBc57d895ce059"], {
    value: 0,
  });
  await droplinked.waitForDeployment();
  console.log(droplinked);
  console.log(
    `[ ✅ ] Droplinked deployed to: ${await droplinked.getAddress()} with fee: ${100}`
  );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
