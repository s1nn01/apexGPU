# Verification Plan — M4 to M6

## Objectives

1. Every supported opcode matches its architectural definition.
2. Signed/unsigned edge behaviour is intentional and stable.
3. Lane masks never modify disabled destination lanes.
4. Scoreboard state prevents consumers from reading an unavailable producer.
5. WB forwarding supplies the newest value once a producer becomes bypassable.
6. A blocked warp does not prevent an independent ready warp from issuing.
7. Architectural state is isolated between all four warp contexts.
8. Random RTL execution ends in exactly the same state as the golden models.
9. Failures are reproducible from a printed seed and inspectable in a VCD waveform.

## Layer 1 — C++ unit tests

`tests/model_tests.cpp` checks:

- instruction encode/decode including warp id;
- arithmetic and telemetry-oriented operations;
- lane masking;
- source/destination aliasing;
- independent warp register state.

## Layer 2 — independent Python vs C++ differential test

`verification/differential_regression.py` keeps the original software triangulation alive. Random single-warp programs execute through both the independent Python implementation and the C++ golden model. The default suite checks 18,000 instructions.

This is intentionally retained after M6: if the software oracle is wrong, using it to validate RTL would simply reproduce the same mistake.

## Layer 3 — directed M5/M6 RTL architecture test

`tests/tb_apexgpu.sv` creates:

- a dependency chain that becomes blocked while its producer is in EX;
- useful work in a second warp while the first warp is blocked;
- a masked destination update;
- independent architectural states using identical register indices.

It also requires non-zero scoreboard-block, warp-switch, and forwarding counters.

## Layer 4 — M4 randomized RTL differential test

`verification/generate_rtl_vectors.py` creates dependency-heavy multi-warp programs. Before a vector file is emitted:

1. the program executes in the Python model;
2. the same initial state/program executes in the C++ golden model;
3. generation aborts if those two models disagree;
4. the C++ result becomes the RTL oracle.

`tests/tb_rtl_random.sv` then:

1. loads all `4 x 16 x 8` initial register values through the debug port;
2. feeds the encoded program into the real RTL while obeying backpressure;
3. waits for every non-NOP instruction to commit;
4. reads all architectural registers from all four warps;
5. compares every lane against the golden final state.

On mismatch it prints the seed, warp, register, lane, expected/actual values, and waveform path.

## Random stimulus bias

Pure uniform random testing under-samples the interesting cases, so the generator deliberately increases:

- same-warp RAW dependencies;
- repeated destinations / WAW pressure;
- sparse lane masks;
- cross-warp interleaving;
- signed values and mixed immediates.

A directed prefix guarantees that scoreboard skipping and multi-warp scheduling are exercised even for small runs.

## Running verification

```bash
make model-test
make regression
make rtl-test
make rtl-random
```

Or all primary checks:

```bash
make verify
```

Run four deterministic randomized RTL seeds:

```bash
make rtl-suite
```

Change the per-seed instruction count:

```bash
APEXGPU_RTL_COUNT=5000 make rtl-suite
```

Run one custom seed:

```bash
APEXGPU_SEED=123456 APEXGPU_RTL_COUNT=2000 make rtl-random
```

## Next verification upgrades

- functional coverage for opcode x mask density x dependency type x warp;
- mutation testing for scoreboard/forwarding defects;
- minimized failing traces;
- assertions that scoreboard bits exactly correspond to in-flight writers;
- memory ordering and bank-conflict coverage once M7 adds vector memory.
