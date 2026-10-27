#!/bin/bash
# Banco del puente de la flash (2.1.1, el mismo del MSXimus V3.8). Uso: ver la cabecera de tb_fbr.sv.
set -e
cd "$(dirname "$0")"
iverilog -g2012 -o tb_fbr.vvp -s tb_fbr tb_fbr.sv ../../src/flash_rw.v ../../src/flash_bridge.v
vvp -n tb_fbr.vvp
