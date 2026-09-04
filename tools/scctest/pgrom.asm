; ============================================================================
; PGROM.ROM -- MSXnano: test de FLIP de pagina (SCREEN 5) como CARTUCHO, para
; lanzar DESDE EL MENU (reproduce el contexto exacto de MG2, no DOS). bug #22
; ----------------------------------------------------------------------------
; Pinta pagina 0 = ROJO, pagina 1 = VERDE (paleta propia). Fija el modo G4
; (R#0/R#1) pero deja R#9/R#13/R#25 COMO LOS DEJO EL MENU, y compara:
;
;  FASE 1 (borde MAGENTA): R#2 = pagina 1 (VERDE), con R#9/R#13/R#25 HEREDADOS
;     del menu. -> si se ve VERDE, el menu deja el estado limpio. Si se ve ROJO
;     o PARPADEA o sale raro, el menu deja estado VDP sucio que fuerza pagina 0.
;
;  FASE 2 (borde BLANCO): igual pero AHORA limpiamos R#9=0, R#13=0, R#25=0.
;     -> debe verse VERDE FIJO. Si la FASE 1 estaba mal y esta bien, CONFIRMA
;        que el menu deja R#9/R#13/R#25 sucios = causa del #22 (fix software).
;
;  FASE 3 (borde AZUL): R#13=0, alterna pagina0<->pagina1 (flip R#2 basico).
;     -> debe verse ROJO <-> VERDE. Si se queda fijo, el flip R#2 esta roto.
;
; Bucle infinito. Para salir: RESET / apagar.
; Cartucho 16K. Ensamblar: asmsx -z pgrom.asm  -> renombrar pgrom.z80 a PGROM.ROM
; ============================================================================
    .ZILOG
    .org #4000

    .db  "AB"                   ; cabecera de cartucho MSX
    .dw  init                   ; INIT
    .dw  0                      ; STATEMENT
    .dw  0                      ; DEVICE
    .dw  0                      ; TEXT

init:
    di
    ; ---- modo G4 (SCREEN 5) + display ON; NO tocamos R#9/R#13/R#25 aun ----
    ld   a, #06
    out  (#99), a
    ld   a, #80|0
    out  (#99), a               ; R#0 = Graphic 4
    ld   a, #40
    out  (#99), a
    ld   a, #80|1
    out  (#99), a               ; R#1 = display ON
    ld   a, #1F
    out  (#99), a
    ld   a, #80|2
    out  (#99), a               ; R#2 = pagina 0 (de momento)

    ; ---- paleta: indice 1 = ROJO, indice 2 = VERDE ----
    ld   a, 1
    out  (#99), a
    ld   a, #80|16
    out  (#99), a
    ld   a, #70
    out  (#9A), a               ; idx1: R7 B0
    ld   a, #00
    out  (#9A), a               ; idx1: G0  -> ROJO
    ld   a, #00
    out  (#9A), a               ; idx2: R0 B0
    ld   a, #07
    out  (#9A), a               ; idx2: G7  -> VERDE

    ; ---- rellenar pagina 0 (0x00000-0x07FFF) = idx1, pagina 1 (0x08000-) = idx2 ----
    ld   a, 0
    ld   e, #11
    call fill16k
    ld   a, 1
    ld   e, #11
    call fill16k
    ld   a, 2
    ld   e, #22
    call fill16k
    ld   a, 3
    ld   e, #22
    call fill16k

main:
    ; ============ FASE 1: R#9/R#13/R#25 HEREDADOS del menu ============
    ld   a, #0D                 ; borde MAGENTA
    out  (#99), a
    ld   a, #80|7
    out  (#99), a
    ld   a, #3F                 ; R#2 = pagina 1 (VERDE)
    out  (#99), a
    ld   a, #80|2
    out  (#99), a
    call delay4

    ; ============ FASE 2: limpiamos R#9=0, R#13=0, R#25=0 ============
    ld   a, #0F                 ; borde BLANCO
    out  (#99), a
    ld   a, #80|7
    out  (#99), a
    xor  a
    out  (#99), a
    ld   a, #80|9
    out  (#99), a               ; R#9 = 0 (EO off, 192 lineas)
    xor  a
    out  (#99), a
    ld   a, #80|13
    out  (#99), a               ; R#13 = 0 (blink off)
    xor  a
    out  (#99), a
    ld   a, #80|25
    out  (#99), a               ; R#25 = 0
    ld   a, #3F                 ; R#2 = pagina 1 (VERDE)
    out  (#99), a
    ld   a, #80|2
    out  (#99), a
    call delay4

    ; ============ FASE 3: flip basico pagina0<->pagina1 (borde AZUL) ============
    ld   a, #04
    out  (#99), a
    ld   a, #80|7
    out  (#99), a
    ld   b, 4
.f3:
    push bc
    ld   a, #1F                 ; pagina 0 (ROJO)
    out  (#99), a
    ld   a, #80|2
    out  (#99), a
    call delay
    ld   a, #3F                 ; pagina 1 (VERDE)
    out  (#99), a
    ld   a, #80|2
    out  (#99), a
    call delay
    pop  bc
    djnz .f3

    jr   main

; ----------------------------------------------------------------------------
fill16k:                        ; A = R#14 (bloque A16-A14), E = byte. 16 KB.
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

; ----------------------------------------------------------------------------
delay4:                         ; ~ 4 retardos
    call delay
    call delay
    call delay
    call delay
    ret
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
; (el fichero se rellena a 16 KB despues de ensamblar)
