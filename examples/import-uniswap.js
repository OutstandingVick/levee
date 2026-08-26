import { writeFile } from "node:fs/promises";
import { fetchUniswapV3History } from "../src/providers/uniswapSubgraph.js";
import { mandate } from "./scenario.js";

const poolIds = (process.env.UNISWAP_POOL_IDS ?? "").split(",").filter(Boolean);
if (poolIds.length === 0) throw new Error("UNISWAP_POOL_IDS is required");
const snapshots = await fetchUniswapV3History({
  endpoint: process.env.UNISWAP_SUBGRAPH_ENDPOINT,
  apiKey: process.env.THE_GRAPH_API_KEY,
  poolIds,
  startTimestamp: Number(process.env.START_TIMESTAMP ?? Math.floor(Date.now() / 1000) - 30 * 86_400),
  mandate,
});
const output = new URL("./history.base.json", import.meta.url);
await writeFile(output, `${JSON.stringify({ metadata: { source: "the-graph-uniswap-v3", network: "Base" }, snapshots }, null, 2)}\n`);
console.log(`Wrote ${snapshots.length} verified daily snapshots to ${output.pathname}`);
