# Levee

Levee is a mandate-driven liquidity allocation engine. An owner protects a
stable reserve, sets minimum yield and maximum stress-loss constraints, and
allows the engine to deploy only capital that fits those rules.

This repository currently contains Phase 1: deterministic pool evaluation,
portfolio stress simulation, allocation ranking, and explainable rejections.
It does not move funds.

## Run it

Requires Node.js 20 or newer and has no package dependencies.

```bash
npm test
npm run demo
npm run replay
```

To import verified Uniswap v3 Base daily data through The Graph:

```bash
THE_GRAPH_API_KEY=... \
UNISWAP_SUBGRAPH_ENDPOINT=https://gateway.thegraph.com/api/subgraphs/id/... \
UNISWAP_POOL_IDS=0xpool1,0xpool2 \
npm run import:uniswap
```

Credentials are required and never stored by Levee. The importer fails rather
than silently substituting synthetic data.

## Current model

- `net APY = gross APY - annualized gas drag - volatility penalty`
- Candidate pools must pass protocol, asset, TVL, and age allowlists/floors.
- A 50/50 constant-product LP is simulated over each mandate price shock.
- Concentrated positions use Uniswap-v3-style token amount equations and range
  boundaries to estimate capital and relative-underperformance loss.
- Stress loss is the larger of nominal capital loss and impermanent loss.
- Pool risk is scaled by its `riskyAssetWeight`.
- Aggregate loss is divided by total portfolio capital, so the stable reserve
  reduces whole-portfolio risk but is never considered deployable.
- Capital that cannot be allocated safely remains in reserve.
- Stale, conflicting, abnormal-TVL, and implausible-APY inputs fail closed.
- Every replayed decision records model/mandate versions and a SHA-256 input hash.

The model is deliberately conservative and transparent. Later phases can
replace synthetic pool inputs with Base data without changing the mandate or
decision output shapes.

## Layout

- `src/engine.js` — validation, IL/stress calculations, ranking and allocation
- `src/history.js` — snapshot validation, observed volatility, historical replay
- `examples/scenario.js` — deterministic hackathon scenario
- `examples/history.demo.json` — synthetic, clearly labeled replay fixture
- `examples/demo.js` — human-readable decision report
- `examples/replay.js` — historical replay report
- `test/engine.test.js` — safety invariants and rejection tests

## Phase 1 status

Phase 1 is feature-complete: normalized ingestion, provider adapter, observed
volatility, concentrated-liquidity stress, decomposed returns, fail-closed data
quality, historical replay metrics, decision provenance, and randomized safety
tests. Production calibration remains ongoing research rather than a software
completeness claim; no model output should be treated as financial advice.

## Phase 2 contracts

The in-progress Base/EVM safety layer lives in `contracts/`:

- `PolicyGuard` versions mandates and enforces asset, target, selector, reserve,
  concentration, expiry, cooldown, and projected-stress constraints.
- `MandateVault` holds tokens, delegates narrowly to one revocable agent, resets
  protocol allowances after each call, and supports pause plus owner recovery.
- Risk assessments are approved by a distinct attestor, bound to the chain,
  guard, mandate version, and full action, then consumed exactly once.

Run both phases' tests with:

```bash
forge test
npm test
```

These contracts are unaudited and must not hold production funds.
