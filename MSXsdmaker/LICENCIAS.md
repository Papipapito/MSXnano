# Licencias y créditos / Licenses and credits

## MSX SD Maker

© 2026 Albert (Papipapito), proyecto MSXimus / MSXnano. GNU General Public License v3, como el resto del proyecto. El código fuente está en https://github.com/Papipapito/SD_Maker (y una copia en `fuente/`).

© 2026 Albert (Papipapito), MSXimus / MSXnano project. GNU General Public License v3, like the rest of the project. The source code is at https://github.com/Papipapito/SD_Maker (and a copy in `fuente/`).

## Lo que se copia en la tarjeta / What is copied to the card

`MSXsdmaker.exe` lleva dentro estos ficheros y los copia en la tarjeta. Cada uno es de su autor y se distribuye sin coste, tal como circula en la comunidad MSX. Si eres autor de alguno y prefieres que no esté, abre una *issue* y se retira.

`MSXsdmaker.exe` carries these files inside and copies them to the card. Each belongs to its author and is distributed free of charge, as it circulates in the MSX community. If you are the author of any of them and would rather it were not included, open an issue and it will be removed.

| Ficheros / Files | Autor / Author | Licencia / License |
|---|---|---|
| `NEXTOR.SYS`, `COMMAND2.COM`, `MSXDOS2.SYS`, Nextor tools (`bin\`: `MAPDRV`, `DRIVERS`, `DEVINFO`, `CHKDSK`, `XCOPY`…) | Néstor Soriano (Konamiman) and The MSX Licensing Corporation | Nextor license, below |
| `COMMAND3.COM` and the Nextor 3.0 beta 2 tools | Néstor Soriano (Konamiman) | Nextor license, below |
| `MSXDOS.SYS`, `COMMAND.COM` (MSX-DOS 1) | ASCII Corporation / Microsoft; today The MSX Licensing Corporation | Non-commercial distribution |
| `SOFARUN\` (SofaRun 8.1) | Louthrax | Freeware |
| VGMPlay: `musica\vgmplay.com` and `UTIL\VGMPLAY.COM` (1.4 dev), `SOFARUN\VGMPLAY.COM` (1.2, patched for SofaRun by Louthrax) | Laurens Holst (Grauw) | Simplified BSD, below |
| `MM\` (Multi Mente 2.07) | MOGU; `MM.COM` patched by this project to show long names (`parches/mm-nombres-largos`) and with its tool slots set from `MM.CFG` | Freeware |
| `FONTS\` | Font pack for Multi Mente | Freeware |
| `hub\` (`HUB.COM`, `HUBG.COM`) | Carles Amigó (fr3nd); HUBG by Oduvaldo Pavan Junior and Israel F. Araujo | Freeware |
| `WIFI\` (`TELNET`, `HGET`, `FTP`, `SNTP`, `TCPIP`…) | Oduvaldo Pavan Junior (ducasp), Néstor Soriano (Konamiman) and others | Freeware; see `WIFI\README.TXT` |
| `WIFI\FH.COM` (File-Hunter) | See `WIFI\FH_LICENSE.TXT` | See that file |
| `musica\mbwave\` (MoonBlaster for MoonSound Wave 1.17) and `musica\mbfm\` (MoonBlaster for MoonSound FM 1.03A) | Remco Schrijvers (Moonsoft); Wave 1.17 with Marcel Delorme | Distributed free of charge; no licence text ships with them |
| `musica\roboplay\` (RoboPlay 2.1: `ROBOPLAY.COM`, the `.PLY` players, `WAVES.DAT`, `YRW801.DAT`, `STANDARD.BNK`), from https://gitlab.com/torihino/roboplay | ToriHino (RoboSoft Inc.) | Simplified BSD, below |
| `musica\MUSPLAY.COM` | Albert (Papipapito), MSX SD Maker; fuente / source: `fuente/fuentes/musplay/musplay.asm` | GPL v3 |
| `UTIL\`, `musica\`, `mapper\`, `indev.com` | Various authors of the MSX scene | Freeware |
| `IA\` | Albert (Papipapito) | GPL v3 |
| `FPGA\MXUPDATE.COM` | Albert (Papipapito), proyecto MSXimus | GPL v3 |
| `FPGA\MTVOL.COM` | Albert (Papipapito), proyecto MoonTANG; fuente: `tools/msx/mtvol.asm` en https://github.com/Papipapito/MoonTANG | GPL v3 |

MSX-DOS 1 (`MSXDOS.SYS`, `COMMAND.COM`) no forma parte del código fuente de Nextor y no está cubierto por su licencia. Se incluye bajo la responsabilidad del autor de este proyecto, solo para uso no comercial.

MSX-DOS 1 (`MSXDOS.SYS`, `COMMAND.COM`) is not part of the Nextor source code and is not covered by its license. It is included under the responsibility of this project's author, for non-commercial use only.

## MSXBOOK, OneChipBook y 1chipMSX / MSXBOOK, OneChipBook and 1chipMSX

`MSXsdmaker.exe` **no** lleva el OCM-SDBIOS Pack de KdL: lo pone el usuario en la carpeta `OCM-SDBIOS` (se le pide al autor). Las BIOS, el sistema, `HELP` y `UTILS` de esas tarjetas salen de ese pack, como hacen sus `make-sdb.cmd` y `sdcreate.cmd`; sus ROMs y programas son de sus autores (KdL y los que cita el pack) y están bajo las condiciones del pack: uso personal, no comercial.

`MSXsdmaker.exe` does **not** include KdL's OCM-SDBIOS Pack: the user puts it in the `OCM-SDBIOS` folder (ask the author for it). The BIOS images, the system, `HELP` and `UTILS` on those cards come from that pack, the way its `make-sdb.cmd` and `sdcreate.cmd` do it; its ROMs and programs belong to their authors (KdL and those credited in the pack) and are under the pack's terms: personal, non-commercial use.

## Licencia de Nextor / Nextor license

Reproducida tal cual, como exige la propia licencia. / Reproduced verbatim, as the license itself requires.

```
MSX-DOS is (c) 2018 The MSX Licensing Corporation
Nextor is (c) 2018 Nestor Soriano Vilchez

Nextor is a fork of MSX-DOS and as such it makes extensive use of the MSX-DOS source code. The MSX Licensing
Corporation authorizes this usage under the following terms:

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
documentation files (the "Software"), to deal in the Software without restriction, including without limitation
the rights to use, copy, modify, merge, publish and/or distribute the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following conditions:

- The above copyright notice and this permission notice shall be included in all copies or substantial portions
  of the Software.

- Commercial usage of the Software is not allowed without explicit permission from the copyright holders.
  "Commercial usage" means selling copies of the Software, either in source code form or in binary form.

- Producing and distributing hardware that includes the Software in ROM (or in an equivalent built-in storage
  media) is allowed as long as no fee is charged for the Software itself. That is, the selling price of the
  hardware must be the same it would be if it didn't include the Software.

- Derivative works are not allowed without explicit permission from the copyright holders. "Derivative works"
  means independent projects that are created as forks of the original source code for the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO
THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
IN THE SOFTWARE.
```

## Licencia de VGMPlay / VGMPlay license

Reproducida tal cual, como exige la propia licencia. / Reproduced verbatim, as the license itself requires.

```
Copyright (c) 2015, Laurens Holst
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

## Licencia de RoboPlay / RoboPlay license

El proyecto (https://gitlab.com/torihino/roboplay) no trae fichero de licencia: su `README.md` dice «Created by RoboSoft Inc. in 2026. This work is free. You can redistribute it and/or modify it under the terms of the Simplified BSD License.» Abajo, el texto de esa licencia con su aviso, como pide para la distribución en binario.

The project (https://gitlab.com/torihino/roboplay) ships no licence file: its `README.md` says "Created by RoboSoft Inc. in 2026. This work is free. You can redistribute it and/or modify it under the terms of the Simplified BSD License." Below is the text of that licence with its notice, as it requires for binary distribution.

```
Copyright (c) 2026, RoboSoft Inc. (ToriHino)
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```
