; MUSPLAY.COM: toca un .MUS con el reproductor que le toca (MSX-DOS 2 / Nextor)
;
;   MUSPLAY CANCION.MUS [opciones]
;
; Dos programas usan la extension .MUS:
;   - MGS (MGSDRV, de Ain): MML en texto. Lo compila y lo toca MGSC (-P toca, -N no
;     guarda el .MGS).
;   - FAC SoundTracker: un volcado binario de 8000h-BFFFh (casi siempre con la cabecera
;     de BSAVE, FEh 00 80 FF BF 00 80, pero los hay con esos 7 bytes a cero o con
;     basura). Lo toca ROBOPLAY en el OPL4, con sus samples (.SM1 y .SM2) si estan.
; MUSPLAY mira los 256 primeros bytes: con un caracter de control que no sea TAB, LF,
; FF, CR, ^Z ni ESC es binario y ejecuta ROBOPLAY CANCION.MUS [opciones]; si no,
; MGSC CANCION.MUS -P -N [opciones].
;
; Lo ejecuta como COMMAND2: busca el .COM en la carpeta actual y luego en las del PATH,
; pone PROGRAM (la ruta completa con la que lo encontro: RoboPlay saca de ahi la carpeta
; de sus .PLY) y PARAMETERS (lo mismo que en 81h, espacios del principio incluidos: MGSC
; lee de ahi la linea de ordenes) y la linea en 80h, y lo carga en 100h desde un trozo de
; codigo que se copia en (0006h) - 200h (encima queda sitio para la pila mientras lee).
; El programa arranca con la pila en (0006h) y 0000h encima, como si lo hubiera cargado
; COMMAND2. Los errores de MSX-DOS (fichero que no esta, falta de memoria...) se
; devuelven con _TERM y COMMAND2 los explica.
;
; Ensamblar con pasmo: pasmo --bin musplay.asm MUSPLAY.COM

BDOS            equ     0005h
_STROUT         equ     09h
_CURDRV         equ     19h
_FFIRST         equ     40h
_OPEN           equ     43h
_CLOSE          equ     45h
_READ           equ     48h
_GETCD          equ     59h
_TERM           equ     62h
_GENV           equ     6Bh
_SENV           equ     6Ch
_DOSVER         equ     6Fh
_EOF            equ     0C7h            ; fin de fichero (un .MUS vacio)
_NORAM          equ     0DEh            ; "Not enough memory"

                org     0100h

inicio:         ld      b,0
                ld      c,_DOSVER
                call    BDOS
                ld      a,b
                cp      2
                ld      de,t_dos2
                jp      c,mensaje

; La linea de ordenes (80h: longitud, 81h: texto) a "linea", acabada en 0
                ld      hl,0080h
                ld      c,(hl)
                ld      b,0
                inc     hl
                ld      de,linea
                ld      a,c
                or      a
                jr      z,sin_linea
                ldir
sin_linea:      xor     a
                ld      (de),a

; El nombre del fichero es la primera palabra; "resto" son las opciones que siguen
                ld      hl,linea
saltar:         ld      a,(hl)
                cp      ' '
                jr      z,saltar1
                cp      9
                jr      nz,saltar2
saltar1:        inc     hl
                jr      saltar
saltar2:        or      a
                ld      de,t_uso
                jp      z,mensaje
                ld      (nombre),hl
fin_nombre:     ld      a,(hl)
                or      a
                jr      z,fin_nombre1
                cp      ' '
                jr      z,fin_nombre1
                cp      9
                jr      z,fin_nombre1
                inc     hl
                jr      fin_nombre
fin_nombre1:    ld      (resto),hl
                ld      (sep),a
                ld      (hl),0          ; el nombre acabado en 0 (se repone al armar la linea)

; Los 256 primeros bytes del fichero
                ld      de,(nombre)
                ld      a,1             ; solo lectura
                ld      c,_OPEN
                call    BDOS
                or      a
                jp      nz,error_dos
                ld      a,b
                ld      (handle),a
                ld      de,muestra
                ld      hl,256
                ld      c,_READ
                call    BDOS
                ld      (leidos),hl
                push    af
                ld      a,(handle)
                ld      b,a
                ld      c,_CLOSE
                call    BDOS
                pop     af
                or      a
                jr      z,clasificar
                cp      _EOF
                jp      nz,error_dos
                ld      hl,0
                ld      (leidos),hl

