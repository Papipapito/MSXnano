# Documentación del MSXnano

Índice general. El [README](../README.md) del repositorio (en inglés) se queda corto a
propósito: qué es, qué hace falta y cómo se instala. Todo lo demás vive aquí.

Estado del proyecto: **v2.0, cerrado** (release [`v2.0-final`](https://github.com/Papipapito/MSXnano/releases/tag/v2.0-final), 23/09/2026). El core ocupa el ~89 % de la lógica del chip y no
queda sitio para funcionalidades nuevas. Lo que hay funciona y está validado en placa; lo
que se quedó fuera está documentado en [pendientes y aparcado](tecnica/09-pendientes.md)
para quien quiera retomarlo.

## Cómo está organizada

| Carpeta | Para quién | Qué contiene |
|---|---|---|
| `docs/manual/` | Quien tiene la placa y quiere usarla | Instalación, tarjeta SD, menú, ROMs, teclado y ratón, WiFi, audio y vídeo, carcasa, problemas |
| `docs/tecnica/` | Quien quiere entender o modificar el core | Arquitectura, puertos de E/S, mapas de memoria, pack de BIOS, protocolo del companion, síntesis y timing, simulación, changelog, pendientes |
| `docs/historico/` | Nadie en particular | Índice de los documentos de diseño y las cazas de bugs que se conservan por si explican una decisión, pero que ya no describen el estado actual |

Idioma: castellano. El README y el `case/README.md` están en inglés porque son la puerta
de entrada pública.

## Manual de usuario (`docs/manual/`)

| Nº | Capítulo | De dónde sale |
|---|---|---|
| 01 | [Qué es el MSXnano](manual/01-que-es.md): la máquina, lo que trae, lo que hace falta, lo que no es | README, top.v |
| 02 | [Instalación](manual/02-instalacion.md): flashear el core y el pack, el RP2040, el ESP-01S o el ESP32-C6, cableado, actualizar | README, firmwares |
| 03 | [La tarjeta SD](manual/03-tarjeta-sd.md): formato, qué poner, Nextor | menú, Nextor |
| 04 | [El menú de arranque](manual/04-menu.md): Ajustes, navegador, lanzar ROM y disco, Boot Turbo, File-Hunter | bios-msxnano-msximus |
| 05 | [ROMs y mappers](manual/05-roms-mappers.md): la megaram, los mappers, cómo se decide, el forzado manual | megaram.v, menú |
| 06 | [Teclado, ratón y joystick](manual/06-teclado-raton-joystick.md): el companion RP2040, el mapa de teclas, F11, el ratón MSX, autofire, hubs | rp2040/, kbd_uart_rx.v, msx_mouse.v |
| 07 | [WiFi y File-Hunter](manual/07-wifi-file-hunter.md): ESP-01S o ESP32-C6, la tecla W, la tecla F, la pantalla del C6 | README, ESP32-for-FPGA |
| 08 | [Audio, vídeo y turbo](manual/08-audio-video-turbo.md): los chips, estéreo por HDMI, scanlines, el turbo Panasonic y cómo activarlo | top.v, tn_vdp |
| 09 | [La carcasa](manual/09-carcasa.md): piezas, las dos tapas, impresión, montaje, lista de materiales | case/, docs/BOM.md |
| 10 | [Problemas frecuentes](manual/10-problemas.md): por síntoma, con causa probable y qué hacer | todo lo anterior |

## Referencia técnica (`docs/tecnica/`)

| Nº | Capítulo | De dónde sale |
|---|---|---|
| 01 | [Arquitectura](tecnica/01-arquitectura.md): relojes, módulos, mapa de ficheros, defines de compilación | top.v, build.tcl |
| 02 | [Puertos de E/S](tecnica/02-puertos-es.md): todos los puertos que decodifica el core, propios y estándar | top.v, submódulos |
| 03 | [Mapas de memoria](tecnica/03-mapas-memoria.md): slots, SDRAM, flash | top.v, README |
| 04 | [El pack de BIOS](tecnica/04-pack-bios.md): anatomía byte a byte, cómo se monta, qué es propietario | bios-msxnano-msximus |
| 05 | [El companion RP2040](tecnica/05-companion-rp2040.md): el protocolo UART congelado, teclado, joystick, ratón, latencia | kbd_uart_rx.v, msx_mouse.v, usbin.c |
| 06 | [Síntesis y timing](tecnica/06-sintesis-timing.md): Gowin, ocupación, relojes críticos, campañas, **por qué no cabe más** | build.tcl, commits |
| 07 | [Simulación](tecnica/07-simulacion.md): Icarus en WSL, los testbenches que hay | tools/ |
| 08 | [Changelog](tecnica/08-changelog.md): de la v1.0 a la v2.0 | tags, releases |
| 09 | [Pendientes y aparcado](tecnica/09-pendientes.md): lo que se sabe y no se hizo, con su porqué | auditorías, sesiones |

## Histórico (`docs/historico/`)

[Índice](historico/README.md) de los documentos que se conservan tal cual: la auditoría
previa al porte al 60K, el diseño del frontend gráfico, la caza del bug de Metal Gear 2 y
el expediente de la doble interrupción de línea.

## Otros repositorios del proyecto

| Repositorio | Qué es |
|---|---|
| `bios-msxnano-msximus` (**privado**) | El menú de arranque y las herramientas que montan el pack de BIOS. Fuente único para las dos máquinas; los packs ya montados van en la release |
| [ESP32-for-FPGA](https://github.com/Papipapito/ESP32-for-FPGA) | Firmware del ESP32-C6 (WiFi UNAPI + pantalla) |
| [MSXimus](https://github.com/Papipapito/MSXimus) | El hermano mayor, en la Tang Console 60K |
| [msx-turbo](https://github.com/Papipapito/msx-turbo) | `TURBO.COM`: activar y desactivar el turbo desde MSX-DOS |
