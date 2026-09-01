#!/usr/bin/env python3
from __future__ import annotations
import argparse
import random
from pathlib import Path
from reference import execute

OPS = list(range(1, 0xC))
LANES, REGS = 8, 16

def pack(mask: int, op: int, dst: int, a: int, b: int, imm: int) -> int:
    return ((mask & 0xFF) << 56) | ((op & 0xF) << 52) | ((dst & 0xF) << 48) | \
           ((a & 0xF) << 44) | ((imm & 0xFFFFFFFF) << 12) | ((b & 0xF) << 8)

def generate(seed: int, count: int):
    rng = random.Random(seed)
    regs = [[rng.randint(-2000, 2000) for _ in range(LANES)] for _ in range(REGS)]
    initial = [r[:] for r in regs]
    program = []
    snapshots = []

    # Seed the stream with dependency-heavy directed instructions, then randomise.
    directed = [
        pack(0xFF, 0x1, 4, 1, 2, 0),      # v4 <- v1 + v2
        pack(0xFF, 0x3, 5, 4, 3, 0),      # RAW dependency on v4
        pack(0x55, 0xA, 5, 5, 1, 0),      # dst aliases src, partial mask
        pack(0xFF, 0xB, 6, 5, 0, 500),    # telemetry clamp
    ]
    for word in directed[:count]:
        execute(regs, word)
        program.append(word)
        snapshots.append([r[:] for r in regs])

    while len(program) < count:
        op = rng.choice(OPS)
        dst, a, b = (rng.randrange(REGS) for _ in range(3))
        if rng.random() < 0.35 and program:
            # Increase dependency density by reading the previous destination.
            prev_dst = (program[-1] >> 48) & 0xF
            a = prev_dst
        mask = rng.randrange(1, 256)
        imm = rng.randint(-1000, 1000)
        word = pack(mask, op, dst, a, b, imm)
        execute(regs, word)
        program.append(word)
        snapshots.append([r[:] for r in regs])
    return initial, program, snapshots

def write_vector_file(path: Path, seed: int, initial, program, snapshots):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w") as f:
        f.write(f"# ApexGPU vectors seed={seed} instructions={len(program)}\n")
        for r, values in enumerate(initial):
            f.write("INIT %d %s\n" % (r, " ".join(map(str, values))))
        for cycle, (word, state) in enumerate(zip(program, snapshots)):
            f.write(f"EXEC {cycle} {word:016x}\n")
            for r, values in enumerate(state):
                f.write("EXPECT %d %s\n" % (r, " ".join(map(str, values))))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, default=20260901)
    ap.add_argument("--count", type=int, default=250)
    ap.add_argument("--out", default="build/random_vectors.txt")
    args = ap.parse_args()
    initial, program, snapshots = generate(args.seed, args.count)
    write_vector_file(Path(args.out), args.seed, initial, program, snapshots)
    print(f"generated {len(program)} instructions -> {args.out}")

if __name__ == "__main__": main()
