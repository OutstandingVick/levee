# Operations runbook

1. Verify every token, feed, Uniswap, and owner address independently.
2. Deploy on Base Sepolia and save addresses in `deployments/`.
3. Run the fork check and both test suites against the deployment commit.
4. Configure only the required asset, adapter, and function selectors.
5. Use separate agent and risk-attestor keys; keep ownership in a multisig.
6. Deposit test funds, execute a compliant action, and prove a forbidden action fails.
7. Exercise pause, agent revocation, position close, and emergency recovery.
8. Monitor oracle age, failed simulations, transaction reverts, reserve value,
   position concentration, and consumed assessment events.

After three consecutive operational failures, revoke the agent and investigate.
Never bypass a failed simulation or stale oracle to restore liveness.
