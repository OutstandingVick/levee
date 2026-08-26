import { execFileSync } from "node:child_process";

const required = [
  "BASE_SEPOLIA_RPC_URL", "PRIVATE_KEY", "OWNER_ADDRESS", "AGENT_ADDRESS",
  "RISK_ATTESTOR", "RESERVE_TOKEN", "RESERVE_USD_FEED", "UNISWAP_POSITION_MANAGER",
  "THE_GRAPH_API_KEY", "UNISWAP_SUBGRAPH_ENDPOINT", "UNISWAP_POOL_IDS",
];
const missing = required.filter((key) => !process.env[key]);
if (missing.length) {
  console.error(`Missing configuration: ${missing.join(", ")}`);
  process.exitCode = 1;
} else {
  const cast = (...args) => execFileSync("cast", args, { encoding: "utf8" }).trim();
  const rpc = process.env.BASE_SEPOLIA_RPC_URL;
  const chainId = cast("chain-id", "--rpc-url", rpc);
  if (chainId !== "84532") throw new Error(`wrong chain ID: ${chainId}`);
  for (const key of ["RESERVE_TOKEN", "RESERVE_USD_FEED", "UNISWAP_POSITION_MANAGER"]) {
    const code = cast("code", process.env[key], "--rpc-url", rpc);
    if (code === "0x") throw new Error(`${key} has no deployed bytecode`);
  }
  const roles = [process.env.OWNER_ADDRESS, process.env.AGENT_ADDRESS, process.env.RISK_ATTESTOR]
    .map((address) => address.toLowerCase());
  if (new Set(roles).size !== roles.length) throw new Error("owner, agent and attestor must be distinct");
  console.log("Levee preflight passed for Base Sepolia (84532)");
}
