#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Simulacion de LOGICA de megaram.v (megaram_scc) con Icarus Verilog.
# No necesita la placa Tang Nano: compila el Verilog y corre el testbench en PC.
#
#   Prerequisito (una vez):  sudo apt-get install -y iverilog   (en WSL)
#   Uso:                     bash run.sh
#
# Sale con codigo 0 si "RESULT: PASS", !=0 si falla (usable en CI / por Claude).
# -----------------------------------------------------------------------------
set -euo pipefail
cd "$(dirname "$0")"

DUT="../../fpga/src/megaram.v"
TB="megaram_tb.v"
OUT="/tmp/megaram_sim.vvp"
LOG="/tmp/megaram_sim.log"

if ! command -v iverilog >/dev/null 2>&1; then
    echo "ERROR: iverilog no esta instalado. En WSL:  sudo apt-get install -y iverilog" >&2
    exit 127
fi

iverilog -g2012 -o "$OUT" "$TB" "$DUT"
vvp "$OUT" | tee "$LOG"
grep -q "RESULT: PASS" "$LOG"
