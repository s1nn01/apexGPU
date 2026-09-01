#!/usr/bin/env bash
set -euo pipefail
mkdir -p build
SEED="${APEXGPU_SEED:-20260901}"
COUNT="${APEXGPU_RTL_COUNT:-1000}"

PYTHONPATH=verification python3 verification/generate_rtl_vectors.py \
  --seed "$SEED" --count "$COUNT" --out build/rtl_vectors.txt

SOURCES=(rtl/apexgpu_pkg.sv rtl/vector_alu.sv rtl/apexgpu_core.sv tests/tb_rtl_random.sv)
# Verilator is primary for M4. Icarus 13.0 mis-indexes dynamically selected
# dimensions of this multi-warp unpacked register file for the randomized TB.
if command -v verilator >/dev/null 2>&1; then
  echo "[ApexGPU] randomized RTL regression using Verilator"
  verilator --binary --timing --trace -Wno-fatal "${SOURCES[@]}" \
    --top-module tb_rtl_random -Mdir build/verilated_random
  ./build/verilated_random/Vtb_rtl_random
elif command -v iverilog >/dev/null 2>&1; then
  echo "[ApexGPU] randomized RTL regression using Icarus Verilog (fallback)"
  iverilog -g2012 -o build/tb_rtl_random "${SOURCES[@]}"
  vvp build/tb_rtl_random
else
  echo "No SystemVerilog simulator found. Install Verilator or Icarus Verilog." >&2
  exit 2
fi
