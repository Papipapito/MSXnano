# Proyecto FPGA — Tang Nano 20K

## Hardware
- Sipeed Tang Nano 20K — Gowin GW2AR-18 (familia GW2A-18C)
- Bitstream y flasheo: Gowin EDA + Gowin Programmer (NO usar openFPGALoader)

## Flujo
1. Escribir RTL + testbench
2. Verificar SIEMPRE con **Icarus** antes de dar nada por bueno:
   Icarus 12 en WSL Ubuntu (`iverilog -g2012 a.v b.v ...` + `vvp`), multi-fichero desde
   disco (acepta el RTL legacy tal cual). Ondas con `gtkwave` si hace falta depurar.
3. El bitstream real sale SIEMPRE de **Gowin EDA** (`gw_sh.exe build.tcl`); no hay síntesis
   Gowin en el flujo de sim. Un `yosys` genérico solo valdría de sanity check, no para Gowin.

## Convenciones RTL
- Verilog-2001
- Reset asíncrono activo a nivel bajo: `rst_n`
- Registros: `always @(posedge clk or negedge rst_n)`, asignación no bloqueante `<=`
- Combinacional: `always @(*)`, asignación bloqueante `=`
- Sufijos: `_n` activo bajo, `_r` registrado, `_i`/`_o` puertos de módulo
- Un módulo por fichero, nombre de fichero = nombre de módulo

## Reglas
- Todo módulo nuevo necesita testbench con asserts, no solo $display
- No inferir latches: en `always @(*)` cubrir todos los casos o usar default
