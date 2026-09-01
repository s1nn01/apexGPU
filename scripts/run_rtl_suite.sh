#!/usr/bin/env bash
set -euo pipefail
mkdir -p build
COUNT="${APEXGPU_RTL_COUNT:-1000}"
SEEDS=(20260901 424242 1337 9001)
SOURCES=(rtl/apexgpu_pkg.sv rtl/vector_alu.sv rtl/apexgpu_core.sv tests/tb_rtl_random.sv)

if command -v verilator >/dev/null 2>&1; then
  echo "[ApexGPU] compiling randomized RTL suite with Verilator"
  verilator --binary --timing --trace -Wno-fatal "${SOURCES[@]}" \
    --top-module tb_rtl_random -Mdir build/verilated_random
  for seed in "${SEEDS[@]}"; do
    PYTHONPATH=verification python3 verification/generate_rtl_vectors.py \
      --seed "$seed" --count "$COUNT" --out build/rtl_vectors.txt --cli build/apexgpu_cli
    echo "[ApexGPU] RTL seed=$seed count=$COUNT"
    ./build/verilated_random/Vtb_rtl_random
  done
elif command -v iverilog >/dev/null 2>&1; then
  echo "[ApexGPU] compiling randomized RTL suite with Icarus Verilog (fallback)"
  iverilog -g2012 -o build/tb_rtl_random "${SOURCES[@]}"
  for seed in "${SEEDS[@]}"; do
    PYTHONPATH=verification python3 verification/generate_rtl_vectors.py \
      --seed "$seed" --count "$COUNT" --out build/rtl_vectors.txt --cli build/apexgpu_cli
    echo "[ApexGPU] RTL seed=$seed count=$COUNT"
    vvp build/tb_rtl_random
  done
else
  echo "No SystemVerilog simulator found. Install Verilator or Icarus Verilog." >&2
  exit 2
fi
