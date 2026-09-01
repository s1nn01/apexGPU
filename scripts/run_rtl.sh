#!/usr/bin/env bash
set -euo pipefail
mkdir -p build
if command -v iverilog >/dev/null 2>&1; then
  echo "[ApexGPU] using Icarus Verilog"
  iverilog -g2012 -o build/tb_apexgpu \
    rtl/apexgpu_pkg.sv rtl/vector_alu.sv rtl/apexgpu_core.sv tests/tb_apexgpu.sv
  vvp build/tb_apexgpu
elif command -v verilator >/dev/null 2>&1; then
  echo "[ApexGPU] using Verilator"
  verilator --binary --timing --trace -Wno-fatal \
    rtl/apexgpu_pkg.sv rtl/vector_alu.sv rtl/apexgpu_core.sv tests/tb_apexgpu.sv \
    --top-module tb_apexgpu -Mdir build/verilated
  ./build/verilated/Vtb_apexgpu
else
  echo "No SystemVerilog simulator found. Install Verilator or Icarus Verilog." >&2
  exit 2
fi
