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

saveA8:
    .db 0
resCode:
    .db 0

sHello:
    .db 13,10,"SCCTEST - MSXnano SCC/SCC+ checker",13,10
    .db "(Stereo ON: SCC megaram=IZQ, 2o SCC=DER)",13,10,13,10,"$"
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
sBye:
    .db 13,10,"Listo.",13,10,"$"
