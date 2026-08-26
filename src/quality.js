export function assessDataQuality(pool, mandate, now = new Date()) {
  const reasons = [];
  const observedAt = Date.parse(pool.observedAt);
  const maxAgeMs = (mandate.maximumDataAgeMinutes ?? 1_440) * 60_000;
  if (!Number.isFinite(observedAt)) {
    reasons.push({ code: "MISSING_TIMESTAMP", detail: "Pool observation has no valid timestamp" });
  } else if (now.getTime() - observedAt > maxAgeMs) {
    reasons.push({ code: "STALE_DATA", detail: "Pool observation exceeds the data-age limit" });
  }
  if (Number.isFinite(pool.secondaryPriceUsd)) {
    const disagreement = Math.abs(pool.spotPriceUsd / pool.secondaryPriceUsd - 1) * 100;
    if (disagreement > (mandate.maximumPriceDisagreementPercent ?? 2)) {
      reasons.push({ code: "PRICE_DISAGREEMENT", detail: `${disagreement.toFixed(2)}% price-source disagreement` });
    }
  }
  if (pool.previousTvlUsd > 0) {
    const tvlChange = Math.abs(pool.tvlUsd / pool.previousTvlUsd - 1) * 100;
    if (tvlChange > (mandate.maximumDailyTvlChangePercent ?? 40)) {
      reasons.push({ code: "ABNORMAL_TVL_CHANGE", detail: `${tvlChange.toFixed(2)}% TVL change` });
    }
  }
  if (pool.feeApyPercent > (mandate.maximumPlausibleFeeApyPercent ?? 100)) {
    reasons.push({ code: "APY_OUTLIER", detail: `${pool.feeApyPercent.toFixed(2)}% fee APY is implausibly high` });
  }
  return reasons;
}
