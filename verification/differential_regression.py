#!/usr/bin/env python3
from __future__ import annotations
import argparse, json, random, subprocess, time
from pathlib import Path
from reference import execute
from generate_vectors import pack, OPS, LANES, REGS

def cpp_state(cli: str, initial, program):
    lines = []
    for r, values in enumerate(initial):
        lines.append(f"SET {r} " + " ".join(map(str, values)))
    for word in program:
        lines.append(f"EXEC {word:016x}")
    for r in range(REGS): lines.append(f"GET {r}")
    p = subprocess.run([cli], input="\n".join(lines)+"\n", text=True, capture_output=True, check=True)
    regs = [[0]*LANES for _ in range(REGS)]
    for line in p.stdout.splitlines():
        parts = line.split()
        if parts and parts[0] == "REG": regs[int(parts[1])] = list(map(int, parts[2:]))
    return regs

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cli", default="build/apexgpu_cli")
    ap.add_argument("--seed", type=int, default=424242)
    ap.add_argument("--programs", type=int, default=120)
    ap.add_argument("--length", type=int, default=150)
    ap.add_argument("--report", default="build/regression_report.json")
    args = ap.parse_args()
    rng = random.Random(args.seed)
    failures, total = [], 0
    start = time.perf_counter()
    for case in range(args.programs):
        initial = [[rng.randint(-(2**31), 2**31-1) for _ in range(LANES)] for _ in range(REGS)]
        py_regs = [r[:] for r in initial]
        program = []
        prev_dst = None
        for _ in range(args.length):
            op = rng.choice(OPS); dst = rng.randrange(REGS); a = rng.randrange(REGS); b = rng.randrange(REGS)
            if prev_dst is not None and rng.random() < 0.45: a = prev_dst
            mask = rng.randrange(1, 256); imm = rng.randint(-50000, 50000)
            word = pack(mask, op, dst, a, b, imm)
            execute(py_regs, word); program.append(word); prev_dst = dst
        got = cpp_state(args.cli, initial, program)
        total += len(program)
        if got != py_regs:
            mismatch = next((r for r in range(REGS) if got[r] != py_regs[r]), None)
            failures.append({"case": case, "register": mismatch, "expected": py_regs[mismatch], "actual": got[mismatch]})
            break
    elapsed = time.perf_counter() - start
    report = {
        "project": "ApexGPU", "seed": args.seed, "programs": args.programs,
        "instructions_checked": total, "failures": failures,
        "elapsed_seconds": round(elapsed, 4), "status": "PASS" if not failures else "FAIL"
    }
    Path(args.report).parent.mkdir(parents=True, exist_ok=True)
    Path(args.report).write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    raise SystemExit(1 if failures else 0)

if __name__ == "__main__": main()
