# 05. ROMs y mappers

No hay slot de cartucho: las ROMs se cargan desde la SD en una **Megaram de 2 MB** que
vive en el **slot 2** y que sabe comportarse como los mappers más comunes. El menú copia
el fichero a la Megaram, le dice al hardware qué mapper imitar, y reinicia el MSX con el
"cartucho" puesto.

## Los mappers que hay en el hardware

`fpga/src/megaram.v` implementa cuatro modos, seleccionables por el menú:

| Modo | Mapper | Bancos | Registros de cambio de banco |
|---|---|---|---|
| Konami4 | Konami sin SCC | 8 KB | 0x6000 · 0x8000 · 0xA000 (el banco de 0x4000 es fijo) |
| Konami SCC | Konami con SCC | 8 KB | 0x5000 · 0x7000 · 0x9000 · 0xB000 |
| ASCII8 | ASCII de 8 KB | 8 KB | 0x6000 · 0x6800 · 0x7000 · 0x7800 |
| ASCII16 | ASCII de 16 KB | 16 KB | 0x6000 · 0x7000 |

Las ROMs **planas** (16 KB, 32 KB, 48 KB sin mapper) se cargan tal cual, sin cambio de
banco. Cubre la inmensa mayoría de lo que existe para MSX1/MSX2: Konami, la generación
ASCII, y los cartuchos sencillos.

Lo que **no** está: mappers exóticos (R-Type de 384 KB, Cross Blaim, Harry Fox, los NEO
modernos, SRAM de cartucho tipo Game Master 2 o Koei). Algunos los tiene el MSXimus; aquí
no cabían.

## Cómo se decide el mapper

En este orden:

1. **Etiqueta en el nombre del fichero**: `Juego [KonamiSCC].rom`, `[ASCII8]`, `[ASCII16]`,
   `[Konami4]`. Es lo más fiable, y lo que te recomiendo si un juego no arranca.
2. **Heurística**: la cabecera `AB`, el tamaño, y un barrido del código buscando escrituras
   a las direcciones de los registros de banco de cada mapper.
3. Si nada encaja: **ROM plana**.

El barrido de código falla con juegos que cambian de banco con `LD (HL),A` en vez de con
una escritura directa (Ikari, por ejemplo): para esos, la etiqueta.

## Forzar el mapper: tecla M

En el navegador, con la ROM seleccionada, **M** cicla entre los tipos. El mapper forzado
se muestra en la pantalla de lanzamiento. No se guarda: si quieres que sea permanente,
pon la etiqueta en el nombre.

## La Megaram desde el software

Para el software que corre en el MSX, la Megaram es una **Megaram SCC estándar en el slot 2**:
2 MB, con el registro de control habitual. **SofaRun** la detecta sola y carga ROMs desde
MSX-DOS sin pasar por el menú. Otros cargadores (por ejemplo `ODO`) puede que necesiten
que les digas el slot a mano.

## Dos SCC

El core lleva **dos SCC+**: el de la Megaram y un segundo que se activa en Ajustes
(*Second SCC*). Con los dos, el software que pide "SCC en dos slots" (Konami SCC-I, algunos
reproductores) lo encuentra. Los dos suenan mezclados en estéreo con el resto.

## Lo que no arranca y por qué

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| Pantalla negra tras lanzar | mapper mal detectado | etiqueta o tecla M |
| Arranca y se cuelga al cambiar de nivel | mapper casi bien (8 vs 16 KB) | probar el otro ASCII |
| "Se ve" pero sin sonido de SCC | ROM etiquetada Konami4 siendo SCC | `[KonamiSCC]` |
| ROM de más de 2 MB | no cabe en la Megaram | no hay solución aquí |
| ROM con SRAM (guardado) | el guardado es volátil | se pierde al apagar; ver [pendientes](../tecnica/09-pendientes.md) |
