# Threat model

## Protected assets and invariants

- Reserve value never falls below the owner's USD floor during normal actions.
- Only the delegated agent can request execution.
- Only approved assets, adapters, pools, and selectors can be reached.
- Pool concentration and projected stress loss remain within the mandate.
- A risk assessment is bound to one chain, guard, mandate version, state, action,
  and expiry and cannot be reused.
- The owner can pause, revoke the agent, and recover custody.

## Trust assumptions

- The owner and risk-attestor keys are uncompromised and independently operated.
- Configured price feeds are live and economically secure for the deposit cap.
- Approved Uniswap deployments and tokens match verified Base addresses.
- The Phase 1 model is conservative but is not an oracle of future performance.

## Defenses

- Stale/non-positive oracle prices fail closed.
- External calls use selector and target allowlists with temporary allowances.
- Reentrancy guards cover custody and adapter operations.
- Actual token balance deltas drive fee-token deposit and execution accounting.
- Position operations enforce pool, range, deadline, and minimum-output bounds.
- Version changes invalidate outstanding EIP-712 assessments.

## Known MVP limitations

- Contracts have not received an independent audit.
- Cross-asset portfolio valuation is intentionally limited to configured feeds.
- The agent's production RPC simulator, signer custody, and transaction relayer
  require deployment-specific implementations.
- Uniswap fork coverage requires operator-provided Base Sepolia configuration.
