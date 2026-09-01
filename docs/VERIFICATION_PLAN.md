# Verification Plan

## Objectives

1. Every supported opcode matches its architectural definition.
2. Signed/unsigned edge behaviour is intentional and stable.
3. Lane masks never modify disabled destination lanes.
4. Back-to-back RAW dependencies observe the newest value.
5. Source/destination aliasing does not create lane-order artefacts.
6. Reset clears architectural state and counters.
7. The design remains debuggable when a test fails.

## Test layers

### C++ unit tests

Directed vectors cover:
- instruction encode/decode;
- VADD;
- VABSDELTA;
- VCLAMP;
- masked writes;
- `dst == src_a` aliasing.

### Independent differential model

`verification/reference.py` is intentionally written differently from `model/apex_gpu.cpp`. Random programs include:
- all opcodes;
- random masks;
- signed 32-bit values;
- random register aliasing;
- elevated back-to-back dependency probability;
- negative and positive immediates.

The Python model and C++ model must end with exactly the same 16 x 8 architectural register state.

### RTL smoke test

The SystemVerilog testbench creates an immediate RAW dependency that requires writeback forwarding. It also checks the forwarding performance counter and emits a VCD waveform.

### Assertions

Current assertions verify:
- register indices are legal;
- each accepted non-NOP instruction commits one cycle later;
- the committed destination matches the issued destination.

## Planned verification upgrades

- vector-file replay of the full randomized software suite in RTL;
- functional covergroups for opcode x mask density x aliasing x forwarding;
- formal proof of masked-lane preservation;
- mutation testing with selectable forwarding/mask bugs;
- scoreboard for multiple outstanding instructions;
- trace minimisation to shrink failing random programs.
