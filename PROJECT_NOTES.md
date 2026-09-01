# Project Notes / build diary starter

Use this file as a real engineering diary while extending ApexGPU. The strongest version of this project is not just the final code; it is being able to explain **why** each architectural decision changed the failure modes and verification strategy.

## MVP decisions

- 8 lanes: wide enough to demonstrate masks, but waveforms stay readable.
- 16 vector registers: keeps the encoding compact.
- 2-stage issue/writeback path: creates meaningful forwarding cases without requiring a full scheduler.
- C++ + Python models: deliberately independent implementations reduce correlated bugs.
- telemetry workload: gives the project a motivating use case without obscuring the GPU architecture.

## Things I should measure next

- percentage of random instructions that trigger forwarding;
- test count required to catch an intentionally removed forwarding path;
- active-lane utilisation under sparse masks;
- throughput after adding multiple warps;
- memory coalescing efficiency once loads/stores exist.

## First deliberate bug experiment

Comment out `fwd_dst_old` in the masked-destination merge path. Construct two consecutive writes to the same destination with complementary masks. The resulting failure is subtle and gives a strong hardware-debugging story.
