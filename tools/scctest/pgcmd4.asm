; ============================================================================
; PGCMD.ROM v4 -- MSXnano: repeticion de comandos FIEL A MG2 (bug #22)
; ----------------------------------------------------------------------------
; v3 demostro que su Fase C era un ARTEFACTO: re-usaba NY (lo ponia una vez y
; no lo reescribia por tira). El FPGA camina NY en sitio (no hace snapshot), asi
; que NY=0 en la tira 2 -> copia gigante -> basura. En openMSX salia LIMPIO
; (el V9958 real tolera el re-uso). MG2 NO re-usa: reescribe el BLOQUE COMPLETO
; (R#32..R#46, incl. NY) por comando via R#17 autoincremento (puerto #9B).
;
; v4 replica EXACTAMENTE eso:
;  FASE A (borde AZUL):  1 LMMM grande (control)            -> LIMPIO esperado.
;  FASE B (borde CIAN):  1 LMMM con X!=0 (mitad derecha)    -> LIMPIO esperado.
;  FASE C (borde BLANCO):14 LMMM, cada uno con BLOQUE COMPLETO de 15 bytes a
;        #9B (igual que MG2), NY=16 REESCRITO en cada comando, DY variando.
;
; Veredicto:  C LIMPIO  -> el motor de comandos esta BIEN; el bug de MG2 no es
;                          la repeticion de comandos. (mis tests previos = arte-
;                          facto del re-uso de NY).
;             C BASURA  -> hay un bug REAL de repeticion de comandos de bloque
;                          completo (= patron de gameplay de MG2).
;
; Bucle infinito; salir = RESET. Cartucho 16K. No escribe a la ROM.
; ============================================================================
    .ZILOG
    .org #4000

    .db  "AB"
    .dw  init
    .dw  0
    .dw  0
    .dw  0

init:
    di
    ld   a, #06
    out  (#99), a
    ld   a, #80|0
    out  (#99), a
    ld   a, #40
    out  (#99), a
    ld   a, #80|1
    out  (#99), a
    ld   a, #1F
    out  (#99), a
    ld   a, #80|2
    out  (#99), a
    xor  a
    out  (#99), a
    ld   a, #80|9
    out  (#99), a
    xor  a
    out  (#99), a
    ld   a, #80|13
    out  (#99), a
    xor  a
    out  (#99), a
    ld   a, #80|25
    out  (#99), a
    ; paleta 1=ROJO 2=VERDE
    ld   a, 1
    out  (#99), a
    ld   a, #80|16
    out  (#99), a
    ld   a, #70
    out  (#9A), a
    ld   a, #00
    out  (#9A), a
    ld   a, #00
    out  (#9A), a
    ld   a, #07
    out  (#9A), a
    ; pagina 1 (oculta) = VERDE
    ld   a, 2
    ld   e, #22
    call fill16k
    ld   a, 3
    ld   e, #22
    call fill16k

main:
    ; ===== FASE A: borde AZUL, 1 copia grande X=0 (control) =====
    ld   a, #04
    out  (#99), a
    ld   a, #80|7
    out  (#99), a
    call fill_page0_red
    call wait_ce
    ld   hl, lmmm_full
    call cmd_exec
    call wait_ce
    call delay4

    ; ===== FASE B: borde CIAN, 1 LMMM con X!=0 (mitad derecha) =====
    ld   a, #07
    out  (#99), a
    ld   a, #80|7
    out  (#99), a
    call fill_page0_red
    call wait_ce
    ld   hl, lmmm_right
    call cmd_exec
    call wait_ce
    call delay4

    ; ===== FASE C: borde BLANCO, 14 tiras, BLOQUE COMPLETO por comando (FIEL A MG2) =====
    ld   a, #0F
    out  (#99), a
    ld   a, #80|7
    out  (#99), a
    call fill_page0_red
    ld   e, 0                  ; E = DY = 0,16,...,208 (14 tiras)
.sc:
    call wait_ce
    ; --- bloque COMPLETO R#32..R#46 via R#17 autoincremento (como MG2) ---
    ld   a, 32
    out  (#99), a
    ld   a, #80|17
    out  (#99), a             ; R#17 = 32 (autoinc ON -> apunta a R#32)
    xor  a
    out  (#9B), a             ; R#32 SX_lo = 0
    out  (#9B), a             ; R#33 SX_hi = 0
    ld   a, e
    out  (#9B), a             ; R#34 SY_lo = DY
    ld   a, 1
    out  (#9B), a             ; R#35 SY_hi = 1  (SY = DY+256, fuente = pagina 1)
    xor  a
    out  (#9B), a             ; R#36 DX_lo = 0
    out  (#9B), a             ; R#37 DX_hi = 0
    ld   a, e
    out  (#9B), a             ; R#38 DY_lo = DY
    xor  a
    out  (#9B), a             ; R#39 DY_hi = 0
    out  (#9B), a             ; R#40 NX_lo = 0
    ld   a, 1
    out  (#9B), a             ; R#41 NX_hi = 1  (NX = 256)
    ld   a, 16
    out  (#9B), a             ; R#42 NY_lo = 16  <-- REESCRITO en CADA comando
    xor  a
    out  (#9B), a             ; R#43 NY_hi = 0
    out  (#9B), a             ; R#44 CLR = 0
    out  (#9B), a             ; R#45 ARG = 0
    ld   a, #90
    out  (#9B), a             ; R#46 CMD = LMMM -> dispara
    ld   a, e
    add  a, 16
    ld   e, a
    cp   224
    jr   c, .sc               ; 14 tiras (DY 0..208)
    call delay4
    jp   main

; ----------------------------------------------------------------------------
cmd_exec:                       ; HL -> 15 bytes -> R#32..R#46 (autoincremento)
    ld   a, 32
    out  (#99), a
    ld   a, #80|17
    out  (#99), a
    ld   b, 15
.ce_l:
    ld   a, (hl)
    out  (#9B), a
    inc  hl
    djnz .ce_l
    ret

wait_ce:
    ld   a, 2
    out  (#99), a
    ld   a, #80|15
    out  (#99), a
.wc:
    in   a, (#99)
    and  1
    jr   nz, .wc
    xor  a
    out  (#99), a
    ld   a, #80|15
    out  (#99), a
    ret

fill_page0_red:
    ld   a, 0
    ld   e, #11
    call fill16k
    ld   a, 1
    ld   e, #11
fill16k:
    out  (#99), a
    ld   a, #8E
    out  (#99), a
    xor  a
    out  (#99), a
    ld   a, #40
    out  (#99), a
    ld   hl, #4000
.fk:
    ld   a, e
    out  (#98), a
    dec  hl
    ld   a, h
    or   l
    jr   nz, .fk
    ret

delay4:
    call delay
    call delay
    call delay
    call delay
    ret
delay:
    push de
    ld   d, 10
.d1:
    ld   bc, 0
.d2:
    dec  bc
    ld   a, b
    or   c
    jr   nz, .d2
    dec  d
    jr   nz, .d1
    pop  de
    ret

lmmm_full:                      ; SX0 SY256 DX0 DY0 NX256 NY212 CLR0 ARG0 CMD90
    .db #00,#00, #00,#01, #00,#00, #00,#00, #00,#01, #D4,#00, #00, #00, #90
lmmm_right:                     ; SX128 SY256 DX128 DY0 NX128 NY212 -> mitad derecha
    .db #80,#00, #00,#01, #80,#00, #00,#00, #80,#00, #D4,#00, #00, #00, #90
; (relleno a 16 KB tras ensamblar)
