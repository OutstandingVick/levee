import test from "node:test";
import assert from "node:assert/strict";
import { LeveeAgent } from "../agent/service.js";
import { candidatePools, mandate } from "../examples/scenario.js";

test("agent performs observe-plan-simulate-attest-execute in order", async () => {
  const calls = [];
  const agent = new LeveeAgent({
    mandate,
    simulator: { simulate: async () => (calls.push("simulate"), { success: true }) },
    attestor: { attest: async () => (calls.push("attest"), { signature: "0x01" }) },
    executor: { execute: async () => (calls.push("execute"), { hash: "0x02" }) },
    clock: () => new Date("2026-08-26T12:00:00Z"),
  });
  const result = await agent.runCycle(candidatePools);
  assert.equal(result.status, "EXECUTED");
  assert.deepEqual(calls, ["simulate", "attest", "execute"]);
});

test("agent never attests or executes a failed simulation", async () => {
  let unsafeCall = false;
  const agent = new LeveeAgent({
    mandate,
    simulator: { simulate: async () => ({ success: false, reason: "slippage" }) },
    attestor: { attest: async () => { unsafeCall = true; } },
    executor: { execute: async () => { unsafeCall = true; } },
  });
  const result = await agent.runCycle(candidatePools);
  assert.equal(result.status, "SIMULATION_REJECTED");
  assert.equal(unsafeCall, false);
});
