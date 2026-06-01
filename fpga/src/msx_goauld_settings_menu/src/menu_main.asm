.ZILOG
.BIOS
.BIOSVARS

ENABLE_SDCARD=1
ENABLE_MEGARAM=1

IFDEF ENABLE_MEGARAM
	struct_EnableMegaRam_UP = struct_EnableMegaRam
	struct_EnableMegaRam_DOWN = struct_EnableMegaRam
	struct_MegaRamSlot_UP = struct_MegaRamSlot
	struct_MegaRamSlot_DOWN = struct_MegaRamSlot
ELSE
	struct_EnableMegaRam_UP = struct_EnableMapper
  IFDEF ENABLE_SDCARD
	struct_EnableMegaRam_DOWN = struct_EnableSD
	struct_MegaRamSlot_UP = struct_MapperSlot
	struct_MegaRamSlot_DOWN = struct_SDSlot
  ELSE
	struct_EnableMegaRam_DOWN = struct_Slot1GhostSCC
	struct_MegaRamSlot_UP = struct_MapperSlot
	struct_MegaRamSlot_DOWN = struct_Slot1GhostSCC
  ENDIF ;ENABLE_SDCARD
	struct_MegaRamSlot = struct_MapperSlot
ENDIF ;ENABLE_MEGARAM

IFDEF ENABLE_SDCARD
	struct_EnableSD_UP = struct_EnableSD
	struct_EnableSD_DOWN = struct_EnableSD
	struct_SDSlot_DOWN = struct_SDSlot
ELSE
  IFDEF ENABLE_MEGARAM
	struct_EnableSD_UP = struct_EnableMegaRam
  ELSE
	struct_EnableSD_UP = struct_EnableMapper
  ENDIF ;ENABLE_MEGARAM
	struct_EnableSD_DOWN = struct_Slot1GhostSCC
	struct_SDSlot = struct_Slot1GhostSCC
ENDIF ;ENABLE_SDCARD

.org #8000

