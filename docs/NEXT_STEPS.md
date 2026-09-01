# Next Steps after M6

M4-M6 close the most important MVP gap: the actual RTL is now driven by randomized programs, dependencies are controlled by a scoreboard, and four independent warps can hide each other's stalls.

## M7 — vector load/store + banked telemetry scratchpad

Add:

- `VLOAD` and `VSTORE`;
- a small banked scratchpad;
- one address per lane;
- bank-conflict detection;
- contiguous/coalesced vs scattered access experiments.

Use synthetic racing telemetry frames as the trace source. Measure cycles per sample and bank conflicts.

## M8 — functional coverage + mutation testing

Track coverage bins for:

- opcode;
- warp id;
- mask population count;
- RAW/WAW/old-destination dependency;
- scoreboard block;
- WB forwarding;
- scheduler skip;
- signed/zero/boundary values.

Then intentionally break one mechanism at a time and measure how quickly the randomized environment catches it.

## M9 — deeper frontend / warp state

Replace the one-entry per-warp queue with a small instruction memory and per-warp PC. This is where “warp” becomes more than an execution context and starts behaving like an independently progressing instruction stream.

## M10 — divergence

Add a branch instruction and active-lane mask per warp. First implement a simple reconvergence model, then verify nested mask behaviour.

## Build order

Do memory before caches. Do coverage before adding lots of ISA. Every new architectural feature should introduce a new failure mode that the verification stack learns to detect.
