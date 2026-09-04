# Bug #22 — MG2/Solid Snake glitchea en partida · Hallazgos del repo bladeba/MSX

> Nota de traspaso (2026-06-23). Generada tras investigar el repo público
> **github.com/bladeba/MSX** (Victor Martínez) buscando referencias para el bug #22.
> **Cómo usar esta nota:** abre una sesión nueva de Claude *dentro de*
> `C:\Users\alber\MSXnano` (así tienes CLAUDE.md + CodeGraph + este harness), di
> "lee tools/scctest/opcheck/BUG22_MG2_bladeba.md" y ataca el plan de la sección 6.

---

## 1. Estado del bug (recordatorio)
MG2/Solid Snake: intro OK, **gameplay corrupto cuando se lanza desde el menú del
nano**; va bien lanzado desde **SofaRun** (OCM). ~11 hipótesis ya descartadas.
Causa sospechada: quisquillosidad de MG2 con los **slots** (no tanto el mapper en sí).

## 2. Qué aporta bladeba/MSX (evidencia nueva)
El repo contiene **el fix comunitario exacto de este problema**:

- **`Fixes/MGEAR2-ESP-FRS-SLOTEXPANDIDO.IPS`** — parche de MG2 que incluye, entre
  otras cosas, un **"parche de slot expandido"** cuya única función es *hacer que
  MG2 funcione en un slot expandido*. Es decir: **MG2 de fábrica NO tolera correr
  desde un slot/subslot expandido** — asume que su ROM Konami-SCC de 512 KB está en
  un slot primario no expandido y usa selects de slot hardcodeados + pokes anticopia.
  (No se pudo decodificar byte a byte: 36 KB dominados por la traducción.)

- **`Fixes/Sdsnatcher-disk1.IPS`** (535 bytes, **decodificado entero**) — usa el
  mismo mecanismo de bajo nivel y lo revela. La técnica del fix de slot expandido es:
  1. En el arranque, **descubrir en runtime** el slot+subslot real donde está el
     cartucho (lee EXPTBL `0FCC1h` bit7 = slot expandido; recorre el campo de subslot
     escribiendo el byte compuesto en `0FFFFh`, que se lee **complementado**; conmuta
     el slot primario por el puerto `0A8h`).
  2. **Reescribir (auto-parchear)** los selects de slot hardcodeados del juego para
     que apunten al subslot descubierto, de modo que las conmutaciones de banco y las
     escrituras al **banco 0x3F (= registros de la SCC, NO un bank-switch real)** se
     enruten al slot correcto.
  - Handshake SCC canónico que confirma: `LD (#9000),#3F` arma la SCC y entonces la
    ventana `#9800` revela su wave-RAM (write/CPL/read-back). Idéntico a lo que ya
    hace nuestro `scctest.asm`.

- **`SRC/Miscellaneous/Search_SCC.asm`** — versión "limpia" del barrido de
  slot/subslot buscando la SCC (EXPTBL bit7 + ENASLT `#0024` + sonda `#9000`/`#9800`).

**Conclusión:** el fix oficial trata el bug como *"MG2 no sabe correr en slot
expandido"*. Y resulta que **el nano lanza la ROM en un subslot expandido** (ver §3).

## 3. Por qué encaja con nuestro RTL (rutas exactas)
`tools/scctest/opcheck/slotchk.txt` ya documenta: la ROM lanzada queda en
**slot 0, subslot 3** (`@4000 = 4C 47 F3`). Y en el RTL:

- **`fpga/top.v:921`** — comentario `//expanded slots 0 & 3`.
- **`fpga/top.v:932-947`** — decodificación de `xffff` (registro de subslot `0FFFFh`),
  `pri_slot_num`, `exp_slotx_num`.
- **`fpga/top.v:908-909`** — PPI puerto `A8h` (registro de slot primario).
- **`fpga/top.v:1597`** — `scc2_req3` (la megaram/SCC del cartucho) se habilita con
  `pri_slot == config_megaram_slot && exp_slotx_num[3] == 1 && xffff == 0`.
  ⇒ **La megaram + su SCC viven en un subslot EXPANDIDO (subslot 3).**
