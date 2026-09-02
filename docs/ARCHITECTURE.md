# ApexGPU Architecture Notes — M4 to M6

## Goal

ApexGPU is a small GPU-style execution block designed to expose **real verification and microarchitecture problems** without pretending to be a complete graphics processor. The M4-M6 version adds three important ideas to the original SIMD core:

1. randomized RTL differential verification;
2. scoreboarding around a two-stage execution pipeline;
3. four independent warp/context register files with round-robin scheduling.

The motivating workload remains racing telemetry: many sensor channels receive the same arithmetic/threshold operations, which maps naturally onto SIMD execution.

## Architectural state

ApexGPU now has four independent execution contexts (“warps”). Each warp owns:

- 16 architectural vector registers;
- 8 signed 32-bit lanes per vector register;
- its own scoreboard state;
- a one-entry instruction queue.

The warp id is encoded in instruction bits `[7:6]`. Two instructions can therefore use identical register numbers while referring to completely independent state.

## Frontend and scheduler

The host injects 64-bit instructions. Each instruction enters the one-entry queue for its encoded warp. The queues decouple host injection from execution enough for the scheduler to observe several warps at once.

A round-robin scheduler begins at `rr_ptr` and searches the four warp queues. A queued instruction is eligible when its source and destination register dependencies are not blocked by the scoreboard. If one warp is blocked, the scheduler skips it and can issue another ready warp.

This is latency hiding in miniature: a dependency in one context does not have to idle the whole vector datapath when independent work exists elsewhere.

## Pipeline

```text
per-warp queues
      |
      v
round-robin scheduler -- scoreboard eligibility
      |
      v
+-----------+
| issue/ALU |
+-----------+
      |
      v
+-----------+
|    EX     |  one-cycle result holding stage
+-----------+
      |
      v
+-----------+
|    WB     |  bypass source + architectural commit
+-----------+
      |
      v
per-warp vector register files
```

Results are computed when an instruction issues, stored in EX, then move to WB and commit. A destination register is marked busy on issue and retired from the scoreboard at commit.

## Scoreboard and hazards

For each warp/register pair, the scoreboard tracks whether a write is in flight.

An instruction is blocked when `src_a`, `src_b`, or `dst` is busy and the producer is not yet bypassable from WB. The destination check is deliberately conservative and also protects masked writes, because disabled lanes implicitly read the previous destination value.

### RAW example

```text
w0: VADD v4, v1, v2
w0: VMUL v5, v4, v3
```

When the second instruction reaches the queue while the first is still in EX, `w0.v4` is busy and not yet forwardable. Warp 0 is skipped for a cycle. If warp 1 has ready work, warp 1 can issue instead.

When the producer reaches WB, the consumer can issue and receive the newest value through the WB forwarding path.

## Forwarding

WB bypassing exists for:

- source A;
- source B;
- the previous destination vector used by masked writes.

The third case is subtle but important. Without old-destination forwarding, two closely spaced partial writes could lose lanes updated by the older instruction.

## Predication

Every instruction has an 8-bit lane mask. Enabled lanes use the ALU result. Disabled lanes preserve the old destination vector. Sparse masks therefore create a real old-destination dependency and make the scoreboard/forwarding logic more interesting to verify.

## Counters

The RTL exposes:

- `instructions_issued_o`;
- `active_lane_ops_o`;
- `masked_lane_ops_o`;
- `forwarding_events_o`;
- `scoreboard_stall_cycles_o`;
- `blocked_warp_events_o`;
- `warp_switch_events_o`;
- `queue_backpressure_events_o`.

These counters make scheduler and dependency behaviour measurable rather than anecdotal.

## Current simplifications

- no instruction memory / PC yet;
- one-entry queue per warp rather than a deep frontend;
- fixed two-stage execution latency;
- no vector memory pipeline yet;
- no branches or divergence stack;
- no cache hierarchy;
- no synthesis/timing target yet.

Those are deliberate boundaries. M7 should add a vector load/store path and a banked scratchpad, because memory behaviour is the next new class of GPU verification problem.
