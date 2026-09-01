#!/usr/bin/env python3
"""Generate deterministic, dependency-heavy multi-warp RTL regression vectors.

File format is deliberately numeric so both Icarus and Verilator testbenches can
parse it with simple $fscanf calls:
  line 1: <seed> <instruction_count>
  next WARPS*REGS lines: <warp> <reg> <8 initial lane values>
  next instruction_count lines: <64-bit instruction hex>
  next WARPS*REGS lines: <warp> <reg> <8 expected final lane values>
"""
from __future__ import annotations
import argparse
import random
import subprocess
from pathlib import Path

from generate_vectors import OPS, pack
from reference import LANES, REGS, WARPS, decode, execute_warped


def make_program(seed: int, count: int):
    rng = random.Random(seed)
    regs = [
        [[rng.randint(-5000, 5000) for _ in range(LANES)] for _ in range(REGS)]
        for _ in range(WARPS)
    ]
    initial = [[r[:] for r in warp] for warp in regs]
    program: list[int] = []
    last_dst = [None] * WARPS

    # Directed prefix: dependency chains in warp 0 are interleaved with useful
    # work from other warps. This specifically exercises scoreboard skipping,
    # round-robin scheduling and WB forwarding.
    directed = [
        pack(0xFF, 0x1, 4, 1, 2, 0, 0),   # w0 v4 = v1 + v2
        pack(0xFF, 0x1, 4, 1, 2, 0, 1),   # w1 independent same reg numbers
        pack(0xFF, 0x3, 5, 4, 3, 0, 0),   # w0 RAW on v4 -> scoreboard wait
        pack(0x55, 0xA, 5, 5, 1, 0, 0),   # w0 masked dst/src alias
        pack(0xFF, 0x2, 6, 2, 1, 0, 2),   # w2 independent
        pack(0xFF, 0xB, 7, 5, 0, 500, 0), # w0 dependency on v5
        pack(0xAA, 0x6, 9, 4, 6, 0, 3),   # w3 masked write
    ]
    for word in directed[:count]:
        execute_warped(regs, word)
        program.append(word)
        w = (word >> 6) & 0x3
        last_dst[w] = (word >> 48) & 0xF

    while len(program) < count:
        warp = rng.randrange(WARPS)
        op = rng.choice(OPS)
        dst = rng.randrange(REGS)
        a = rng.randrange(REGS)
        b = rng.randrange(REGS)

        # High dependency density makes scoreboarding meaningful rather than
        # relying on lucky random collisions.
        if last_dst[warp] is not None and rng.random() < 0.55:
            a = last_dst[warp]
        if last_dst[warp] is not None and rng.random() < 0.20:
            dst = last_dst[warp]

        # Include sparse predication frequently so old-destination hazards are
        # part of the randomized state space.
        mask = 0xFF if rng.random() < 0.25 else rng.randrange(1, 256)
        imm = rng.randint(-50000, 50000)
        word = pack(mask, op, dst, a, b, imm, warp)
        execute_warped(regs, word)
        program.append(word)
        last_dst[warp] = dst

    return initial, program, regs


def cpp_expected(cli: str, initial, program):
    lines = []
    for w in range(WARPS):
        for r in range(REGS):
            lines.append(f"SETW {w} {r} " + " ".join(map(str, initial[w][r])))
    for word in program:
        lines.append(f"EXEC {word:016x}")
    for w in range(WARPS):
        for r in range(REGS):
            lines.append(f"GETW {w} {r}")

    result = subprocess.run(
        [cli], input="\n".join(lines) + "\n", text=True,
        capture_output=True, check=True
    )
    regs = [[[0] * LANES for _ in range(REGS)] for _ in range(WARPS)]
    for line in result.stdout.splitlines():
        parts = line.split()
        if parts and parts[0] == "REGW":
            w, r = int(parts[1]), int(parts[2])
            regs[w][r] = list(map(int, parts[3:]))
    return regs


def write(path: Path, seed: int, initial, program, expected) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w") as f:
        f.write(f"{seed} {len(program)}\n")
        for w in range(WARPS):
            for r in range(REGS):
                f.write(f"{w} {r} " + " ".join(map(str, initial[w][r])) + "\n")
        for word in program:
            f.write(f"{word:016x}\n")
        for w in range(WARPS):
            for r in range(REGS):
                f.write(f"{w} {r} " + " ".join(map(str, expected[w][r])) + "\n")



def write_commit_oracles(base_dir: Path, initial, program) -> None:
    """Write one expected architectural commit stream per warp.

    Warps may interleave in the RTL scheduler, but instructions within a warp
    remain ordered. Keeping one oracle file per warp lets the testbench check
    every commit without assuming a global commit order.
    """
    regs = [[r[:] for r in warp] for warp in initial]
    handles = [
        (base_dir / f"rtl_commits_w{w}.txt").open("w")
        for w in range(WARPS)
    ]
    try:
        for program_index, word in enumerate(program):
            ins = decode(word)
            execute_warped(regs, word)
            values = regs[ins["warp"]][ins["dst"]]
            handles[ins["warp"]].write(
                f"{program_index} {word:016x} {ins['dst']} " + " ".join(map(str, values)) + "\n"
            )
    finally:
        for handle in handles:
            handle.close()

def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, default=20260901)
    ap.add_argument("--count", type=int, default=1000)
    ap.add_argument("--out", default="build/rtl_vectors.txt")
    ap.add_argument("--cli", default="build/apexgpu_cli")
    args = ap.parse_args()
    initial, program, python_expected = make_program(args.seed, args.count)
    golden_expected = cpp_expected(args.cli, initial, program)
    if golden_expected != python_expected:
        raise SystemExit("Python/C++ architectural models disagree; refusing to generate RTL oracle")
    out_path = Path(args.out)
    write(out_path, args.seed, initial, program, golden_expected)
    write_commit_oracles(out_path.parent, initial, program)
    print(f"generated RTL regression seed={args.seed} instructions={len(program)} -> {args.out}")


if __name__ == "__main__":
    main()
