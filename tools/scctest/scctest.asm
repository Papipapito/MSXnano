; ============================================================================
; SCCTEST.COM -- MSXnano: detector y prueba de sonido SCC / SCC+
; ----------------------------------------------------------------------------
; Recorre los slots primarios 1-3 (cambia SOLO la pagina 2 via puerto A8) y
; para cada uno:
;  - SCC (compat): activa la ventana 9800 (bank2:9000=3F) y comprueba que la
;    wave RAM conmuta con el banco: escribe #41 con ventana ON, #BE con OFF,
;    re-activa y lee. #41 = SCC real (celdas distintas); #BE = RAM normal.
;  - SCC+: activa B800 (bank3:B000 bit7 + modo BFFE bit5) y repite la
;    comprobacion conmutando el modo.
;  - Si detecta chip toca ~0.5s de onda cuadrada (canal A, ~440Hz) en el modo
;    mas alto detectado: se OYE cada chip. Con "Stereo Sound" ON en MSXnano:
;    SCC de la megaram = canal IZQUIERDO, segundo SCC = DERECHO.
; Restaura bancos (reg2=02, reg3=03, modo=0) y el slot de pagina 2 al salir.
;
; Ensamblar:  asmsx -z scctest.asm   ->  scctest.z80  ->  renombrar SCCTEST.COM
; Uso:        copiar SCCTEST.COM a la SD y ejecutarlo desde Nextor/MSX-DOS.
; ============================================================================
    .ZILOG
    .org #0100

DOSFN    equ #0005
PSLOT   equ #A8

