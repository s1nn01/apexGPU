#!/usr/bin/env bash
set -euo pipefail
mkdir -p build
SOURCES=(rtl/apexgpu_pkg.sv rtl/vector_alu.sv rtl/apexgpu_core.sv tests/tb_apexgpu.sv)
if command -v verilator >/dev/null 2>&1; then
  echo "[ApexGPU] using Verilator"
  verilator --binary --timing --trace -Wno-fatal "${SOURCES[@]}" \
    --top-module tb_apexgpu -Mdir build/verilated
  ./build/verilated/Vtb_apexgpu
elif command -v iverilog >/dev/null 2>&1; then
  echo "[ApexGPU] using Icarus Verilog (fallback)"
  iverilog -g2012 -o build/tb_apexgpu "${SOURCES[@]}"
  vvp build/tb_apexgpu
else
  echo "No SystemVerilog simulator found. Install Verilator or Icarus Verilog." >&2
  exit 2
fi
