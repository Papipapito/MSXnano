; ============================================================================
; PGCMD.ROM v3 -- MSXnano: aislar el bug del MOTOR DE COMANDOS (LMMM)
; ----------------------------------------------------------------------------
; v2 demostro: 1 copia grande (X=0) = LIMPIO; 16 columnas (X!=0, NX peq, muchas)
; = BASURA, SIN CPU concurrente. Aqui separamos las variables:
;
;  FASE A (borde AZUL):  1 LMMM grande SX=0 DX=0 NX=256 NY=212  -> control LIMPIO.
;  FASE B (borde CIAN):  1 LMMM con X != 0: SX=128 DX=128 NX=128 NY=212
;       -> copia la MITAD DERECHA. Limpio = mitad izq ROJA + der VERDE.
;          BASURA = el bug es X!=0 (SX/DX no-cero) en una sola copia.
;  FASE C (borde BLANCO):14 tiras horizontales, TODAS X=0, NX=256 NY=16,
;       variando SY/DY (muchos comandos a X=0). Limpio = VERDE.
;          BASURA = el bug es "muchos comandos seguidos" (a X=0).
;
; Veredicto:  B basura  -> bug = SX/DX no-cero.
;             C basura  -> bug = repeticion de comandos.
;             ambas     -> ambos contribuyen.
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

    ; ===== FASE C: borde BLANCO, 14 tiras horizontales a X=0 =====
    ld   a, #0F
    out  (#99), a
    ld   a, #80|7
    out  (#99), a
    call fill_page0_red
    ld   hl, strip_fixed       ; SX=0,DX=0,NX=256,NY=16,SY_hi=1,ARG=0
    ld   b, 12
.sf:
    ld   a, (hl)
    out  (#99), a
    inc  hl
    ld   a, (hl)
    out  (#99), a
    inc  hl
    djnz .sf
    ld   e, 0                  ; E = DY = 0,16,...,208 (14 tiras)
.sc:
    call wait_ce
    ld   a, e
    out  (#99), a
    ld   a, #80|34
    out  (#99), a              ; R#34 SY_lo = DY (SY = DY+256)
    ld   a, e
    out  (#99), a
    ld   a, #80|38
    out  (#99), a              ; R#38 DY_lo = DY
    ld   a, #90
    out  (#99), a
    ld   a, #80|46
    out  (#99), a              ; CMD = LMMM -> dispara
    ld   a, e
    add  a, 16
    ld   e, a
    cp   224
    jr   c, .sc               ; 14 tiras (DY 0..208)
    call delay4
    jr   main

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
strip_fixed:                    ; (val,0x80|reg) fijos para las tiras
    .db #00,#A0                 ; R#32 SX_lo = 0
    .db #00,#A1                 ; R#33 SX_hi = 0
    .db #01,#A3                 ; R#35 SY_hi = 1
    .db #00,#A4                 ; R#36 DX_lo = 0
    .db #00,#A5                 ; R#37 DX_hi = 0
    .db #00,#A7                 ; R#39 DY_hi = 0
    .db #00,#A8                 ; R#40 NX_lo = 0  (256)
    .db #01,#A9                 ; R#41 NX_hi = 1  (NX=256)
    .db #10,#AA                 ; R#42 NY_lo = 16
    .db #00,#AB                 ; R#43 NY_hi = 0
    .db #00,#AC                 ; R#44 CLR = 0
    .db #00,#AD                 ; R#45 ARG = 0
; (relleno a 16 KB tras ensamblar)
