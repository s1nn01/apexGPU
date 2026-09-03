# ApexGPU

**A four-warp GPU-style SIMD telemetry accelerator with a verification-first workflow.**

ApexGPU is a learning microarchitecture built around two things I wanted to understand deeply: **GPU execution/verification** and **high-rate racing telemetry**. The design processes eight 32-bit lanes in parallel and now includes enough frontend and dependency machinery to create realistic verification problems rather than behaving like a standalone vector ALU.

The project now includes:

- 8-lane x 32-bit SIMD datapath;
- 16 vector registers **per warp**;
- 4 independent warp/context register files;
- per-lane predication masks;
- 11 vector instructions including telemetry-motivated `VABSDELTA` and `VCLAMP`;
- two-stage EX/WB pipeline;
- per-warp register scoreboard;
- WB source and old-destination forwarding;
- one-entry instruction queue per warp;
- round-robin scheduler that skips blocked warps;
- scheduler/dependency performance counters;
- C++ architectural golden model;
- independent Python architectural model;
- Python ↔ C++ randomized differential regression;
- **randomized C++-golden ↔ SystemVerilog RTL differential replay**;
- deterministic seeds and VCD waveform output;
- GitHub Actions verification on every push.

## Why racing telemetry?

The motivation is data parallelism rather than pretending this is a complete Formula 1 GPU. Sensor batches such as wheel speed, temperature, suspension travel and brake channels naturally apply the same arithmetic across many values.

Two instructions make that workload concrete:

- `VABSDELTA`: lane-wise absolute difference from a reference sample;
- `VCLAMP`: lane-wise clamp to `[0, immediate]` for bounded/sanitised sensor values.

The surrounding architecture is conventional SIMD/GPU-inspired execution logic.

## M4 — randomized RTL differential verification

The randomized RTL test no longer stops at software models.

```text
                    same encoded program
                           |
            +--------------+--------------+
            |                             |
            v                             v
 independent Python model          C++ golden model
            |                             |
            +------------ compare --------+
                          |
                    must agree first
                          |
                          v
                  SystemVerilog RTL
                          |
                          v
             compare all 4 x 16 x 8
               architectural values
```

`verification/generate_rtl_vectors.py` deliberately produces dependency-heavy, masked, multi-warp programs. It refuses to generate an RTL oracle unless Python and C++ agree first.

On an RTL mismatch the testbench reports the exact **seed, warp, register, lane, expected value, actual value and VCD path**.

## M5 — scoreboard + hazard handling

The core now has a real EX stage before WB. A destination is marked busy when its instruction issues and stays busy until commit.

For each queued instruction, the scheduler checks:

- `src_a` dependency;
- `src_b` dependency;
- destination/WAW dependency;
- old-destination dependency required by masked writes.

A producer in EX is too early to consume, so the dependent warp waits. Once the producer reaches WB, the value can be forwarded and the consumer may issue.

## M6 — four warp contexts + round-robin scheduler

Each warp owns an independent register file, scoreboard and queue. The scheduler walks the queues in round-robin order and issues the first ready warp.

```text
 warp 0 queue --\
 warp 1 queue ----> round-robin + scoreboard ---> SIMD EX ---> WB
 warp 2 queue ----/                                  |
 warp 3 queue --/                                    v
                                          per-warp register files
```

This means a dependency in one warp does not necessarily stall the datapath: another ready warp can issue instead. It is a small but genuine example of latency hiding through multiple execution contexts.

## Instruction encoding

```text
63      56 55   52 51   48 47   44 43                12 11    8 7  6 5     0
+----------+-------+-------+-------+--------------------+--------+----+-------+
| lane mask| opcode|  dst  | src_a | signed immediate   | src_b  |warp| rsvd  |
+----------+-------+-------+-------+--------------------+--------+----+-------+
```

Warp ID is encoded in bits `[7:6]`, allowing four contexts.

## Instruction set

| Opcode | Mnemonic | Behaviour |
|---:|---|---|
| `0x0` | `VNOP` | no operation |
| `0x1` | `VADD` | `dst[i] = a[i] + b[i]` |
| `0x2` | `VSUB` | `dst[i] = a[i] - b[i]` |
| `0x3` | `VMUL` | low 32 bits of multiplication |
| `0x4` | `VMAX` | signed maximum |
| `0x5` | `VMIN` | signed minimum |
| `0x6` | `VXOR` | bitwise XOR |
| `0x7` | `VAND` | bitwise AND |
| `0x8` | `VSHL` | logical left shift |
| `0x9` | `VCMPLT` | signed less-than -> 0/1 |
| `0xA` | `VABSDELTA` | saturating signed absolute difference |
| `0xB` | `VCLAMP` | clamp `a[i]` into `[0, imm]` |

## Running it

### Software model tests

```bash
make model-test
```

### Independent Python ↔ C++ regression

```bash
make regression
```

### Directed M5/M6 RTL architecture test

```bash
make rtl-test
```

This checks scoreboard blocking, multi-warp state isolation, scheduler switching and WB forwarding.

### One randomized RTL differential run

```bash
make rtl-random
```

Verilator is the primary simulator for multi-warp RTL regression; Icarus remains a fallback for simpler compatibility checks.

Default: 1,000 randomized RTL instructions.

Use your own seed/count:

```bash
APEXGPU_SEED=123456 APEXGPU_RTL_COUNT=5000 make rtl-random
```

### Four-seed RTL suite

```bash
make rtl-suite
```
