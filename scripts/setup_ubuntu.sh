#!/usr/bin/env bash
set -euo pipefail
sudo apt-get update
sudo apt-get install -y build-essential python3 make iverilog gtkwave
printf '\nApexGPU dependencies installed. Try: make verify\n'
