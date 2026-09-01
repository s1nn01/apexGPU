# ApexGPU Architecture Notes

## Goal

ApexGPU is the smallest design I could make that still exposes **real GPU-verification ideas**: vector lanes, predication, pipelining, dependencies, forwarding and an architectural reference model.

## Datapath

The core contains 16 architectural vector registers. Each register has eight signed 32-bit lanes. An issued instruction reads two source vectors and the previous destination vector. The ALU computes all eight lane results combinationally. The lane mask chooses which computed lanes replace the previous destination state.

The merged vector enters a one-entry writeback pipeline register and commits on the next rising clock edge.

## Forwarding

A back-to-back dependency such as:

```text
VADD v4, v1, v2
VSUB v5, v4, v3
```

would otherwise read stale `v4`, because `v4` is still in writeback while the second instruction reads its operands. ApexGPU compares the issue source indices with the current writeback destination and bypasses `wb_value` when they match.

The same bypass is applied to the *old destination* used during masked writes. This less obvious case matters for:

```text
VADD mask=0x0F v4, v1, v2
VADD mask=0xF0 v4, v3, v5
```

Without destination forwarding, the second instruction could accidentally lose the first instruction's lower-lane update.

## Predication / lane masks

Every instruction carries one bit per lane. Disabled lanes preserve architectural destination state. This resembles vector predication and provides a stepping stone towards a future divergence-mask implementation.

## Counters

The core exposes:

- issued instruction count;
- active lane operation count;
- masked lane operation count;
- forwarding-event count.

The counters make performance experiments measurable as the project grows.

## Intentional simplifications

- no instruction fetch or PC yet;
- no memory pipeline;
- no branches/divergence stack;
- no multiple warps;
- fixed 8-lane width;
- no synthesis/timing target yet.

These are deliberate boundaries for an MVP rather than hidden omissions.
