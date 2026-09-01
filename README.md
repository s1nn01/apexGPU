# ApexGPU

**A small GPU-style SIMD telemetry accelerator with a verification-first workflow.**

ApexGPU is a portfolio project built around two things I wanted to learn deeply: **GPU execution architecture** and **high-rate racing telemetry**. The hardware core accepts compact vector instructions and processes eight telemetry channels in parallel, while the surrounding verification stack checks the RTL against an independent C++ golden model.

The MVP is deliberately more than a toy ALU. It includes:

- 8-lane, 32-bit SIMD datapath
- 16-entry vector register file
- arithmetic, logic, comparison and telemetry-oriented operations
- per-lane execution masks (GPU-style predication)
- two-stage execute/writeback pipeline
- RAW hazard detection and forwarding
- architectural counters for issued instructions, masked lanes and stalls
- SystemVerilog assertions for invariants
- independent C++ reference model
- deterministic + randomized differential test-vector generation
- machine-readable JSON regression reports
- optional VCD waveform generation through the RTL testbench
- GitHub Actions CI for the software-side regression suite

The project is intentionally structured so the next iterations can add **multiple warps, scoreboarding, memory operations, a cache, a scheduler and performance/power experiments**.

## Why telemetry?

A GPU is fundamentally good at applying the same operation across many independent values. Racing telemetry has the same shape: wheel speeds, brake temperatures, suspension travel, tyre channels and sensor batches are naturally vectorisable.

The MVP therefore includes two domain-specific instructions in addition to conventional ALU operations:

- `VABSDELTA`: absolute lane-wise difference, useful for comparing current telemetry with a reference sample.
- `VCLAMP`: clamp each lane between zero and a scalar limit, useful for sanitising bounded sensor values.

These do **not** make this a fake “F1 GPU”. They are simply a motivating workload layered on a conventional SIMD execution core.

## Architecture

```text
             64-bit instruction
                    |
                    v
          +---------------------+
          | decoder + issue     |
          +----------+----------+
                     |
          +----------v----------+
          | 8 x 32-bit SIMD ALU |  <--- forwarding / lane mask
          +----------+----------+
                     |
             pipeline register
                     |
          +----------v----------+
          | vector register file|
          | 16 x (8 x 32-bit)   |
          +---------------------+
```

### Instruction set

| Opcode | Mnemonic | Behaviour |
|---:|---|---|
| `0x0` | `VNOP` | no operation |
| `0x1` | `VADD` | `dst[i] = a[i] + b[i]` |
| `0x2` | `VSUB` | `dst[i] = a[i] - b[i]` |
| `0x3` | `VMUL` | low 32 bits of `a[i] * b[i]` |
| `0x4` | `VMAX` | signed maximum |
| `0x5` | `VMIN` | signed minimum |
| `0x6` | `VXOR` | bitwise XOR |
| `0x7` | `VAND` | bitwise AND |
| `0x8` | `VSHL` | logical left shift by `b[i][4:0]` |
| `0x9` | `VCMPLT` | signed compare; result is 0/1 |
| `0xA` | `VABSDELTA` | `abs(a[i] - b[i])` |
| `0xB` | `VCLAMP` | signed clamp `a[i]` to `[0, imm]` |

Each instruction also carries an **8-bit lane mask**. Masked-off lanes preserve the previous destination value, just like predicated/vector execution.

## Instruction encoding

```text
63          56 55      52 51      48 47      44 43                12 11    8 7       0
+--------------+----------+----------+----------+--------------------+-----------+------+
| lane mask[7:0]| opcode   | dst      | src_a    | immediate[31:0]    | src_b  | reserved |
+--------------+----------+----------+----------+--------------------+-----------+------+
```

The helper code in `model/instruction.hpp` is the source of truth for packing/unpacking software instructions.

## Quick start

### 1. Build and test the C++ golden model

```bash
make model-test
```

### 2. Generate a deterministic randomized regression

```bash
make vectors
```

This emits `build/random_vectors.txt`, containing initial register state, encoded instructions and expected architectural states.

### 3. Run the software differential check

