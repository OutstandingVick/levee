import { readFile } from "node:fs/promises";

const path = process.argv[2];
if (!path) throw new Error("usage: node scripts/verify-deployment.js <deployment.json>");
const deployment = JSON.parse(await readFile(path, "utf8"));
if (deployment.chainId !== 84532) throw new Error("expected Base Sepolia chain ID 84532");
for (const [name, address] of Object.entries(deployment.contracts ?? {})) {
  if (!/^0x[0-9a-fA-F]{40}$/.test(address ?? "")) throw new Error(`${name} has no valid address`);
}
console.log(`Validated ${Object.keys(deployment.contracts).length} Base Sepolia addresses`);
