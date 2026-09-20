# 10. Problemas frecuentes

Por síntoma. Cada entrada dice la causa más probable primero.

## Arranque

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| Pantalla negra, ningún LED de actividad | El core no está grabado, o el Programmer lo grabó en SRAM en vez de en la flash | Regrabar el `.fs` en modo *External Flash*, dirección `0x000000` |
| Logo y luego nada, o basura | Falta el pack, o está en la dirección equivocada | Grabar el pack en `0x200000` con *exFlash C Bin Erase, Program thru GAO-Bridge* |
| El menú avisa de versión distinta | Core y pack de versiones diferentes | Actualizar los dos; van emparejados |
| Arranca en BASIC en vez de MSX-DOS | No hay `NEXTOR.SYS` + `COMMAND2.COM` en la raíz de la SD | Copiarlos de la distribución de Nextor |
| Arranca directo a DOS y quiero el menú | *Menu al arrancar* desmarcado | S → marcar → Save & Restart |
| Se reinicia solo en bucle | Alimentación: el USB-C de un PC a veces no da corriente suficiente con la Pico y un hub colgando | Fuente USB de solo corriente, de 2 A |

## Teclado, ratón, mando

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| Sin teclado | La Pico sin firmware, sin alimentación, o el cable del pin 31 | LED de la Pico encendido; regrabar el `.uf2`; comprobar GP15 → pin 31 |
| Teclado va, pero se queda una tecla pulsada | No debería: el vigilante de 1 s lo suelta todo | Si pasa, cable del pin 31 con mal contacto |
| El teclado funciona a ratos con un hub | Hub sin alimentación propia | Hub alimentado |
| El mando no hace nada | Mando no HID o modo raro | Probar el interruptor XInput/DInput si lo tiene; otro mando |
| El ratón no se mueve | El software no usa ratón MSX, o está en el puerto 1 | El ratón vive en el puerto 2; el LED de la Pico en cian confirma que está montado |
| La ñ no sale | La BIOS internacional no la tiene | Pendiente; ver [tecnica/09](../tecnica/09-pendientes.md) |
| F11 no cambia el turbo | Estás en un software que lo fija por los puertos Panasonic | Es lo correcto: gana el software |

## ROMs y discos

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| ROM que no arranca | Mapper mal detectado | Etiqueta `[KonamiSCC]`/`[ASCII8]`/`[ASCII16]`/`[Konami4]` en el nombre, o tecla M |
| Se cuelga al cambiar de nivel | Mapper casi bien | Probar el otro tamaño de ASCII |
| ROM mayor de 2 MB | No cabe en la Megaram | Sin solución aquí |
| El guardado del juego desaparece | La SRAM es volátil en esta máquina | Pendiente; ver [tecnica/09](../tecnica/09-pendientes.md) |
| Disco que no monta | Imagen no estándar (no 720 KB / 360 KB) o corrupta | Comprobar la imagen en un emulador |
| La SD no se ve | No es FAT32, o partición extendida | Formatear FAT32, partición primaria |

## WiFi

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| W dice que no hay ESP | RX/TX cruzados o ESP sin alimentar | Pin 27 = entrada del ESP (RX), pin 28 = salida (TX) |
| No conecta a la red | Red de 5 GHz | Los módulos son de 2,4 GHz |
| El C6 se reinicia al conectar | Alimentación del C6 | Por su propio USB-C con una fuente decente |
| File-Hunter falla | Sin red, CRC que no cuadra, o SD llena | Reintentar; si se repite con un fichero concreto, apuntar el nombre; ver [07](07-wifi-file-hunter.md) |

## Vídeo y sonido

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| El monitor no detecta señal | Algunos monitores no negocian bien | Otro cable / otro monitor; un televisor suele ser más tolerante |
| Sin sonido | El HDMI es la única salida | El monitor tiene que tener altavoces, o pasar por un extractor de audio HDMI |
| Solo suena un lado | *Stereo Sound* activado y el software solo usa PSG | Es normal: el PSG va a un lado; desactívalo si prefieres mono |
| R-Type con smooth-scroll tiembla | Bug conocido de la interrupción de línea | Arreglo escrito pero no cabe; ver [tecnica/09](../tecnica/09-pendientes.md) |
| Los blancos se ven grises | Expansión de paleta del core | Conocido; ver [tecnica/09](../tecnica/09-pendientes.md) |
| Parpadeo de sprites que no debería estar | *Sprites 8/línea* activado | Desactivarlo (o activarlo si el juego lo necesita) |

## Cómo reportar un problema

Un issue en [github.com/Papipapito/MSXnano](https://github.com/Papipapito/MSXnano/issues)
con: versión del core (Ajustes → *Version FPGA*), pack que usas, qué companions tienes
montados, y el software concreto que falla. Una foto de la pantalla vale más que una
descripción.