- **`fpga/top.v:1211`** — `mapper_req3` también gateado por `exp_slotx_num[0] && xffff==0`.

Es exactamente el escenario para el que existe el parche de slot expandido de bladeba.

## 4. Las dos hipótesis (refinadas con el RTL real)

### Hipótesis A — interacción con el SLOT EXPANDIDO  ← lead más fuerte
MG2 se lanza desde el menú en **slot 0 / subslot 3 (expandido)**; MG2 de fábrica no
tolera eso. **SofaRun va bien** probablemente porque deja a MG2 en un contexto de slot
que sí espera (primario no expandido) o porque corre bajo DOS con la SCC ya colocada.

Acciones:
1. **Comparar la colocación de slot menú vs SofaRun**: instrumentar con openMSX
   (extender `nano_slotchk.tcl`) y volcar, en el momento del lanzamiento, el estado de
   `pri_slot_num` / `exp_slotx_num` / `xffff` y los selects que hace MG2.
2. **Probar a lanzar MG2 en un slot primario NO expandido** (replicar lo que hace
   SofaRun). Si la corrupción desaparece → confirmada A. Mirar dónde el menú decide
   `config_megaram_slot` / la colocación en subslot 3 y si se puede ofrecer una ruta
   "primario plano" para cartuchos quisquillosos.
3. **Auditar el camino de subslot expandido del SCC**: revisar que cuando MG2 accede a
   la SCC *a través del subslot 3*, el decode de `megaram.v` (ventana `#9800`, banco
   `#3F`, regs `#B000`/`#BFFE`) responde igual que por un slot plano. Posible fallo:
   que `xffff==0` / `exp_slotx_num[3]` deseleccione la ventana SCC en algún acceso que
   MG2 hace creyendo estar en su slot.

### Hipótesis B — regla "banco 0x3F = SCC, no bank-switch"  ← parece YA resuelta
**OJO: esto ya está implementado.** No rehacer; solo verificar de refilón.
- `fpga/src/megaram.v:36-61` — la ventana `#9800` solo se abre con
  `megaram_reg2[5:0]==6'b111111` (= 0x3F) y en modo SCC (`ff_scc_mode`,
  `map_sel==2'b10`); en Konami4/ASCII un 0x3F en reg2 **no** abre la ventana.
- `fpga/src/megaram.v:45-52` — `ff_scc_mode` registrado, comentado como
  *"fix timing regresion MG2 v1.7"*.
- `fpga/src/megaram.v:214-224` — guard explícito: *"MG2 hace pokes anticopia a
  BFFE/7FFE que en una megaram abierta habilitan escritura"* → ya contemplado.

→ La causa del bug probablemente **no** está aquí. Solo confirmar contra el modelo de
referencia (§7) que no quede ningún caso de 0x3F mal interpretado **bajo subslot
expandido**.

## 5. Qué NO rehacer
- El handshake/conformidad SCC ya lo cubre `tools/scctest/scctest.asm` (slots 1-3 vía
  A8; SCC compat + SCC+). La **regla 0x3F** y los **guards anticopia de MG2** ya están
  en `megaram.v`. El foco nuevo es el **camino expandido (subslot 3)**, no el mapper.

## 6. Plan de ataque para la próxima sesión (en orden)
1. Leer esta nota + `git log` reciente de `fpga/top.v` y `fpga/src/megaram.v`
   (`ff_scc_mode`/v1.7) para no repetir lo ya probado.
2. **Extender `scctest.asm`**: hoy solo recorre slots **primarios** vía `A8`. Añadir un
   modo que coloque/pruebe la SCC **a través de un subslot expandido** (escribir `0FFFFh`
   complementado, como Search_SCC.asm) y verificar que la ventana `#9800`/regs SCC+
   responden igual que por slot plano. Esto reproduce el acceso de MG2 en subslot 3.
