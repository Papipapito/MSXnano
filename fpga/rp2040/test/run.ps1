# Pruebas en el PC de la logica de entrada del firmware del RP2040 (varios teclados
# y mandos). Compila con el gcc de WSL, sin SDK ni hardware:
#   test_kbd_merge        logica pura de inc/kbd_merge.h
#   test_port_watch       logica pura de inc/port_watch.h (vigilante de puertos de PIO-USB)
#   test_usbin            src/usbin.c REAL con el SDK y TinyUSB sustituidos por stubs/
#   test_usbin check ...  UN solo dispositivo = mismos bytes que el firmware anterior
#                         (golden/single_device.txt)
#   test_usbin_dbg        lo mismo con MSXNANO_DEBUG_CDC=1: el registro dbg_printf no cambia
#                         lo que sale al cable, y ademas se comprueba su texto
#
# Uso:
#   pwsh -File run.ps1 [-Out <dir en WSL para los binarios>]
#   pwsh -File run.ps1 -MakeGolden <dir con src\usbin.c e inc\{usbin,keymaps}.h ANTERIORES>
#     regenera golden/single_device.txt con ese firmware de referencia (hace falta si
#     cambia keymaps.h o el protocolo del cable; no con el usbin.c que se esta probando).
# Sale con codigo distinto de 0 si algo falla.
param(
    [string]$Out = "/tmp/msxnano_rp2040_test",
    [string]$MakeGolden = "",
    [string]$Distro = "Ubuntu-24.04"
)
$ErrorActionPreference = "Stop"

function Get-WslPath([string]$p) {
    $r = (& wsl.exe -d $Distro -- wslpath -a ($p -replace '\\', '/')) | Out-String
    if ($LASTEXITCODE -ne 0 -or -not $r.Trim()) { throw "wslpath fallo con '$p' (distro $Distro)" }
    return $r.Trim()
}
function Invoke-Wsl([string]$cmd) {
    & wsl.exe -d $Distro -- bash -lc $cmd
    if ($LASTEXITCODE -ne 0) { throw "fallo (codigo $LASTEXITCODE)" }
}

$t = Get-WslPath $PSScriptRoot
$cf = "-std=gnu11 -O1 -g -Wall -Wextra -Wno-unused-parameter -Wno-unused-but-set-variable"

if ($MakeGolden) {
    $ref = Get-WslPath (Resolve-Path $MakeGolden).Path
    Invoke-Wsl ("set -e; cd '$t'; mkdir -p '$Out'; " +
        "gcc $cf -Istubs -I'$ref/inc' -I../inc -o '$Out/test_usbin_ref' test_usbin.c '$ref/src/usbin.c'; " +
        "'$Out/test_usbin_ref' dump > golden/single_device.txt; wc -l golden/single_device.txt")
    exit 0
}

Invoke-Wsl ("set -e; cd '$t'; mkdir -p '$Out'; " +
    "gcc $cf -I../inc -o '$Out/test_kbd_merge' test_kbd_merge.c; " +
    "gcc $cf -I../inc -o '$Out/test_port_watch' test_port_watch.c; " +
    "gcc $cf -Istubs -I../inc -o '$Out/test_usbin' test_usbin.c ../src/usbin.c; " +
    "gcc $cf -DMSXNANO_DEBUG_CDC=1 -Istubs -I../inc -o '$Out/test_usbin_dbg' test_usbin.c ../src/usbin.c; " +
    "'$Out/test_kbd_merge'; '$Out/test_port_watch'; '$Out/test_usbin'; '$Out/test_usbin' check golden/single_device.txt; " +
    "'$Out/test_usbin_dbg'; '$Out/test_usbin_dbg' check golden/single_device.txt")
Write-Host "TODO EN VERDE"
