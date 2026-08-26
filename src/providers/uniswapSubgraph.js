import { assessDataQuality } from "../quality.js";

const QUERY = `query PoolHistory($poolIds: [String!], $start: Int!, $first: Int!) {
  poolDayDatas(first: $first, orderBy: date, orderDirection: asc,
    where: { pool_in: $poolIds, date_gte: $start }) {
    date tvlUSD volumeUSD feesUSD token0Price token1Price
    pool { id feeTier createdAtTimestamp token0 { symbol } token1 { symbol } }
  }
}`;

export async function fetchUniswapV3History(config, fetchImpl = fetch) {
  if (!config.endpoint) throw new Error("UNISWAP_SUBGRAPH_ENDPOINT is required");
  if (!config.apiKey) throw new Error("THE_GRAPH_API_KEY is required");
  const response = await fetchImpl(config.endpoint, {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${config.apiKey}` },
    body: JSON.stringify({ query: QUERY, variables: {
      poolIds: config.poolIds.map((id) => id.toLowerCase()), start: config.startTimestamp, first: config.first ?? 1000,
    } }),
  });
  if (!response.ok) throw new Error(`Subgraph request failed with HTTP ${response.status}`);
  const payload = await response.json();
  if (payload.errors) throw new Error(`Subgraph error: ${payload.errors[0]?.message ?? "unknown"}`);
  return normalizePoolDayData(payload.data.poolDayDatas, config.mandate);
}

export function normalizePoolDayData(rows, mandate) {
  const byDate = new Map();
  const previousTvl = new Map();
  for (const row of rows) {
    const poolId = row.pool.id.toLowerCase();
    const tvlUsd = Number(row.tvlUSD);
    const feesUsd = Number(row.feesUSD);
    const feeApyPercent = tvlUsd > 0 ? feesUsd / tvlUsd * 365 * 100 : 0;
    const observedAt = new Date(Number(row.date) * 1000).toISOString();
    const pool = {
      id: poolId,
      protocol: "Uniswap v3",
      pair: `${row.pool.token0.symbol}/${row.pool.token1.symbol} ${Number(row.pool.feeTier) / 10_000}%`,
      assets: [row.pool.token0.symbol, row.pool.token1.symbol],
      spotPriceUsd: Number(row.token0Price),
      grossApyPercent: feeApyPercent,
      feeApyPercent,
      incentiveApyPercent: 0,
      annualGasCostUsd: 0,
      repositionCostUsd: 0,
      slippageBps: 0,
      tvlUsd,
      previousTvlUsd: previousTvl.get(poolId),
      ageDays: Math.floor((Number(row.date) - Number(row.pool.createdAtTimestamp)) / 86_400),
      riskyAssetWeight: 1,
      observedAt,
    };
    pool.dataQualityReasons = assessDataQuality(pool, mandate, new Date(observedAt));
    previousTvl.set(poolId, tvlUsd);
    const pools = byDate.get(observedAt) ?? [];
    pools.push(pool);
    byDate.set(observedAt, pools);
  }
  return [...byDate.entries()].sort(([a], [b]) => a.localeCompare(b))
    .map(([timestamp, pools]) => ({ timestamp, pools }));
}
