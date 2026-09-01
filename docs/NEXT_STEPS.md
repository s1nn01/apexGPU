# Next Steps: turning the MVP into a standout project

The MVP already has enough moving pieces to discuss architecture and verification. The best way to extend it is **depth before breadth**.

## Milestone 1 — replay random programs in RTL

Highest priority.

Take the deterministic vector file produced by `verification/generate_vectors.py` and make the SystemVerilog testbench:

1. initialise all architectural vector registers through the debug port;
2. issue every encoded instruction;
3. wait for the final commit;
4. compare all registers against the expected final state;
5. dump the seed and VCD path on failure.

Then run 100+ seeds in CI.

**Why this matters:** this closes the loop between the golden model and the actual RTL.

## Milestone 2 — mutation testing

Add compile-time switches that intentionally break:

- source forwarding;
- masked destination forwarding;
- signed compare;
- VABSDELTA overflow behaviour.

Measure how many random programs are needed to catch each bug. Put the results in a small table in the README.

**Why this matters:** it shows that the verification environment is evaluated, not merely present.

## Milestone 3 — functional coverage

Track bins for:

- opcode;
- mask population count;
- `dst == src_a` / `dst == src_b`;
- forwarded A / B / old destination;
- positive/negative/zero operands;
- clamp boundary cases.

Cross the important dimensions and stop random regressions only once coverage targets are met.

## Milestone 4 — 4-warp scheduler

Introduce four execution contexts with:

- per-warp PC;
- per-warp lane mask;
- round-robin issue;
- simple scoreboard.

This is the point where the design begins to resemble a tiny GPU execution block rather than simply a vector ALU.

## Milestone 5 — vector memory + telemetry trace

Add vector load/store into a banked scratchpad. Generate synthetic racing telemetry traces and compare:

- scalar accesses;
- contiguous/coalesced vector accesses;
- deliberately scattered accesses.

Measure cycles per sample and bank conflicts.

## Suggested build order

Do **not** jump straight to caches or a graphics API. Finish the verification loop first, then add warps, then memory. Each step should create a new class of bugs that your test infrastructure has to learn to detect.