; Binario (FAC SoundTracker) o texto (MML de MGS)
clasificar:     ld      hl,muestra
                ld      bc,(leidos)
clas_bucle:     ld      a,b
                or      c
                jr      z,es_texto
                ld      a,(hl)
                cp      20h
                jr      nc,clas_sig     ; 20h o mas: texto (o Shift-JIS)
                cp      09h
                jr      c,es_binario    ; 00h-08h
                cp      0Bh
                jr      z,es_binario
                cp      0Eh
                jr      c,clas_sig      ; TAB, LF, FF, CR
                cp      1Ah
                jr      c,es_binario    ; 0Eh-19h
                cp      1Ch
                jr      c,clas_sig      ; ^Z, ESC
                jr      es_binario      ; 1Ch-1Fh
clas_sig:       inc     hl
                dec     bc
                jr      clas_bucle

es_binario:     ld      hl,n_robo
                ld      de,t_robo
                ld      bc,0            ; sin opciones propias
                jr      armar
es_texto:       ld      hl,n_mgsc
                ld      de,t_mgsc
                ld      bc,o_mgsc
armar:          ld      (programa),hl
                ld      (no_esta),de

; La linea nueva: " CANCION.MUS" + opciones propias + lo que seguia al nombre
                ld      de,nueva
                ld      a,' '
                ld      (de),a
                inc     de
                ld      hl,(nombre)
                call    copiar
                ld      h,b
                ld      l,c
                ld      a,h
                or      l
                call    nz,copiar
                ld      hl,(resto)
                ld      a,(sep)
                ld      (hl),a
                call    copiar
                xor     a
                ld      (de),a
                ex      de,hl
                ld      de,nueva
                or      a
                sbc     hl,de           ; HL = longitud
                ld      a,h
                or      a
                jr      nz,larga
                ld      a,l
                cp      128
                jr      c,corta
larga:          ld      de,t_larga
                jp      mensaje
corta:          ld      (longitud),a

; El reproductor: en la carpeta actual ("X:\CARPETA\NOMBRE.COM", como pone COMMAND2 en
; PROGRAM) y luego en las del PATH
                ld      c,_CURDRV
                call    BDOS
                add     a,'A'
                ld      hl,ruta
                ld      (hl),a
                inc     hl
                ld      (hl),':'
                inc     hl
                ld      (hl),'\'
                inc     hl
                ex      de,hl
                push    de
                ld      b,0
                ld      c,_GETCD
                call    BDOS
                pop     de
                or      a
                jr      nz,en_path
                ld      a,(de)
                or      a
                jr      z,en_cd         ; en la raiz: "X:\NOMBRE.COM"
                ex      de,hl
                xor     a
                ld      b,a
                ld      c,a
                cpir                    ; detras del 0 de la carpeta
                dec     hl
                ld      (hl),'\'
                inc     hl
                ex      de,hl
en_cd:          ld      hl,(programa)
                call    copiar
                xor     a
                ld      (de),a
                call    probar
                jr      z,hallado
en_path:
                ld      hl,n_path
                ld      de,valpath
                ld      b,255
                ld      c,_GENV
                call    BDOS
                or      a
                jr      z,path_ok
                xor     a
                ld      (valpath),a
path_ok:        ld      hl,valpath
path_bucle:     ld      a,(hl)
                or      a
                jr      z,no_hallado
                call    separador
                jr      nz,path_entrada
                inc     hl
                jr      path_bucle
path_entrada:   ld      de,ruta
                ld      c,0
path_copia:     ld      a,(hl)
                or      a
                jr      z,path_fin
                call    separador
                jr      z,path_fin
                ld      (de),a
                ld      c,a
                inc     hl
                inc     de
                jr      path_copia
path_fin:       push    hl
                ld      a,c
                cp      '\'
                jr      z,path_nombre
                cp      ':'
                jr      z,path_nombre
                ld      a,'\'
                ld      (de),a
                inc     de
path_nombre:    ld      hl,(programa)
                call    copiar
                xor     a
                ld      (de),a
                call    probar
                pop     hl
                jr      nz,path_bucle
                jr      hallado
no_hallado:     ld      de,(no_esta)
                jp      mensaje

; Tiene que caber entre 100h y el trozo que lo carga ((0006h) - 200h)
hallado:        ld      hl,(fib+23)
                ld      a,h
                or      l
                jr      nz,no_cabe
                ld      hl,(0006h)
                dec     h
                dec     h
                ld      (destino),hl
                ld      de,0100h
                or      a
                sbc     hl,de
                ld      (maximo),hl
                ld      de,(fib+21)
                or      a
                sbc     hl,de
                jr      nc,cabe