```bash
make regression
```

This compares an independent Python execution model against the C++ golden model over a randomized instruction stream and writes `build/regression_report.json`.

### 4. Run the RTL (when Verilator or Icarus Verilog is installed)

```bash
make rtl-test
```

The script automatically uses an available simulator. The testbench consumes generated vectors and can dump `build/apexgpu.vcd` for waveform debugging.

> The repository remains useful on machines without an RTL simulator: the C++ model, generator, regressions and benchmarks all run independently.

## Example telemetry program

`examples/telemetry_demo.cpp` loads two eight-channel snapshots and executes:

1. absolute delta from the previous sample;
2. clamp to a maximum plausible delta;
3. compare against a per-channel threshold.

This maps cleanly onto operations used in anomaly detection / sensor-health pipelines while remaining a genuine vector-architecture exercise.

## Verification strategy

The verification plan is intentionally layered:

1. **Unit tests** check instruction encoding and every operation in the C++ model.
2. **Directed architectural tests** cover masking, signed arithmetic and source/destination aliasing.
3. **Random differential tests** generate legal programs and compare two independent software implementations.
4. **RTL smoke testing** exercises a dependency chain that requires forwarding and checks architectural state.
5. **Assertions** check issue/commit invariants and register legality.
6. **Waveforms** are emitted on demand to make a failing cycle debuggable rather than merely detectable.

Full randomized vector replay through RTL is intentionally the first verification upgrade on the roadmap.

See [`docs/VERIFICATION_PLAN.md`](docs/VERIFICATION_PLAN.md).

## Interesting design decisions

### Why a two-stage pipeline?

A single-cycle ALU would be simpler, but it removes one of the most useful verification problems: dependencies. Two stages create realistic RAW hazards and make forwarding observable.

### Why preserve masked destination lanes?

Predication is central to vector/SIMD execution. Preserving masked lanes means the verification environment must reason about old destination state, which produces stronger tests than simply writing zero.

### Why an independent golden model?

Copying the RTL logic into the testbench can reproduce the same bug twice. The C++ model uses different code structure and types, so disagreement is more informative.

## Repository layout

```text
ApexGPU/
├── rtl/                 SystemVerilog core, ALU, decoder, assertions
├── model/               C++ architectural golden model
├── verification/        random generator + independent Python model
├── tests/               C++ tests and RTL testbench
├── benchmarks/          software throughput microbenchmark
├── examples/            telemetry-motivated example workload
├── scripts/             build / RTL runner helpers
├── docs/                architecture and verification notes
└── .github/workflows/   CI
```

## Build-on roadmap

The MVP is designed to grow in technically meaningful increments:

**v0.2 — Warp execution**
- 4 hardware contexts (“warps”)
- round-robin warp scheduler
- per-warp program counter and mask
- scoreboard instead of simple pipeline interlock

**v0.3 — Memory system**
- vector load/store
- banked scratchpad
- coalescing experiment
- simple direct-mapped L1 cache

**v0.4 — Verification depth**
- constrained random instruction sequences
- functional coverage bins
- mutation testing: inject known RTL bugs and measure detection
- formal properties for forwarding and masking

**v0.5 — Telemetry kernel**
- rolling z-score / threshold kernel
- trace-driven workload from synthetic race telemetry
- cycles-per-sample comparison against scalar execution

**v1.0 — Mini GPU front end**
- tiny instruction memory
- multiple warps
- branches with divergence masks
- performance counters + dashboard

## What I would talk about in an interview

- why I chose SIMD and predication as the smallest meaningful GPU concepts;
- how I made the C++ model independent from the RTL;
- bugs caused by read-after-write dependencies;
- how forwarding changes both architecture and verification;
- why random testing finds aliasing/mask combinations directed tests miss;
- how I would scale the design to a scoreboard and multiple warps;
- what changes once vector memory access and cache behaviour are introduced.

## Status

This repository is an **MVP / learning architecture**, not production silicon. The current goal is correctness, debuggability and extensibility rather than timing closure or synthesis optimisation.

## License

MIT — see `LICENSE`.