start:
    ld   de, sHello
    call prtstr

    ; Activar la megaram en modo SCC-I, igual que hace el menu al lanzar una ROM
    ; (en un arranque normal nadie emite este SWIO y la megaram/SCC1 esta inactiva,
    ; por eso un test en DOS no encontraria nada). OCM: dev 212 + smart cmd #0F.
    di
    ld   a, #D4
    out  (#40), a
    ld   a, #0F
    out  (#41), a
    ei
    ld   de, sSwio
    call prtstr

    ld   b, 1
slot_loop:
    push bc
    ld   a, b
    add  a, '0'
    ld   (sSlotN), a
    ld   de, sSlot
    call prtstr
    pop  bc
    push bc
    ld   a, b
    call test_slot          ; A: 0 nada / 1 SCC / 2 SCC+
    cp   2
    jr   z, .isplus
    or   a
    jr   nz, .isscc
    ld   de, sNone
    jr   .show
.isplus:
    ld   de, sPlus
    jr   .show
.isscc:
    ld   de, sScc
.show:
    call prtstr
    pop  bc
    inc  b
    ld   a, b
    cp   4
    jr   c, slot_loop

    ; =========================================================================
    ; Chips de I/O: PSG1 (A0h), PSG2 (10h, deteccion + tono), FM OPLL (7Ch)
    ; =========================================================================
    ld   de, sPsg1
    call prtstr
    di
    ld   c, #A0
    call play_psg
    ei
    ld   de, sTone
    call prtstr

    ld   de, sPsg2
    call prtstr
    di
    ld   a, 2               ; deteccion: reg 2 (8 bits) read-back en puerto 12h
    out  (#10), a
    ld   a, #5A
    out  (#11), a
    in   a, (#12)
    cp   #5A
    jr   nz, .no_psg2
    ld   a, #A5
    out  (#11), a
    in   a, (#12)
    cp   #A5
    jr   nz, .no_psg2
    xor  a                  ; limpiar reg 2 y tocar
    out  (#11), a
    ld   c, #10
    call play_psg
    ei
    ld   de, sTone2
    call prtstr
    jr   .fm
.no_psg2:
    ei
    ld   de, sNone2
    call prtstr
.fm:
    ld   de, sFm
    call prtstr
    di
    call play_fm
    ei
    ld   de, sTone
    call prtstr

    ld   de, sBye
    call prtstr
    ret                     ; volver a DOS

; ----------------------------------------------------------------------------
prtstr:                      ; DE = cadena terminada en '$'
    push bc
    ld   c, 9
    call DOSFN
    pop  bc
    ret

; ----------------------------------------------------------------------------
; test_slot: A = slot primario (1..3). Devuelve A = 0/1/2. Toca tono si > 0.
; DI durante toda la prueba; restaura A8 y los bancos al salir.
; ----------------------------------------------------------------------------
test_slot:
    di
    ld   c, a
    in   a, (PSLOT)
    ld   (saveA8), a
    and  #CF                ; limpia bits de pagina 2 [5:4]
    ld   b, a
    ld   a, c
    rrca                    ; slot 1..3 -> bits 5:4 (ror 4 == shl 4 aqui)
    rrca
    rrca
    rrca
    and  #30
    or   b
    out  (PSLOT), a

    ld   e, 0               ; E = resultado provisional

    ; ---------- SCC compat (ventana 9800, bank2 = 3F) ----------
    ld   a, #3F
    ld   (#9000), a         ; ventana ON
    ld   a, #41
    ld   (#9800), a
    xor  a
    ld   (#9000), a         ; ventana OFF
    ld   a, #BE
    ld   (#9800), a         ; esto cae en la RAM/banco normal (o en nada)
    ld   a, #3F
    ld   (#9000), a         ; ventana ON otra vez
    ld   a, (#9800)
    cp   #41                ; #41 = wave RAM propia -> SCC ; #BE = RAM normal
    jr   nz, .no_compat
    ld   a, #55             ; doble verificacion r/w con ventana activa
    ld   (#9801), a
    ld   a, (#9801)
    cp   #55
    jr   nz, .no_compat
    ld   e, 1
.no_compat:

    ; ---------- SCC+ (ventana B800, bank3 bit7 + BFFE bit5) ----------
    xor  a
    ld   (#9000), a         ; compat OFF
    ld   a, #80
    ld   (#B000), a         ; bank3 bit7 = 1
    ld   a, #20
    ld   (#BFFE), a         ; modo SCC+ ON
    ld   a, #41
    ld   (#B800), a
    xor  a
    ld   (#BFFE), a         ; modo OFF
    ld   a, #BE
    ld   (#B800), a
    ld   a, #20
    ld   (#BFFE), a         ; modo ON
    ld   a, (#B800)
    cp   #41
    jr   nz, .no_plus
    ld   a, #55
    ld   (#B801), a
    ld   a, (#B801)
    cp   #55
    jr   nz, .no_plus
    ld   e, 2
.no_plus:

    ld   a, e
    ld   (resCode), a

    ; ---------- tono en el modo mas alto detectado ----------
    or   a
    jr   z, .restore
    cp   2
    jr   z, .tone_plus
    xor  a                  ; tono SCC compat
    ld   (#BFFE), a
    ld   a, #3F
    ld   (#9000), a
    ld   hl, #9800          ; wave chA
    ld   de, #9880          ; regs
    call play_tone
    jr   .restore
.tone_plus:                 ; (bank3 bit7 + modo ya estan ON)
    ld   hl, #B800          ; wave chA
    ld   de, #B8A0          ; regs
    call play_tone

.restore:
    xor  a
    ld   (#BFFE), a         ; modo SCC+ off
    ld   a, #03
    ld   (#B000), a         ; bank3 valor por defecto
    ld   a, #02
    ld   (#9000), a         ; bank2 valor por defecto
    ld   a, (saveA8)
    out  (PSLOT), a
    ei
    ld   a, (resCode)
    ret

; ----------------------------------------------------------------------------
; play_tone: HL = base wave, DE = base regs. Cuadrada chA ~440Hz, ~0.5s.
; ----------------------------------------------------------------------------
play_tone:
    ld   b, 16              ; onda cuadrada: 16 x #60 + 16 x #A0
.w1:
    ld   (hl), #60
    inc  hl
    djnz .w1
    ld   b, 16
.w2:
    ld   (hl), #A0
    inc  hl
    djnz .w2
    ex   de, hl             ; HL = base de registros
    ld   (hl), #FD          ; +0: freq chA lo  (periodo 253 ~ 440Hz)
    inc  hl
    ld   (hl), #00          ; +1: freq chA hi
    ld   a, l
    add  a, #09             ; -> +#0A: volumen chA
    ld   l, a
    ld   (hl), #0F
    ld   a, l
    add  a, #05             ; -> +#0F: canal enable
    ld   l, a
    ld   (hl), #01          ; chA on
    push hl
    ld   b, 1               ; retardo ~0.5s (65536 x ~28T @3.58MHz)
.dly1:
    ld   de, 0
.dly2:
    dec  de
    ld   a, d
    or   e
    jr   nz, .dly2
    djnz .dly1
    pop  hl
    ld   (hl), #00          ; silencio: canal off
    ld   a, l
    sub  #05
    ld   l, a
    ld   (hl), #00          ; volumen 0
    ret

; ----------------------------------------------------------------------------
; psgw: escribe registro PSG. C = puerto base (A0h o 10h), D = reg, E = valor.
; ----------------------------------------------------------------------------
psgw:
    ld   a, d
    out  (c), a             ; seleccion de registro (base)
    inc  c
    ld   a, e
    out  (c), a             ; dato (base+1)
    dec  c
    ret

; ----------------------------------------------------------------------------
; play_psg: tono ~440Hz en canal A del PSG con base de puertos en C, ~0.5s.
; Restaura volumen y mixer al terminar. Mantiene R7 bits 7:6 = 10 (joysticks).
; ----------------------------------------------------------------------------
play_psg:
    ld   d, 0
    ld   e, #FE             ; periodo lo: 1789772/(16*440) ~ 254
    call psgw
    ld   d, 1
    ld   e, 0               ; periodo hi
    call psgw
    ld   d, 7
    ld   e, #BE             ; mixer: solo tono A (bits joystick estandar 10)
    call psgw
    ld   d, 8
    ld   e, #0F             ; volumen A max
    call psgw
    call delay_half
    ld   d, 8
    ld   e, 0               ; silencio
    call psgw
    ld   d, 7
    ld   e, #BF             ; todo off
    call psgw
    ret

; ----------------------------------------------------------------------------
; oplw: escribe registro OPLL (7Ch=reg, 7Dh=dato) con settle entre accesos.
; ----------------------------------------------------------------------------
oplw:
    ld   a, d
    out  (#7C), a
    push af
    pop  af                 ; ~21T de settle (el YM2413 real lo pide)
    ld   a, e
    out  (#7D), a
    push af
    pop  af
    push af
    pop  af
    ret

; ----------------------------------------------------------------------------
; play_fm: nota A4 (~440Hz) en canal 0 del OPLL, instrumento piano, ~0.5s.
; fnum = 440*2^18/(49716*2^(block-1)) con block 4 -> 290 = 0x122.
; ----------------------------------------------------------------------------
play_fm:
    ld   d, #30
    ld   e, #30             ; ch0: instrumento 3 (piano), volumen max (0)
    call oplw
    ld   d, #10
    ld   e, #22             ; fnum bits 7:0
    call oplw
    ld   d, #20
    ld   e, #19             ; key ON (bit4) | block 4 (bits 3:1) | fnum bit8=1
    call oplw
    call delay_half
    ld   d, #20
    ld   e, #09             ; key OFF
    call oplw
    ret

; ----------------------------------------------------------------------------
delay_half:                 ; ~0.5s con DI (65536 x ~28T @3.58MHz)
    push de
    ld   de, 0
.dh_loop:
    dec  de
    ld   a, d
    or   e
    jr   nz, .dh_loop
    pop  de
    ret

saveA8:
    .db 0
resCode:
    .db 0

sHello:
    .db 13,10,"SCCTEST v3 - MSXnano SCC+/PSG2/FM checker",13,10
    .db "(Stereo ON: SCC megaram=IZQ, 2o SCC=DER)",13,10
    .db "(2o SCC: activar 'Second SCC' en Ajustes)",13,10,13,10,"$"
sSwio:
    .db "SWIO #D4/#0F: megaram -> SCC-I slot 2",13,10,13,10,"$"
sSlot:
    .db "Slot "
sSlotN:
    .db "?: $"
sPlus:
    .db "SCC+  <tono>",13,10,"$"
sScc:
    .db "SCC   <tono>",13,10,"$"
sNone:
    .db "---",13,10,"$"
sPsg1:
    .db 13,10,"PSG 1 (A0h):  $"
sPsg2:
    .db "PSG 2 (10h):  $"
sFm:
    .db "FM OPLL (7Ch): $"
sTone:
    .db "<tono>",13,10,"$"
sTone2:
    .db "OK <tono>  (DER en stereo)",13,10,"$"
sNone2:
    .db "--- no detectado",13,10,"$"
sBye:
    .db 13,10,"Listo.",13,10,"$"