no_cabe:        ld      a,_NORAM
                jp      error_dos
cabe:           ld      de,ruta
                ld      a,1
                ld      c,_OPEN
                call    BDOS
                or      a
                jp      nz,error_dos
                ld      a,b
                ld      (handle),a

; PROGRAM y PARAMETERS, y la linea en 80h
                ld      hl,n_program
                ld      de,ruta
                ld      c,_SENV
                call    BDOS
                or      a
                jp      nz,error_dos
                ld      hl,n_param
                ld      de,nueva        ; como COMMAND2: lo mismo que en 81h, espacios incluidos
                ld      c,_SENV
                call    BDOS
                or      a
                jp      nz,error_dos
                ld      a,(longitud)
                ld      (0080h),a
                ld      c,a
                ld      b,0
                inc     bc
                ld      hl,nueva
                ld      de,0081h
                ldir

; El cargador a lo alto de la TPA, y alli: lee el programa en 100h y salta
                ld      hl,cargador
                ld      de,(destino)
                ld      bc,cargador_fin-cargador
                ldir
                ld      a,(handle)
                ld      b,a
                ld      hl,(maximo)
                ld      ix,(destino)
                jp      (ix)

; Se copia y se ejecuta en (0006h) - 200h: solo saltos relativos. B = handle, HL = bytes
cargador:       ld      de,0100h
                ld      c,_READ
                push    bc
                call    BDOS
                pop     bc
                push    af
                ld      c,_CLOSE
                call    BDOS
                pop     af
                or      a
                jr      nz,cargador_err
                ld      sp,(0006h)
                ld      hl,0
                push    hl
                jp      0100h
cargador_err:   ld      b,a
                ld      c,_TERM
                jp      BDOS
cargador_fin:

; ---------------------------------------------------------------- rutinas

; Copia la cadena de HL (acabada en 0, sin el 0) a DE; DE queda detras
copiar:         ld      a,(hl)
                or      a
                ret     z
                ld      (de),a
                inc     hl
                inc     de
                jr      copiar

; Z si A separa dos carpetas del PATH (';', espacio o TAB)
separador:      cp      ';'
                ret     z
                cp      ' '
                ret     z
                cp      9
                ret

; _FFIRST de "ruta" (ficheros normales): Z si esta
probar:         ld      de,ruta
                ld      b,0
                ld      ix,fib
                ld      c,_FFIRST
                call    BDOS
                or      a
                ret

error_dos:      ld      b,a
                ld      c,_TERM
                jp      BDOS

mensaje:        ld      c,_STROUT
                jp      BDOS

; ---------------------------------------------------------------- datos

t_dos2:         db      "MUSPLAY needs MSX-DOS 2 or Nextor",13,10,"$"
t_uso:          db      "MUSPLAY 1.0: plays a .MUS song with the right player",13,10
                db      "Usage: MUSPLAY SONG.MUS [options]",13,10
                db      "  MGS (MML text):            MGSC SONG.MUS -P -N [options]",13,10
                db      "  FAC SoundTracker (binary): ROBOPLAY SONG.MUS [options]",13,10,"$"
t_robo:         db      "*** ROBOPLAY.COM not found (it plays FAC SoundTracker songs)",13,10,"$"
t_mgsc:         db      "*** MGSC.COM not found (it plays MGS songs)",13,10,"$"
t_larga:        db      "*** Command line too long",13,10,"$"
n_robo:         db      "ROBOPLAY.COM",0
n_mgsc:         db      "MGSC.COM",0
o_mgsc:         db      " -P -N",0
n_path:         db      "PATH",0
n_program:      db      "PROGRAM",0
n_param:        db      "PARAMETERS",0

nombre:         dw      0
resto:          dw      0
sep:            db      0
handle:         db      0
leidos:         dw      0
programa:       dw      0
no_esta:        dw      0
longitud:       db      0
destino:        dw      0
maximo:         dw      0

; Buferes detras del programa (no van en el .COM)
fin_com:
linea           equ     fin_com                 ; 128
nueva           equ     linea+128               ; 140
muestra         equ     nueva+140               ; 256
fib             equ     muestra+256             ; 64
valpath         equ     fib+64                  ; 256
ruta            equ     valpath+256             ; 272
