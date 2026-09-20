# 07. WiFi y File-Hunter

La WiFi la pone un módulo ESP externo que habla con el MSX por una UART. Para el software
del MSX es una tarjeta de red **MSX UNAPI** (el estándar de Konamiman), así que sirve todo
lo que use UNAPI: clientes de red, descargas, el File-Hunter del menú, `NT.COM`, etc.

El firmware del ESP es el **UNAPI de ducasp**, en dos sabores según el módulo. El core no
distingue cuál lleva: los dos hablan a **859372 baudios** por los pines 27/28.

## Qué módulo

| | ESP-01S | ESP32-C6-LCD-1.3 |
|---|---|---|
| WiFi UNAPI | ✅ | ✅ |
| Pantalla de estado | — | ✅ 240×240 |
| Indicador de turbo | — | ✅ (pin 29) |
| TLS / HTTPS | limitado (poca RAM) | ✅ |
| Alimentación | 3,3 V de la Tang | su propio USB-C |
| Firmware | [ESP8266-UNAPI de ducasp](https://github.com/ducasp/ESP8266-UNAPI-Firmware) | [ESP32-for-FPGA](https://github.com/Papipapito/ESP32-for-FPGA) |

El cableado está en [02. Instalación](02-instalacion.md).

## Configurar la red: tecla W

Desde el menú, **W** abre la configuración del ESP: escaneo de redes, elegir una, meter
la contraseña. La configuración se guarda **en el ESP**, no en la SD ni en la flash de la
Tang, así que sobrevive a cambiar de pack o de core.

Al conectar, el ESP pone en hora el reloj (NTP). El MSX pregunta la hora por UNAPI.

## La pantalla del ESP32-C6

Si montas el C6, su pantalla enseña:

- Al arrancar, el **logo de MSX Barcelona**.
- El nombre de la red, la señal y la IP.
- La **hora**, el tiempo encendido y la temperatura del chip.
- **TURBO** iluminado cuando el MSX está a 5,37 MHz (lo lee del pin 29).
- Un punto de actividad cuando hay tráfico entre el MSX y el ESP.

## File-Hunter: tecla F

Con la red conectada, **F** en el navegador abre el buscador de
[file-hunter.com](https://www.file-hunter.com): escribes parte del nombre, sale la lista,
eliges y se descarga a `FHUNT/` en la SD. Cada descarga se verifica por **CRC32**; si no
cuadra, se avisa y no se guarda. Después el fichero aparece en el navegador como uno más.

> **Estado en el MSXnano**: probado en placa el 04/09/2026 (la primera vez que cupo en el
> pack) y funciona. Lleva menos horas de uso que en el MSXimus, donde se ha validado con
> muchas descargas: si una descarga falla, apunta el fichero y el mensaje.

## Diagnóstico

| Síntoma | Mira |
|---|---|
| W dice que no hay ESP | cables 27/28 cruzados (RX↔TX), o el ESP sin alimentación |
| Se ve el ESP pero no conecta | contraseña; redes de 5 GHz no valen (los dos módulos son de 2,4 GHz) |
| Conecta pero las descargas fallan | la señal; con un ESP-01S, HTTPS puede quedarse sin memoria |
| El C6 se reinicia al conectar | alimentación del C6: por su USB-C con una fuente decente, no del 3,3 V de la Tang |
