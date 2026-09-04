; ============================================================================
; PGTEST.COM -- MSXnano: test de FLIP de pagina visible en SCREEN 5 (bug #22)
; ----------------------------------------------------------------------------
; Aisla del MG2 el cambio de pagina visible del VDP (R#2). Pinta la pagina 0 de
; ROJO y la pagina 1 de VERDE (paleta propia, no depende de la de DOS) y luego:
;
;  FASE A (borde AZUL, R#13=0):    alterna R#2 pagina0<->pagina1 cada ~1s.
;     -> debe verse ROJO <-> VERDE. Si se queda fijo, el flip R#2 NO funciona.
;
;  FASE B (borde BLANCO, R#13=33): fija R#2 = pagina1 (VERDE) y NO toca mas.
;     -> debe verse VERDE FIJO. Si PARPADEA verde/rojo, se confirma el bug del
;        RTL: con R#13!=0 la maquina de blink fuerza la pagina 0
;        (vdp_graphic4567.vhd:249) -> y el menu deja R#13 sucio = causa del #22.
;
; Bucle infinito (FASE A, luego B, repite). Para salir: RESET / apagar.
; Ensamblar:  asmsx -z pgtest.asm   ->  renombrar pgtest.z80 a PGTEST.COM
; ============================================================================
    .ZILOG
    .org #0100

start:
    di
    ; ---- registros para SCREEN 5 (Graphic 4) ----
    ld   hl, vregs
    ld   c, 0
.ri:
    ld   a, (hl)
    out  (#99), a               ; dato
    ld   a, c
    or   #80
    out  (#99), a               ; selecciona R#c
    inc  hl
    inc  c
    ld   a, c
    cp   11                     ; R#0..R#10
    jr   c, .ri
    ; R#23=0, R#25=0 (sin scroll vertical / sin extras V9958)
    xor  a
    out  (#99), a
    ld   a, #80|23
    out  (#99), a
    xor  a
    out  (#99), a
    ld   a, #80|25
    out  (#99), a

    ; ---- paleta propia: indice 1 = ROJO, indice 2 = VERDE ----
    ld   a, 1
    out  (#99), a
    ld   a, #80|16              ; R#16 = puntero de paleta = 1
    out  (#99), a
    ld   a, #70                 ; idx1 byte1: R=7,B=0
    out  (#9A), a
    ld   a, #00                 ; idx1 byte2: G=0  -> ROJO
    out  (#9A), a
    ld   a, #00                 ; idx2 byte1: R=0,B=0
    out  (#9A), a
    ld   a, #07                 ; idx2 byte2: G=7  -> VERDE
    out  (#9A), a

    ; ---- rellenar pagina 0 (VRAM 0x00000-0x07FFF) con indice 1 (0x11) ----
    ld   a, 0
    ld   e, #11
    call fill16k                ; R#14=0
    ld   a, 1
    ld   e, #11
    call fill16k                ; R#14=1
    ; ---- rellenar pagina 1 (VRAM 0x08000-0x0FFFF) con indice 2 (0x22) ----
    ld   a, 2
    ld   e, #22
    call fill16k                ; R#14=2
    ld   a, 3
    ld   e, #22
    call fill16k                ; R#14=3

main:
    ; ================= FASE A: R#13=0, borde AZUL (R#7=#04) =================
    xor  a
    out  (#99), a
    ld   a, #80|13
    out  (#99), a               ; R#13 = 0 (blink OFF)
    ld   a, #04
    out  (#99), a
    ld   a, #80|7
    out  (#99), a               ; R#7 = borde azul
    ld   b, 4
.fa:
    push bc
    ld   a, #1F                 ; R#2 = pagina 0 (base 0x0000)
    out  (#99), a
    ld   a, #80|2
    out  (#99), a
    call delay
    ld   a, #3F                 ; R#2 = pagina 1 (base 0x8000, bit5=1)
    out  (#99), a
    ld   a, #80|2
    out  (#99), a
    call delay
    pop  bc
    djnz .fa

    ; ============ FASE B: R#13=#33 (blink ON), borde BLANCO ============
    ; Dejamos R#2 fijo en pagina 1 (VERDE). Sin bug -> VERDE fijo.
    ; Con el bug del blink -> parpadea verde/rojo (se fuerza pagina 0).
    ld   a, #3F                 ; R#2 = pagina 1
    out  (#99), a
    ld   a, #80|2
    out  (#99), a
    ld   a, #0F
    out  (#99), a
    ld   a, #80|7
    out  (#99), a               ; R#7 = borde blanco (marca FASE B)
    ld   a, #33                 ; R#13 = blink ON=3 / OFF=3 (~conmuta solo)
    out  (#99), a
    ld   a, #80|13
    out  (#99), a
    call delay
    call delay
    call delay
    call delay
    call delay
    call delay
    jr   main

; ----------------------------------------------------------------------------
; fill16k: A = valor de R#14 (bloque A16-A14), E = byte de relleno. 16 KB.
; ----------------------------------------------------------------------------
fill16k:
    out  (#99), a               ; R#14 = A
    ld   a, #8E
    out  (#99), a               ; selecciona R#14
    xor  a
    out  (#99), a               ; direccion baja = 0
    ld   a, #40
    out  (#99), a               ; direccion alta = 0 + bit de escritura
    ld   hl, #4000
.fk:
    ld   a, e
    out  (#98), a
    dec  hl
    ld   a, h
    or   l
    jr   nz, .fk
    ret

; ----------------------------------------------------------------------------
delay:                          ; ~0.5s con DI
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

vregs:
    .db #06                     ; R#0 = Graphic 4 (M3,M4)
    .db #40                     ; R#1 = display ON
    .db #1F                     ; R#2 = tabla de nombres pagina 0 (base 0x0000)
    .db #FF                     ; R#3
    .db #03                     ; R#4
    .db #FF                     ; R#5
    .db #03                     ; R#6
    .db #04                     ; R#7 = borde
    .db #08                     ; R#8
    .db #00                     ; R#9 = 192 lineas
    .db #00                     ; R#10
