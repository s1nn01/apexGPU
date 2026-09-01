# Project Notes / engineering diary

The strongest version of ApexGPU is not just the final code; it is being able to explain **why each microarchitectural change created a new class of bugs and how verification evolved to catch them**.

## MVP decisions

- 8 SIMD lanes: wide enough to demonstrate masks while waveforms remain readable.
- 16 vector registers per context: compact encoding and enough dependency variety.
- telemetry workload: a motivating data-parallel use case without obscuring GPU architecture.
- C++ + Python models: independent implementations reduce correlated reference-model bugs.

## M4 — randomized RTL differential verification

The important change is not “more random tests”. The RTL now receives the same encoded programs as the architectural models. Vector generation first requires Python and C++ to agree, then uses the C++ state as the RTL oracle.

Failure reproduction data:

- seed;
- instruction count;
- warp/register/lane mismatch;
- VCD waveform path.

## M5 — scoreboard

Adding a real EX stage means a producer can be too early to forward. The per-warp scoreboard marks destinations busy from issue to commit. A consumer can issue once the producer reaches WB, where bypassing is possible.

Masked writes make `dst` an implicit source. That is why the scoreboard protects destinations as well as explicit source registers.

## M6 — four warp contexts

Each warp has an independent register file, scoreboard and instruction queue. The scheduler searches in round-robin order and skips blocked warps. This demonstrates the GPU idea of using other contexts to hide a dependency stall.

## Measurements worth recording

- blocked warp events per 1,000 instructions;
- global stall cycles per 1,000 instructions;
- forwarding events;
- warp switches;
- active-lane utilisation;
- throughput for one warp vs four interleaved warps.

## Deliberate bug experiments

1. Disable `register_blocked()` for `src_a`: random RAW sequences should fail.
2. Remove `fwd_dst_old`: complementary masked writes should lose lanes.
3. Index the register file without `selected_warp`: multi-warp isolation should fail quickly.
4. Stop skipping blocked queues in the scheduler: throughput counters should show more global stall cycles even if architectural correctness remains intact.