3. **Trace en openMSX (réplica `MSXnano_test`)** con `mg2_launchglitch.tcl` +
   `nano_slotchk.tcl` extendido: capturar, en el frame donde aparece la corrupción, los
   selects de slot/subslot de MG2 y los accesos a `#9000`/`#9800`/`#B000`/`#BFFE`.
   Comparar **menú vs SofaRun** lado a lado.
4. Según el resultado:
   - Si A: ajustar el menú/loader para presentar MG2 en primario no expandido, **o**
     corregir el decode SCC bajo `exp_slotx_num[3]` en `megaram.v`/`top.v`.
   - Recordar la restricción del proyecto: **NUNCA reset HW al lanzar** (la megaram
     decae con la recarga de flash) — la solución debe ser por colocación/decode, no por reset.
5. Regresión: re-probar MG2 (intro+gameplay), Solid Snake, y otros Konami-SCC, más el
   `SCCTEST.COM` en HW, antes de mergear (rama desde `dev`).

## 7. Referencias
- **Modelo de oro** (cómo debe comportarse la MegaFlashROM SCC+ SD):
  openMSX `src/memory/MegaFlashRomSCCPlusSD.cc`
  (https://github.com/openMSX/openMSX/blob/master/src/memory/MegaFlashRomSCCPlusSD.cc)
- Mapper/SCC Konami + detección: https://www.msx.org/wiki/MegaROM_Mappers ·
  http://bifi.msxnet.org/msxnet/tech/soundcartridge · http://bifi.msxnet.org/msxnet/tech/scc
- Problema slot expandido de MG2 + slotfix:
  https://www.msx.org/forum/msx-talk/software/metal-gear-solid-snake-through-megaflashrom-scc-512k-not-working
- FRS Turbo Fix (parte "FRS" del IPS, timing R800): https://frs.badcoffee.info/patches.html ·
  https://www.msx.org/news/development/en/turbo-fix-patch-metal-gear-2
- Repo fuente de los hallazgos: https://github.com/bladeba/MSX (carpetas `Fixes/`, `SRC/Miscellaneous/`)

## 10. CORRECCION IMPORTANTE (2026-06-23) — MG2 arranca en SLOT 2 PLANO

Al leer la secuencia de lanzamiento real (`menu_main.asm` `boot_stub`, ~1873-1897)
se descubre que **el lanzador NO pone MG2 en un subslot expandido**: hace
`ld a,#02 / call ENASLT` para páginas 1 y 2 → **primario 2, PLANO** (id #02 con
bit7=0). Como MG2 arranca (intro OK), la megaram responde ahí: **slot 2 plano**,
igual que bajo SofaRun. El "slot 0/subslot 3" de `slotchk.txt` era de la **réplica
openMSX** (`.tcl` hardcodeado); el "slot 3 expandido / config_megaram_slot=2'b11"
del análisis RTL era la **rama fallback** (sin flash-config), no la activa
(`config_megaram_slot = config1_ff[7:6] = var_megslt = slot 2`; `MEG_SLOT equ #02`).

**Implicaciones:**
- La teoría de bladeba ("MG2 no tolera slot expandido") **NO aplica a nuestro
  lanzador**: ya usamos un slot plano. La extensión `test_subslot` de §9 prueba un
  camino (subslot 3 expandido) que MG2 **no usa al arrancar** → no es la ruta del
  bug #22 (queda como diagnóstico SCC general, no como sonda de #22).
- Los 3 "forks" del RTL de §9 (scc_sound_disable, CDC exp_slotx_num[3], doble
  contabilidad) son diferencias del camino EXPANDIDO `*_req3`; MG2 usa el PLANO
  `*_req12` → tampoco aplican.
- El bug está en la **secuencia de lanzamiento** (VDP/paleta/cerrojo/H.STKE) vs un
  arranque limpio BIOS/SofaRun. Encaja con el síntoma: el fundido-a-negro por
  cambio de paleta tras el logo azul no ocurre. Es SOFTWARE (`menu_main.asm`), sin
  recompilar FPGA.

**Siguiente real (§6 paso 3, reenfocado al VDP):** trazar en openMSX las escrituras
de paleta/VDP de MG2 durante el fundido (puerto `#9A`, R#16/R#17 vía `#99`)
**menú vs SofaRun** y localizar la divergencia. (El `launch_rom` hace INIT32 +
vdp_clean_tbl + restore_palette + cerrojo mode_a=0x80 antes del INIT del cartucho:
sospechosos de alterar el estado VDP que MG2 espera.)

## 11. CAUSA RAIZ + FIX (2026-06-23) — motor de comandos VDP residual

**El glitch NO se reproduce en la réplica openMSX** (MG2 lanzado por el menú llega
limpio a título y gameplay: `lg_06/08/10.png`). → es **específico del FPGA**.
Cruzado con que SofaRun va bien en el mismo FPGA, la causa es:

> El **logo de arranque** (MSX Barcelona) pinta su bitmap con **comandos VDP** y
> deja el motor del V9938/58 **a medias (CE asserted) + R32-R46 sucios**. El
> `launch_rom` reinicia R0-R27 y la paleta pero **NUNCA toca el bloque de comandos
> (R32-R46) ni drena CE**. MG2, al entrar, hace su **HMMV de borrado** (el fundido
> a negro / limpiar la página de trabajo, trace `mg2_io.txt` L61076-61088: HMMV
> DX=40,DY=832,NX=168,NY=72,CLR=0 en SCREEN 5); con el motor aún "ocupado" para el
> FPGA ese borrado no cuaja → los 103 HMMM del título se componen sobre VRAM sin
> limpiar → "la pantalla de carga se mezcla con el juego".

Encaja con las 3 restricciones: (a) FPGA-only — openMSX modela el motor instantáneo
y el abort de libro; el RTL real tiene handshake CE + gate STIDLE/CMRWR
(`vdp_command.vhd:458-502`). (b) menú falla / SofaRun limpio — el `launch_rom`
provablemente no tiene ningún `out(#99)` a registro ≥32 ni lectura de S#2; SofaRun
corre bajo DOS con el motor ocioso. (c) síntoma = el HMMV de borrado no surte efecto.

**FIX (software, sin recompilar FPGA)** — `menu_main.asm`, rutina `vdp_cmd_abort`
llamada en `launch_rom` justo antes de saltar a `boot_stub`: como acabamos de hacer
INIT32 → SCREEN 1, ahí `W_VDPCMD_EN=0`, así que escribir **R#46=0 fuerza STIDLE y
limpia CE** (verificado en `vdp_command.vhd:458-502` / `198-199`). Se limpian
R32-R45 (ARG/coords) y R46 el ÚLTIMO. Build: `make clean && make rom` (OK, asMSX) +
inyectado en `goauld_rom_int.bin` @0x6C000. **PENDIENTE: validar en HW** (flashear
pack, lanzar MG2 desde el menú, confirmar que hace el fundido a negro).

**Confianza ~75-90%.** Si NO lo arregla: (1) añadir drenaje de S#2 (poll CE) antes
del abort; (2) si persiste, es el latch de modo en HSYNC (`vdp_register.vhd:319-329`
alimentando el command engine combinacional) → fix RTL con rebuild. Detalle completo
en el workflow `ws5gmr3zn`. Dato sin verificar (eslabón): que el logo deje CE=1 —
confirmable trazando el logo (no MG2) en openMSX, o por el propio resultado en HW.

## 9. Progreso (2026-06-23) — §6 paso 2 HECHO

**`scctest.asm` extendido a v4** con el camino de **subslot expandido** (rutina
`test_subslot`), handshake refactorizado (`scc_handshake` + `scc_restore_banks`
compartidos por el camino plano y el expandido → comparación apples-to-apples).
Revisado adversarialmente contra el RTL (0 bugs en pila/slot, máscaras A8,
round-trip de `#FFFF`, scoping de labels, DI/EI). **Falta**: ensamblar
(`asmsx -z scctest.asm` → `SCCTEST.COM`) y correr en HW.

**Verdades de campo confirmadas contra el RTL (corrigen suposiciones previas):**
- La megaram/SCC vive en **primario 3 / subslot 3 (expandido)** — `config_megaram_slot
  = config1_ff[7:6] = 2'b11` (top.v:2014/2045), y `scc2_req3` exige
  `pri_slot==3 && exp_slotx_num[3]==1 && xffff==0` (top.v:1597). El "slot 2" del
  comentario de scctest = nomenclatura OCM del *modo*, no el slot MSX; el "slot 0"
  de slotchk venía del `.tcl` hardcodeado (réplica openMSX), no del HW real.
- `map_sel = Slot2Mode` (top.v:1612); **el SWIO `#D4/#0F` ya arma `map_sel=10`
  (modo SCC)** (menu_main.asm:1448-1452) → no hace falta SWIO extra para la ventana.
- `#FFFF` se guarda PLANO (top.v:966) y se lee COMPLEMENTADO; la escritura solo
  cuaja si la página 3 es primario 3 (top.v:940).
- Acceso correcto a la SCC por subslot 3: A8 pág2=3 (`[5:4]=11`) + `#FFFF`=`#F0`
  (pág2 sub3) con pág3=3 momentáneo para la escritura.

**Cómo leer el resultado en HW:** la nueva línea `Subslot exp (pri3/sub3): SCC/SCC+/---`.
Como la megaram solo responde expandida, lo esperado es `Slot 3: ---` (barrido plano)
**y** `Subslot exp: SCC` → confirma que la SCC vive en el subslot expandido. Si el
expandido también da `---`, el decode estático del subslot está roto (ver abajo).

**Candidatos de causa raíz del RTL (forks que solo existen en el camino expandido
`*_req3`, no en el plano `*_req12`) — leads para el paso 3:**
1. **`scc_sound_disable` asimétrico (top.v:1557 vs 1558):** `scc_req3` NO está gateado
   por `scc_sound_disable`, `scc_req12` SÍ. Los pokes anticopia de MG2 a `#7FFE/#BFFE`
   tocan ese bit → la ventana de sonido se comporta distinto en el camino que MG2 usa.
   **Lead más accionable.**
2. **CDC `exp_slotx_num[3]` (top.v:966 clk_27m → 1594 clk_54m):** el camino plano no
   tiene término `exp_slotx_num`; el expandido sí, cruzando dominios. Un bank-switch
   in-game podría desincronizar y deseleccionar la megaram un frame. **No reproducible
   con sonda estática** → si la sonda pasa pero el glitch persiste, este es el sospechoso.
3. **Doble contabilidad `megaram_reg2` (megaram.v:202, con guard) vs `scc_bank2`
   (top.v:1532, sin guard):** tras los pokes de modo pueden divergir → ventana abierta
   en un decoder y no en el otro.

**Siguiente (§6 paso 3):** trazar en openMSX (réplica `MSXnano_test`) los selects de
slot/subslot y accesos a `#9000/#9800/#B000/#BFFE` en el frame de la corrupción,
**menú vs SofaRun** lado a lado (`mg2_launchglitch.tcl` + `nano_slotchk.tcl` extendido).

## 8. Licencia / cuidado
bladeba/MSX **no tiene licencia** (todos los derechos reservados). Los *algoritmos*
(handshake SCC, barrido de slot/subslot, regla 0x3F) no son copyrightables y están
documentados en las fuentes de §7 → **reimplementar clean-room** (es lo que ya hacemos).
**No** incrustar ni redistribuir las ROMs/IPS parcheadas (Konami MG2 + traducción de
Pazos + parche de FRS). Usarlas solo como referencia privada de comportamiento.
