import test from "node:test";
import assert from "node:assert/strict";
import { fetchUniswapV3History, normalizePoolDayData } from "../src/providers/uniswapSubgraph.js";
import { mandate } from "../examples/scenario.js";

const row = {
  date: "1787529600", tvlUSD: "10000000", volumeUSD: "2000000", feesUSD: "10000",
  token0Price: "4300", token1Price: "0.000232558",
  pool: { id: "0xabc", feeTier: "500", createdAtTimestamp: "1700000000",
    token0: { symbol: "WETH" }, token1: { symbol: "USDC" } },
};

test("normalizes subgraph daily rows and derives fee APY", () => {
  const snapshots = normalizePoolDayData([row], mandate);
  assert.equal(snapshots.length, 1);
  assert.equal(snapshots[0].pools[0].feeApyPercent, 36.5);
  assert.deepEqual(snapshots[0].pools[0].assets, ["WETH", "USDC"]);
});

test("provider requires credentials and does not silently fall back", async () => {
  await assert.rejects(() => fetchUniswapV3History({ endpoint: "x", poolIds: [] }), /THE_GRAPH_API_KEY/);
});

test("provider sends an authenticated GraphQL request", async () => {
  let request;
  const mockFetch = async (url, options) => {
    request = { url, options };
    return { ok: true, json: async () => ({ data: { poolDayDatas: [row] } }) };
  };
  const snapshots = await fetchUniswapV3History({
    endpoint: "https://example.test/subgraph", apiKey: "secret", poolIds: ["0xABC"],
    startTimestamp: 1, mandate,
  }, mockFetch);
  assert.equal(request.options.headers.authorization, "Bearer secret");
  assert.equal(snapshots.length, 1);
});