; #############################################################################
; ##  MSXnano MAIN MENU (Picoverse-style boot menu) - added for M1
; #############################################################################
; This is now the entry point reached after the FM logo (menu.asm decompresses
; this code to #8000 and jumps here). It shows a main menu with 4 options and,
; when "Arrancar sistema" is chosen, returns to the BIOS so the normal MSX boot
; continues (chain to Nextor/MSX-DOS exactly as it would without a cartridge
; INIT taking over).
;
; STACK NOTE: when execution arrives at #8000 the top of the stack is the
; return address into the BIOS boot routine (the original caller of the
; cartridge INIT at #4760). We save SP here so "Arrancar sistema" can restore
; it and 'ret' cleanly back into the BIOS boot flow.

main_menu_entry:
	; The "Arrancar sistema" option returns to the BIOS through the live stack
	; (see main_action_boot); we do NOT snapshot SP/return into page-2 RAM
	; because that RAM may be remapped between now and the selection.
	xor  a
	ld   (var_mainSel), a			; start with first option highlighted

; Re-entry point used by the placeholders (M2/M3): re-init the screen and
; redraw WITHOUT re-capturing the BIOS context (which is only valid on the
; very first entry from the cartridge INIT).
main_menu_restart:
	call init_screen				; Reuse screen/blink init (shared routine)

main_menu_redraw:
	; Title "MSXnano" centered in the top white box
	ld   hl, #1c02					; X=28, Y=2
	call POSIT						; BIOS setCursor
	ld   hl, mainTitleStr
	call print_string
	; clear text area below the header box
	ld   a, #00
	ld   bc, 240
	ld   hl, #0800
	call FILVRM
	; Top header line (white box like the config menu)
	ld   a, #ff
	ld   bc, 30
	ld   hl, #0800
	call FILVRM						; BIOS fill VRAM

	; Print the 4 main-menu option strings
	ld   hl, #1c06					; X=28
	call POSIT
	ld   hl, mainOpt1Str
	call print_string
	ld   hl, #1c08
	call POSIT
	ld   hl, mainOpt2Str
	call print_string
	ld   hl, #1c0a
	call POSIT
	ld   hl, mainOpt3Str
	call print_string
	ld   hl, #1c0c
	call POSIT
	ld   hl, mainOpt4Str
	call print_string
	; Hint line at the bottom
	ld   hl, #1216
	call POSIT
	ld   hl, mainHintStr
	call print_string

main_menu_loop:
	; Draw the selection highlight (inverse video) on the current option row
	call main_draw_selection

main_menu_wait:
	; Read a key by scanning the keyboard matrix DIRECTLY through the PPI ports
	; (0xAA = row select, 0xA9 = column read), instead of using the BIOS
	; CHSNS/CHGET. At cartridge-INIT time the BIOS keyboard interrupt service
	; is not reliably hooked yet on the Goa'uld, so CHGET ignored the cursor /
	; space keys on real hardware. Direct matrix scan works regardless of BIOS
	; keyboard state (this is the same technique the original G-key gate uses).
	call read_menu_key				; A = key code (0 if none / unmapped)
	or   a
	jr   z, main_menu_wait

	cp   VT_UP
	jr   z, main_menu_up
	cp   VT_DOWN
	jr   z, main_menu_down
	cp   VT_RETURN
	jr   z, main_menu_select
	cp   VT_SPACE
	jr   z, main_menu_select
	; numeric shortcuts 1..4 (direct selection: the user expects this)
	cp   '1'
	jr   z, main_sel_set0
	cp   '2'
	jr   z, main_sel_set1
	cp   '3'
	jr   z, main_sel_set2
	cp   '4'
	jr   z, main_sel_set3
	jr   main_menu_wait				; any other key: ignore, keep waiting

main_sel_set0:
	xor  a
	jr   main_set_and_select
main_sel_set1:
	ld   a, 1
	jr   main_set_and_select
main_sel_set2:
	ld   a, 2
	jr   main_set_and_select
main_sel_set3:
	ld   a, 3
main_set_and_select:
	; A = new selection index. Clear the OLD highlight first (uses the old
	; var_mainSel), then store the new index. NOTE: main_clear_selection
	; destroys A, so preserve it across the call.
	push af
	call main_clear_selection		; remove highlight from the previously-selected row
	pop  af
	ld   (var_mainSel), a			; commit the new selection
	jr   main_menu_select_now

main_menu_up:
	call main_clear_selection
	ld   a, (var_mainSel)
	or   a
	jr   nz, .mu_dec
	ld   a, MAIN_OPT_COUNT			; wrap from top to bottom
.mu_dec:
	dec  a
	ld   (var_mainSel), a
	jr   main_menu_loop

main_menu_down:
	call main_clear_selection
	ld   a, (var_mainSel)
	inc  a
	cp   MAIN_OPT_COUNT				; wrap from bottom to top
	jr   c, .md_store
	xor  a
.md_store:
	ld   (var_mainSel), a
	jr   main_menu_loop

main_menu_select:
main_menu_select_now:
	ld   a, (var_mainSel)
	or   a
	jr   z, main_action_boot		; 0 -> Arrancar sistema
	dec  a
	jr   z, main_action_sdrom		; 1 -> Lanzar ROM de la SD (placeholder)
	dec  a
	jr   z, main_action_wifi		; 2 -> Configuracion WiFi (placeholder)
	jp   config_menu_entry			; 3 -> Ajustes (existing config menu)

; --- Option 1: continue the normal MSX boot ---------------------------------
; Behaves EXACTLY like the proven "Save & Exit" of the config menu (known to
; continue the boot on real Goa'uld hardware): clean up the screen and 'ret'
; through the NATURAL, LIVE stack back to the BIOS cartridge-INIT caller, which
; chains to Nextor / MSX-DOS.
;
; ROOT CAUSE of the previous reset (found by debugger): a previous version
; saved SP + the BIOS return address into page-2 RAM variables at entry and
; restored them here. But on the Goa'uld the page-2 (0x8000-0xBFFF) slot/segment
; mapping is NOT guaranteed to be the same when the menu first runs and when an
; option is later selected, so those variables read back as GARBAGE -> "ld sp,
; garbage" + "ret" jumped to a random address -> CPU reset/loop. The fix is to
; never rely on page-2 stored state: the LIVE stack (page-3 RAM) still holds the
; BIOS return address on top here (the menu's calls are balanced), so a plain
; 'ret' returns correctly regardless of any page-2 remapping.
main_action_boot:
	di
	call INITXT						; clear screen (SCREEN 0) before handing back
	ld   bc, #000d					; turn blink mode off (restore normal text)
	call WRTVDP
	ei
	ret								; return into BIOS boot -> normal boot continues

; --- Option 2: Lanzar ROM de la SD (PLACEHOLDER, M2) ------------------------
main_action_sdrom:
	ld   hl, msgSoonM2Str
	call main_show_message
	jp   main_menu_restart			; redraw menu (keep BIOS context, no reset)

; --- Option 3: Configuracion WiFi (PLACEHOLDER, M3) -------------------------
main_action_wifi:
	ld   hl, msgSoonM3Str
	call main_show_message
	jp   main_menu_restart			; redraw menu (keep BIOS context, no reset)

; Shows a centered message line, waits for ANY key, returns.
; Input: HL - message string
main_show_message:
	push hl
	ld   hl, #1212					; bottom area
	call POSIT
	pop  hl
	call print_string
.msg_wait:
	call read_any_key				; direct matrix scan, A!=0 when a key was pressed
	or   a
	jr   z, .msg_wait
	ret

; -----------------------------------------------------------------------------
; Direct keyboard-matrix reader (bypasses BIOS CHGET, which is unreliable at
; cartridge-INIT time on the Goa'uld). Reads via PPI: write row to port 0xAA
; (low nibble = row, high nibble kept high), read columns from port 0xA9
; (a 0 bit = key pressed). Matrix positions verified empirically:
;   '1'..'4' = row 0 bits 1..4 | UP = row8 bit5 | DOWN = row8 bit6
;   SPACE    = row8 bit0       | RETURN = row7 bit7
; Each routine implements press+release debouncing so one physical press yields
; exactly one event.
; -----------------------------------------------------------------------------
KB_PPIB	equ	0xA9				; PPI port B: keyboard column read
KB_PPIC	equ	0xAA				; PPI port C: keyboard row select (low nibble)

; read_menu_key: returns A = mapped key code (VT_UP/VT_DOWN/VT_RETURN/VT_SPACE/
;                '1'..'4') or 0 if nothing relevant is pressed. Waits for the
;                key to be released before returning (one event per press).
read_menu_key:
	; --- Row 0: digits 1..4 ---
	ld   a, 0xF0
	out  (KB_PPIC), a				; select row 0
	in   a, (KB_PPIB)
	cpl								; now 1 bit = pressed
	ld   b, a						; B = row0 pressed mask
	bit  1, b
	jr   nz, .k1
	bit  2, b
	jr   nz, .k2
	bit  3, b
	jr   nz, .k3
	bit  4, b
	jr   nz, .k4
	; --- Row 8: space / cursor up / cursor down ---
	ld   a, 0xF8
	out  (KB_PPIC), a				; select row 8
	in   a, (KB_PPIB)
	cpl
	ld   b, a						; B = row8 pressed mask
	bit  5, b
	jr   nz, .kup
	bit  6, b
	jr   nz, .kdown
	bit  0, b
	jr   nz, .kspace
	; --- Row 7: RETURN ---
	ld   a, 0xF7
	out  (KB_PPIC), a				; select row 7
	in   a, (KB_PPIB)
	cpl
	bit  7, a
	jr   nz, .kret
	xor  a							; nothing relevant pressed
	ret

.k1:	ld   c, '1'
	jr   .got
.k2:	ld   c, '2'
	jr   .got
.k3:	ld   c, '3'
	jr   .got
.k4:	ld   c, '4'
	jr   .got
.kup:	ld   c, VT_UP
	jr   .got
.kdown:	ld   c, VT_DOWN
	jr   .got
.kspace:ld   c, VT_SPACE
	jr   .got
.kret:	ld   c, VT_RETURN
.got:
	call wait_all_released			; debounce: wait until ALL keys are up
	ld   a, c
	ret

; read_any_key: returns A!=0 once ANY key is pressed (then released), else 0.
read_any_key:
	ld   a, 0xF0
	ld   b, 9						; scan rows 0..8
.ra_loop:
	out  (KB_PPIC), a
	push af
	in   a, (KB_PPIB)
	cp   0xFF						; 0xFF = no key in this row
	jr   nz, .ra_pressed
	pop  af
	inc  a							; next row
	djnz .ra_loop
	xor  a							; no key
	ret
.ra_pressed:
	pop  af
	call wait_all_released
	ld   a, 1						; signal "a key was pressed"
	ret

; wait_all_released: blocks until no key is pressed on rows 0,7,8 (the ones we
; use), with a short settle, so a single press is not read repeatedly.
wait_all_released:
	push bc
.war_loop:
	ld   a, 0xF0					; row 0
	out  (KB_PPIC), a
	in   a, (KB_PPIB)
	inc  a							; 0xFF -> 0 if all released
	jr   nz, .war_busy
	ld   a, 0xF7					; row 7
	out  (KB_PPIC), a
	in   a, (KB_PPIB)
	inc  a
	jr   nz, .war_busy
	ld   a, 0xF8					; row 8
	out  (KB_PPIC), a
	in   a, (KB_PPIB)
	inc  a
	jr   nz, .war_busy
	; all released -> small settle delay then return
	ld   bc, 0x0800
.war_settle:
	dec  bc
	ld   a, b
	or   c
	jr   nz, .war_settle
	pop  bc
	ret
.war_busy:
	jr   .war_loop

; Draws (#ff) the inverse-video highlight bar on the current main-menu row.
main_draw_selection:
	ld   a, #ff
	jr   main_selection_common
; Clears (0) the highlight bar on the current main-menu row.
main_clear_selection:
	xor  a
main_selection_common:
	ld   (var_selColor), a			; remember fill color (#ff highlight / 0 clear)
	; Compute VRAM name-color offset = #0800 + Y*80 + 28
	; Y (screen row) = 6 + sel*2  -> options at Y=6,8,10,12
	ld   a, (var_mainSel)
	add  a, a						; sel*2
	add  a, 6						; A = Y
	ld   l, a
	ld   h, 0						; HL = Y
	add  hl, hl						; 2Y
	add  hl, hl						; 4Y
	add  hl, hl						; 8Y
	add  hl, hl						; 16Y
	push hl							; save 16Y
	add  hl, hl						; 32Y
	add  hl, hl						; 64Y
	pop  de							; DE = 16Y
	add  hl, de						; HL = 80Y
	ld   de, #0800 + 28				; name table base + column 28
	add  hl, de						; HL = VRAM address of the row start
	ld   bc, 14						; width of the highlight bar
	ld   a, (var_selColor)			; fill color
	jp   FILVRM						; fill name-color row, returns to caller

; Shared screen initialization: SCREEN 0 / 80 columns + blink mode ON.
; Used by both the main menu and the config menu so they look identical.
init_screen:
	ld   a, 80
	ld   (LINL40), a
	call INITXT
	; Blink mode on
	ld   bc, #4f0c
	call WRTVDP
	ld   bc, #100d
	jp   WRTVDP						; tail-call, returns to caller

; #############################################################################
; ##  EXISTING GOA'ULD CONFIG MENU  (reached from main menu option "Ajustes")
; #############################################################################

; ############## Initialization
config_menu_entry:
	call init_screen				; SCREEN 0 80-col + blink (shared routine)

	; Print menu title
	ld   hl,#1a02
	call POSIT						; BIOS setCursor
	ld   hl,menuTitleStr
	call print_string
	; clear area
	ld   a, #00
	ld   bc, 240
	ld   hl, #0800
	call FILVRM	
	; Top header line
	ld   a, #ff
	ld   bc, 30
	ld   hl, #0800
	call FILVRM						; BIOS fill VRAM
	; FW version
	ld   hl, #1518
	call POSIT						; BIOS setCursor
	ld   hl, #7D40
	call print_string

	; Print menu options
	ld   ix, structs_start
	ld   (var_currentStruct), ix
.printmenu_loop:
	ld   a, (ix)
	or   a
	jr   z, .printmenu_loop_end
	call print_struct
	ld   bc, STRUCT_SIZE
	add  ix, bc
	jr   .printmenu_loop
.printmenu_loop_end:

	; Read Goauld settings
	di								; Set initial variables values

	ld   a, #48						; Set I/O device to Goauld (#48)
	out  (#40), a
	in   a, (#41)
	
	ld   b, a
	and  #01						; Bit 0: mapper enable
	ld   (var_mapper), a
	ld   a, b
IFDEF ENABLE_MEGARAM
	and  #02						; Bit 1: megaram enable
	rrca
	ld   (var_megram), a
	ld   a, b
ENDIF ;ENABLE_MEGARAM
	and  #04						; Bit 2: ghost scc enable
	rrca
	rrca
	ld   (var_ghtscc), a
	ld   a, b
	and  #08						; Bit 3: scanlines enable
	rrca
	rrca
	rrca
	ld   (var_scanln), a
	ld   a, b
	and  #30						; Bits5,4: mapper slot
	rrca
	rrca
	rrca
	rrca
	ld   (var_mapslt), a
	ld   a, b
IFDEF ENABLE_MEGARAM
	and  #c0						; Bits7,6: megaram slot
	rlca
	rlca
	ld   (var_megslt), a
ENDIF ;ENABLE_MEGARAM

IFDEF ENABLE_SDCARD
	in   a, (#42)
	ld   b, a
	and  #01						; Bit 0: SD card enable
	ld   (var_sdcard), a
	ld   a, b
	and  #06						; Bits1,2: SD card slot
	rrca
	ld   (var_sdcslt), a
ENDIF ;ENABLE_SDCARD

	in   a, (#42)
	and  #08						; Bit 3: slow device
	rrca
	rrca
	rrca
	ld   (var_slowdv), a

	ei

; ############## Main loop

bucle_repaint_selection:
	ld   a, #ff						; Print selection
	call print_selection

ONOFF_Y = 5
bucle:
	ld   hl,#2b00 + ONOFF_Y			; Print Enable Mapper
	ld   a,(var_mapper)
	call print_on_off
ONOFF_Y = ONOFF_Y + 2

IFDEF ENABLE_MEGARAM
	ld   hl,#2b00 + ONOFF_Y			; Print Enable Megaram
	ld   a,(var_megram)
	call print_on_off
ONOFF_Y = ONOFF_Y + 2
ENDIF ;ENABLE_MEGARAM

IFDEF ENABLE_SDCARD
	ld   hl,#2b00 + ONOFF_Y			; Print Enable SD Card
	ld   a,(var_sdcard)
	call print_on_off
ONOFF_Y = ONOFF_Y + 2
ENDIF ;ENABLE_SDCARD

	ld   hl,#2b00 + ONOFF_Y			; Print Ghost SCC
	ld   a,(var_ghtscc)
	call print_on_off
ONOFF_Y = ONOFF_Y + 2

	ld   hl,#2b00 + ONOFF_Y			; Print Enable Scanlines
	ld   a,(var_scanln)
	call print_on_off
ONOFF_Y = ONOFF_Y + 2

	ld   hl,#2b00 + ONOFF_Y			; Print Slow Device
	ld   a,(var_slowdv)
	call print_on_off
ONOFF_Y = ONOFF_Y + 2

ONOFF_Y = 5
	ld   hl,#3c00 + ONOFF_Y			; Print Mapper Slot
	call POSIT						; BIOS setCursor
	ld   a,(var_mapslt)
	add  a,#30
	call CHPUT						; BIOS printChar
ONOFF_Y = ONOFF_Y + 2

IFDEF ENABLE_MEGARAM
	ld   hl,#3c00 + ONOFF_Y			; Print MegaRam Slot
	call POSIT						; BIOS setCursor
	ld   a,(var_megslt)
	add  a,#30
	call CHPUT						; BIOS printChar
ONOFF_Y = ONOFF_Y + 2
ENDIF ;ENABLE_MEGARAM

IFDEF ENABLE_SDCARD
	ld   hl,#3c00 + ONOFF_Y			; Print SD Card Slot
	call POSIT						; BIOS setCursor
	ld   a,(var_sdcslt)
	add  a,#30
	call CHPUT						; BIOS printChar
ONOFF_Y = ONOFF_Y + 2
ENDIF ;ENABLE_SDCARD

	; Wait for a key
wait_for_a_key:
	ei
	halt
	call CHSNS						; BIOS keyStatus
	jr   z, wait_for_a_key
	call CHGET						; BIOS readChar
	or   a
	jr   z, wait_for_a_key

; ############## Keys handling

.key_lateral:
	sub  VT_RIGHT
	jr   z, .key_lateral_ok
	dec  a
	jr   nz, .key_up
.key_lateral_ok:
	ld   e, (ix+STRUCT_KEY_LATERAL)
	ld   d, (ix+STRUCT_KEY_LATERAL+1)
.new_selection:
	ld   a, 0						; Remove selection print
	call print_selection
	ld   ixl, e
	ld   ixh, d
	ld   (var_currentStruct), ix
	jp   bucle_repaint_selection

.key_up:
	dec  a
	jr   nz, .key_down
	ld   e, (ix+STRUCT_KEY_UP)
	ld   d, (ix+STRUCT_KEY_UP+1)
	jR   .new_selection

.key_down:
	dec  a
	jr   nz, .key_space
	ld   e, (ix+STRUCT_KEY_DOWN)
	ld   d, (ix+STRUCT_KEY_DOWN+1)
	jr   .new_selection

.key_space:
	ld   hl, bucle
	push hl
	dec  a
	ret  nz

	ld   l, (ix+STRUCT_SEL_ACTION)
	ld   h, (ix+STRUCT_SEL_ACTION+1)
	jp   (hl)

; ############## Actions

selected_mapper:
	ld   hl, var_mapper
	call .selected_on_off
	or   a
	ret  nz
	ld   a, 3
	ld   (var_mapslt), a
	ret

IFDEF ENABLE_MEGARAM
selected_megaRam:
	ld   hl, var_megram
	call .selected_on_off
	or   a
	ret  nz
	ld   a, 3
	ld   (var_megslt), a
	ret
ENDIF ;ENABLE_MEGARAM

IFDEF ENABLE_SDCARD
selected_sdCard:
	ld   hl, var_sdcard
	call .selected_on_off
;	or   a
;	ret  z
;	ld   a, (var_sdcslt)
;	dec  a
;	ld   (var_sdcslt), a
;	call selected_sdCardSlot
	ret
ENDIF ;ENABLE_SDCARD

selected_slowdevice:
	ld   hl, var_slowdv
	call .selected_on_off
	ret

selected_slot1Ghost:
	ld   hl, var_ghtscc
	jp   .selected_on_off

selected_scanlines:
	ld   hl, var_scanln

.selected_on_off:
	ld   a, (hl)
	xor  1
	ld   (hl), a
	ret

selected_mapperSlot:
	ld   a, (var_mapper)				; If disabled then don't modify
	or   a
	ret  z
IFDEF ENABLE_MEGARAM
	ld   a, (var_megslt)				; Increase slot if not used by MegaRam nor SD Card
	cp   3
	jr   nz, .mp_skip
	xor  a
.mp_skip:
	ld   b, a
ENDIF ;ENABLE_MEGARAM
;IFDEF ENABLE_SDCARD
;	ld   a, (var_sdcslt)
;	ld   c, a
;ENDIF ;ENABLE_SDCARD
	ld   a, (var_mapslt)
.mp_used:
	inc  a
.mp_no_inc:
IFDEF ENABLE_MEGARAM
	cp   b
	jr   z, .mp_used
ENDIF ;ENABLE_MEGARAM
;IFDEF ENABLE_SDCARD
;	ld   d, a
;	ld   a, (var_sdcard)				; If disabled then skip
;	or   a
;	ld   a, d
;	jr   z, .mapperSlot_check
;	cp   c
;	jr   z, .mp_used
;	
;ENDIF ;ENABLE_SDCARD

.mapperSlot_check:
	cp   4
	jr   nz, .mp_no4
	ld   a, #1
	jr   .mp_no_inc
.mp_no4:
	ld   (var_mapslt), a
	ret

IFDEF ENABLE_MEGARAM
selected_megaRamSlot:
	ld   a, (var_megram)				; If disabled then don't modify
	or   a
	ret  z
	ld   a, (var_mapslt)				; Increase slot if not used by Mapper nor SD Card
	cp   3
	jr   nz, .mr_skip
	xor  a
.mr_skip:
	ld   b, a
;IFDEF ENABLE_SDCARD
;	ld   a, (var_sdcslt)
;	ld   c, a
;ENDIF ;ENABLE_SDCARD
	ld   a, (var_megslt)
.mr_used:
	inc  a
.mr_no_inc:
	cp   b
	jr   z, .mr_used
;IFDEF ENABLE_SDCARD
;	ld   d, a
;	ld   a, (var_sdcard)				; If disabled then skip
;	or   a
;	ld   a, d
;	jr   z, .megaramSlot_check
;	cp   c
;	jr   z, .mr_used
;ENDIF

.megaramSlot_check:
	cp   4
	jr   nz, .mr_no4
	ld   a, #1
	jr   .mr_no_inc
.mr_no4:
	ld   (var_megslt), a
	ret
ENDIF ;ENABLE_MEGARAM

IFDEF ENABLE_SDCARD
selected_sdCardSlot:
	ret
	ld   a, (var_sdcard)				; If disabled then don't modify
	or   a
	ret  z
	ld   a, (var_mapslt)				; Increase slot if not used by Mapper nor MegaRam
	ld   b, a
IFDEF ENABLE_MEGARAM
	ld   a, (var_megslt)
	ld   c, a
ENDIF ;ENABLE_MEGARAM
	ld   a, (var_sdcslt)
.sd_used:
	inc  a
.sd_used_no_inc:
	cp   b
	jr   z, .sd_used
IFDEF ENABLE_MEGARAM
	cp   c
	jr   z, .sd_used
ENDIF ;ENABLE_MEGARAM
	cp   4
	jr   nz, .sd_no4
	ld   a, #1
	jr   .sd_used_no_inc
.sd_no4:
	ld   (var_sdcslt), a
	ret
ENDIF ;ENABLE_SDCARD

selected_saveReset:
	pop  hl							; Remove ret to bucle
	call config_var2byte
	di
	ld   a, #48						; Set I/O device to Goauld (#48)
	out  (#40),a
	in   a, (#42)
	or   #C0						; Bit 7: reset, Bit 6: save config in flash
	out  (#42), a
	ei
	ret

selected_saveExit:
	pop  hl							; Remove ret to bucle (the config-menu loop)
	call config_var2byte			; Save settings to flash + clear screen
	; Continue the boot using the SAME robust mechanism as the main-menu
	; "Arrancar sistema" option, instead of ret'ing into a possibly-drifted
	; stack. This guarantees we hand control back to the BIOS cleanly.
	jp   main_action_boot

config_var2byte:
	ld   a, (var_mapper)			; #41 Bit 0: mapper enable
	ld   b, a
IFDEF ENABLE_MEGARAM
	ld   a, (var_megram)			; #41 Bit 1: megaram enable
	rlca
	or   b
	ld   b, a
ENDIF ;ENABLE_MEGARAM
	ld   a, (var_ghtscc)			; #41 Bit 2: ghost scc enable
	rlca
	rlca
	or   b
	ld   b, a
	ld   a, (var_scanln)			; #41 Bit 3: scanlines enable
	rlca
	rlca
	rlca
	or   b
	ld   b, a
	ld   a, (var_mapslt)			; #41 Bits5,4: mapper slot
	rlca
	rlca
	rlca
	rlca
	or   b
	ld   b, a
IFDEF ENABLE_MEGARAM
	ld   a, (var_megslt)			; #41 Bits7,6: megaram slot
	rlca
	rlca
	rlca
	rlca
	rlca
	rlca
	or   b
	ld   b, a
ENDIF ;ENABLE_MEGARAM

	ld   c, #41
	call set_settings

	ld   b, #0
IFDEF ENABLE_SDCARD
	ld   a, (var_sdcard)			; #42 Bit 0: SD Card enable
	ld   b, a
	ld   a, (var_sdcslt)			; #42 Bit 1,2: SD Card slot
	rlca
	or   b
	ld   b, a
ENDIF

	ld   a, (var_slowdv)			; #42 Bit 3: slow device
	rlca
	rlca
	rlca
	or   b
	or   #40						; Bit 6: save config in flash
	ld   b, a

	ld   c, #42
	call set_settings

	call INITXT						; BIOS clearScreen
	ld   bc, #000d					; Blink mode off
	jp   WRTVDP

set_settings:
	di
	ld   a, #48						; Set I/O device to Goauld (#48)
	out  (#40),a
	ld   a, b
	out  (c),a
	reti

; Prints characters from memory until a 0 is found.
; Input    : HL - The text address 
print_string:
	ld   a,(hl)
	or   a
	ret  z
	inc  hl
	call CHPUT						; BIOS printChar
	jr   print_string

; Set the cursor to L,H position and prints 'Off'/'On ' if A is 0 or not.
; Input    : H  - Y coordinate of cursor
;            L  - X coordinate of cursor
;            A  - Value to print (0:Off 1:On)
print_on_off:
	ld   b, a
	call POSIT						; BIOS setCursor
	ld   a, b
	ld   hl,offStr
	or   a
	jr   z,print_on_off_end
	ld   hl,onStr
print_on_off_end:
	jr   print_string

; Print the text of a struct
; Input    : IX - Struct address
print_struct:
	ld   l, (ix+STRUCT_POSXY+1)
	ld   h, (ix+STRUCT_POSXY)
	call POSIT						; BIOS setCursor
	ld   l, (ix+STRUCT_TEXT)
	ld   h, (ix+STRUCT_TEXT+1)
	jr   print_string

; Print the selection highlight on/off
; Input    : A  - 0:off #ff:on
print_selection:
	ld   ix, (var_currentStruct)
	ld   b, 0
	ld   c, (ix+STRUCT_SEL_LEN)
	ld   l, (ix+STRUCT_SEL_START)
	ld   h, (ix+STRUCT_SEL_START+1)
	jp   FILVRM


; ############## Constants

; ----- Main menu (MSXnano) strings -----
MAIN_OPT_COUNT	equ		4				; number of main-menu options

mainTitleStr:
	.db "MSXnano",0
mainOpt1Str:
	.db "1. Arrancar sistema",0
mainOpt2Str:
	.db "2. Lanzar ROM de la SD",0
mainOpt3Str:
	.db "3. Configuracion WiFi",0
mainOpt4Str:
	.db "4. Ajustes",0
mainHintStr:
	.db "Flechas para mover - ENTER/ESPACIO para elegir",0
msgSoonM2Str:
	.db "Lanzar ROM de la SD: Proximamente (M2). Pulsa una tecla...",0
msgSoonM3Str:
	.db "Configuracion WiFi: Proximamente (M3). Pulsa una tecla...",0

menuTitleStr:
	.db "MSX Goa'uld Settings Menu v1.23",0
enableMapperStr:
	.db "Enable Mapper",0
IFDEF ENABLE_MEGARAM
enableMegaRamStr:
	.db "Enable MegaRam SCC",0
ENDIF ;ENABLE_MEGARAM
IFDEF ENABLE_SDCARD
enableSDStr:
	.db "Enable SD",0
ENDIF ;ENABLE_SDCARD
slot1GhostStr:
	.db "Ghost SCC",0
enableScanlinesStr:
	.db "Enable Scanlines",0
slowDeviceStr:
	.db "Compatible Mode",0
saveExitStr:
	.db "Save & Exit",0
saveResetStr:
	.db "Save & Reset",0
slotStr:
	.db "Slot",0

onStr:
	.db "On ",0
offStr:
	.db "Off",0


; ############## Structs

STRUCT_POSXY		equ		0
STRUCT_TEXT			equ		STRUCT_POSXY + 2
STRUCT_KEY_UP		equ		STRUCT_TEXT + 2
STRUCT_KEY_DOWN		equ		STRUCT_KEY_UP + 2
STRUCT_KEY_LATERAL	equ		STRUCT_KEY_DOWN + 2
STRUCT_SEL_START	equ		STRUCT_KEY_LATERAL + 2
STRUCT_SEL_LEN		equ		STRUCT_SEL_START + 2
STRUCT_SEL_ACTION	equ		STRUCT_SEL_LEN + 1

STRUCT_SIZE			equ		STRUCT_SEL_ACTION + 2	; Struct size

POS_Y = 4

structs_start:
struct_EnableMapper:
	.db 21, POS_Y+1
	.dw enableMapperStr
	.dw struct_SaveReset, struct_EnableMegaRam_DOWN, struct_MapperSlot
	.dw #0800 + POS_Y*10 + 2
	.db 4
	.dw selected_mapper
POS_Y = POS_Y + 2

IFDEF ENABLE_MEGARAM
struct_EnableMegaRam:
	.db 21, POS_Y+1
	.dw enableMegaRamStr
	.dw struct_EnableMapper, struct_EnableSD_DOWN, struct_MegaRamSlot
	.dw #0800 + POS_Y*10 + 2
	.db 4
	.dw selected_megaRam
POS_Y = POS_Y + 2
ENDIF ;ENABLE_MEGARAM

IFDEF ENABLE_SDCARD
struct_EnableSD:
	.db 21, POS_Y+1
	.dw enableSDStr
	.dw struct_EnableMegaRam_UP, struct_Slot1GhostSCC, struct_SDSlot
	.dw #0800 + POS_Y*10 + 2
	.db 4
	.dw selected_sdCard
POS_Y = POS_Y + 2
ENDIF ;ENABLE_SDCARD

struct_Slot1GhostSCC:
	.db 21, POS_Y+1
	.dw slot1GhostStr
	.dw struct_EnableSD_UP, struct_EnableScanlines, struct_Slot1GhostSCC
	.dw #0800 + POS_Y*10 + 2
	.db 4
	.dw selected_slot1Ghost
POS_Y = POS_Y + 2

struct_EnableScanlines:
	.db 21, POS_Y+1
	.dw enableScanlinesStr
	.dw struct_Slot1GhostSCC, struct_SlowDevice, struct_EnableScanlines
	.dw #0800 + POS_Y*10 + 2
	.db 4
	.dw selected_scanlines
POS_Y = POS_Y + 2

struct_SlowDevice:
	.db 21, POS_Y+1
	.dw slowDeviceStr
	.dw struct_EnableScanlines, struct_SaveExit, struct_SlowDevice
	.dw #0800 + POS_Y*10 + 2
	.db 4
	.dw selected_slowdevice
POS_Y = POS_Y + 2

struct_SaveExit:
	.db 21, POS_Y+1
	.dw saveExitStr
	.dw struct_SlowDevice, struct_SaveReset, struct_SaveExit
	.dw #0800 + POS_Y*10 + 2
	.db 4
	.dw selected_saveExit
POS_Y = POS_Y + 2

struct_SaveReset:
	.db 21, POS_Y+1
	.dw saveResetStr
	.dw struct_SaveExit, struct_EnableMapper, struct_SaveReset
	.dw #0800 + POS_Y*10 + 2
	.db 4
	.dw selected_saveReset
POS_Y = POS_Y + 2

POS_Y = 4

struct_MapperSlot:
	.db 54, POS_Y+1
	.dw slotStr
	.dw struct_SaveReset, struct_MegaRamSlot_DOWN, struct_EnableMapper
	.dw #0800 + POS_Y*10 + 6
	.db 2
	.dw selected_mapperSlot
POS_Y = POS_Y + 2

IFDEF ENABLE_MEGARAM
struct_MegaRamSlot:
	.db 54, POS_Y+1
	.dw slotStr
	.dw struct_MapperSlot, struct_SDSlot_DOWN, struct_EnableMegaRam
	.dw #0800 + POS_Y*10 + 6
	.db 2
	.dw selected_megaRamSlot
POS_Y = POS_Y + 2
ENDIF ;ENABLE_MEGARAM

IFDEF ENABLE_SDCARD
struct_SDSlot:
	.db 54, POS_Y+1
	.dw slotStr
	.dw struct_MegaRamSlot_UP, struct_Slot1GhostSCC, struct_EnableSD
	.dw #0800 + POS_Y*10 + 6
	.db 2
	.dw selected_sdCardSlot
POS_Y = POS_Y + 2
ENDIF

structs_end:
	.db 0


; ############## Variables

	var_mapper: ds 1
IFDEF ENABLE_MEGARAM
	var_megram: ds 1
ENDIF
IFDEF ENABLE_SDCARD
	var_sdcard: ds 1
ENDIF
	var_ghtscc: ds 1
	var_scanln: ds 1
	var_mapslt: ds 1
	var_slowdv: ds 1
IFDEF ENABLE_MEGARAM
	var_megslt: ds 1
ENDIF
IFDEF ENABLE_SDCARD
	var_sdcslt: ds 1
ENDIF

	var_currentStruct: ds 2

	; Main menu (MSXnano) state
	var_mainSel:  ds 1				; currently selected main-menu option (0..3)
	var_selColor: ds 1				; scratch: fill color for highlight bar


; ############## MSX VT-52 Character Codes

VT_BEEP    equ	#07		; A beep sound
VT_RETURN  equ	#0d		; 13,"M"	; Carriage return
VT_RIGHT   equ	#1c		; 27,"C"	; Cursor right
VT_LEFT    equ	#1d		; 27,"D"	; Cursor left
VT_UP      equ	#1e		; 27,"A"	; Cursor up
VT_DOWN    equ	#1f		; 27,"B"	; Cursor down
VT_SPACE   equ	#20		; Space
VT_CLRSCR  equ	#0c		; 27,"E"	; Clear screen:	Clears the screen and moves the cursor to home
VT_HOME    equ	#0b		; 27,"H"	; Cursor home:	Move cursor to the upper left corner.

