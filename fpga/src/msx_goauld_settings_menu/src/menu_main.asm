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
	; Save the BIOS cartridge-INIT return context. At this point SP points at the
	; BIOS return address (the decompressor's final 'ret' consumed the pushed
	; #8000, leaving the BIOS return on top). We store SP in PAGE-3 RAM (#E000),
	; which does NOT remap like page 2, so "Arrancar sistema" can restore the exact
	; SP and 'ret' reliably even if the menu's stack ends up unbalanced for any
	; reason (this is more robust than relying on perfectly balanced calls).
	ld   (BOOT_SP), sp
	pop  hl							; top of stack = BIOS boot return address
	push hl
	ld   (BOOT_RET), hl				; save it: the WiFi ESP ROM may clobber the stack
	; The goauld BIOS boot calls this cartridge INIT a SECOND time before it
	; finally boots the disk. "Arrancar sistema" sets BOOT_FLAG and rets; on the
	; re-run we see the flag and ret again WITHOUT showing the browser, so a
	; single ESC boots (otherwise it took two: logo + browser reappear, then boot).
	ld   a, (BOOT_FLAG)
	ld   b, a
	xor  a
	ld   (BOOT_FLAG), a				; the flag is only valid transiently
	ld   a, b
	cp   #99
	jp   z, main_action_boot		; pending boot -> continue the boot, skip the menu
	; Wipe any stale Nextor disk-emulation pointer in RAM (#A000). The one-time
	; record we write for .dsk launch survives a WARM reset, so without this a plain
	; "arrancar sistema" (ESC) after a previous .dsk would make Nextor re-enter
	; emulation and hang. Only the .dsk launch path re-writes it, later than here.
	ld   hl, #A000
	ld   de, #A001
	ld   bc, 15
	ld   (hl), 0
	ldir							; zero the 16-byte "NEXTOR_EMU_DATA" signature
	ld   a, 2
	ld   (FILTER), a				; default tab = ALL
	xor  a
	ld   (var_mainSel), a			; start with first option highlighted

; Re-entry point used by the placeholders (M2/M3): re-init the screen and
; redraw WITHOUT re-capturing the BIOS context (which is only valid on the
; very first entry from the cartridge INIT).
main_menu_restart:
	xor  a
	ld   (BROWSING), a				; leaving the browser: stop marquee animation
	call init_screen				; Reuse screen/blink init (shared routine)
	; UNIFIED UI (Picoverse-style): the SD browser IS the home screen. Boot and
	; every "return to menu" land here. ESC in the browser = boot the system,
	; 'A' = settings. The old 4-option menu below is kept but no longer reached.
	jp   main_action_sdrom

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
	; Read a key via the BIOS keyboard (ei/halt/CHSNS/CHGET, see browse_getkey).
	; This delivers the cursor keys (rows the direct PPI scan missed) so the main
	; menu can be driven with cursors + ENTER, just like the SD browser. The
	; numeric 1..4 shortcuts still work (CHGET returns the same codes).
	call browse_getkey				; A = key code (cursors 1E/1F, RETURN 0D, etc.)
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
	jp   z, main_action_sdrom		; 1 -> Lanzar ROM de la SD
	dec  a
	jp   z, main_action_wifi		; 2 -> Configuracion WiFi (placeholder)
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
; boot_system: user chose "arrancar sistema". Mark a pending-boot flag (so the
; BIOS's second INIT pass auto-continues instead of showing the browser again)
; and continue the boot.
boot_system:
	ld   a, #99
	ld   (BOOT_FLAG), a
	; fall through to main_action_boot

main_action_boot:
	di
	call INITXT						; clear screen (SCREEN 0) before handing back
	ld   bc, #000d					; turn blink mode off (restore normal text)
	call WRTVDP
	ld   sp, (BOOT_SP)				; restore the exact BIOS-INIT SP saved at entry
	ld   hl, (BOOT_RET)				; re-supply the BIOS return address in case the
	ex   (sp), hl					; WiFi ESP ROM clobbered that stack slot
	ei
	ret								; return into BIOS boot -> normal boot continues

; --- Option 2: Lanzar ROM de la SD -------------------------------------------
; M2.1 derisk: prove the boot menu itself can read a raw SD sector through the
; WonderTANG window BEFORE the OS boots. Menu code runs at #8000 (page 2); the
; SD register window is at #7C00-#7EFF in PAGE 1, slot 3-2. We switch page 1 to
; slot 3-2 only around the access, read sector 0, restore page 1 to slot 3-1.
; The sector buffer + scratch live at FIXED PAGE-3 RAM addresses (NOT reserved
; inside the menu image with 'ds', which would inflate the decompressed image).
SD_LBA		equ	#C000			; 4 bytes: LBA to read (page-3 RAM scratch)
SD_CTYPE	equ	#C004			; 1 byte: card type read back
SD_STATUS	equ	#C005			; 1 byte: 0=OK, 1=init timeout, 2=read timeout
part_type	equ	#C006			; 1 byte: MBR partition 1 type
PART_LBA	equ	#C008			; 4 bytes: partition start LBA (FAT16 volume)
ROOT_LBA	equ	#C00C			; 4 bytes: root directory start LBA
disp_row	equ	#C010			; 1 byte: current display row
sec_left	equ	#C011			; 1 byte: root-dir sectors remaining
ent_in_sec	equ	#C01F			; 1 byte: dir entries left in current sector
name83		equ	#C012			; 13 bytes: formatted 8.3 name (ASCIIZ)
ENT_COUNT	equ	#C020			; 1 byte: number of entries scanned
BR_SEL		equ	#C021			; 1 byte: selected entry index
BR_TOP		equ	#C022			; 1 byte: first visible entry index
BR_TMP		equ	#C023			; 1 byte: scratch (draw_entry)
BR_TMP2		equ	#C024			; 1 byte: scratch (draw_browser loop index)
BR_REC		equ	#C025			; 2 bytes: scratch record pointer
ARR_PTR		equ	#C027			; 2 bytes: array write pointer (scan)
BR_OLD		equ	#C029			; 1 byte: previously-selected index (partial repaint)
BR_OLDTOP	equ	#C02A			; 1 byte: BR_TOP before ensure_visible (scroll detect)
ENT_ARRAY	equ	#C300			; entry array: ENT_SIZE bytes each (type,cluster,name)
ENT_SIZE	equ	80				; record: type(1)+cluster(2)+size(4)+name(73 ASCIIZ)
NAME_OFF	equ	7				; name offset inside a record (after type+cluster+size)
NAME_MAX	equ	72				; max name chars stored (+ NUL) -> longer than the
								; 59-col window so long names overflow and marquee-scroll
NAME_WIN	equ	59				; name display window width (cols 9..67, size at 69)
VISIBLE		equ	18				; entries per page (list rows 4..21; hdr 1, tabs 2, line 3, sep 22, footer 23)
MAX_ENT		equ	115				; array capacity (115*80 = 9200 bytes -> C300..E6F0)
HAVE_LFN	equ	#C02B			; 1 byte: a long-file-name is being accumulated
LFN_BUF		equ	#C02C			; 80 bytes: assembled long file name (C02C..C07B)
CUR_CLUS	equ	#C07C			; 2 bytes: current directory cluster (0 = root)
DIR_SP		equ	#C07E			; 1 byte: folder back-stack depth
DATA_LBA	equ	#C090			; 4 bytes: FAT data region start LBA
SEC_PER_CLUS equ #C094			; 1 byte: sectors per cluster
ROOT_SECS	equ	#C095			; 1 byte: root-directory sector count
JOY_PREV	equ	#C096			; 1 byte: previous joystick code (edge detect)
FAT_LBA		equ	#C097			; 4 bytes: FAT table start LBA
FILE_CLUS	equ	#C09B			; 2 bytes: selected file's first cluster
CHAIN_CNT	equ	#C09D			; 2 bytes: file cluster-chain length
DIR_STACK	equ	#C0A0			; 8 x 2 bytes: parent-cluster back stack
BOOT_SP		equ	#C0B0			; 2 bytes: saved BIOS cartridge-INIT SP (page-3, stable)
MQ_OFF		equ	#C0B2			; 1 byte: marquee scroll offset of the selected name
MQ_SEL		equ	#C0B3			; 1 byte: entry index currently being marquee-scrolled
MQ_TICK		equ	#C0B4			; 1 byte: marquee frame counter
BROWSING	equ	#C0B5			; 1 byte: 1 while inside the SD browser (gate marquee)
MAP_SCC		equ	#C0B6			; 2 bytes: Konami-SCC bank-write count
MAP_KON		equ	#C0B8			; 2 bytes: Konami bank-write count
MAP_A8		equ	#C0BA			; 2 bytes: ASCII8 bank-write count
MAP_A16		equ	#C0BC			; 2 bytes: ASCII16 bank-write count
SCAN_CLUS	equ	#C0BE			; 2 bytes: cluster being scanned
SSEC_LEFT	equ	#C0C0			; 1 byte: sectors left in current cluster (scan)
SCAN_N		equ	#C0C1			; 2 bytes: sectors scanned so far
MAPPER_ID	equ	#C0C3			; 1 byte: detected mapper id
MEG_T0		equ	#C0C4			; 1 byte: megaram write-test readback byte 0
MEG_T1		equ	#C0C5			; 1 byte: megaram write-test readback byte 1
MEG_P42		equ	#C0C6			; 1 byte: SWIO port 0x42 readback (Slot2Mode in bits 4,5)
MEG_B0		equ	#C0C7			; 1 byte: megaram byte 0 BEFORE the write
LOAD_SEG	equ	#C0C8			; 1 byte: current 8K megaram segment being loaded
LOAD_OFF	equ	#C0C9			; 2 bytes: byte offset within the current 8K segment
LOAD_CLUS	equ	#C0CB			; 2 bytes: cluster being loaded (chain walk)
MEG_RB		equ	#C0CD			; 8 bytes: megaram readback scratch (load verify)
NEEDLE		equ	#C0D5			; 2 bytes: substring search needle pointer (tag scan)
TAGPTR		equ	#C0D7			; 2 bytes: haystack (filename) pointer (tag scan)
PE_PTR		equ	#C0D9			; 2 bytes: MBR partition-entry pointer (dump diag)
PE_ROW		equ	#C0DB			; 1 byte: partition dump display row
PE_DW		equ	#C0DC			; 4 bytes: 32-bit value scratch for hex print
DSK_LBA		equ	#C0E0			; 4 bytes: abs LBA of the selected .dsk first sector
DSK_SECS	equ	#C0E4			; 2 bytes: .dsk size in 512-byte sectors
EMU_LBA		equ	#C0E6			; 4 bytes: abs LBA of the NEXTOR.EMU data file sector
FAT_SZ		equ	#C0EA			; 2 bytes: sectors per FAT (FATSz16)
NUM_FATS	equ	#C0EC			; 1 byte: number of FAT copies
NEW_CLUS	equ	#C0ED			; 2 bytes: cluster allocated for a new NEXTOR.EMU
FFC_BASE	equ	#C0EF			; 2 bytes: base cluster of the FAT sector being scanned
FFC_LEFT	equ	#C0F1			; 2 bytes: FAT sectors left to scan
MCE_OFF		equ	#C0F3			; 2 bytes: byte offset of the FAT entry within its sector
WDE_LEFT	equ	#C0F5			; 1 byte: root-dir sectors left to scan
MCE_SEC		equ	#C0F6			; 1 byte: FAT sector offset of the cluster entry
BR_BLINK	equ	#C0F7			; 1 byte: per-row blink-attr fill byte (dir colour)
FILTER		equ	#C0F8			; 1 byte: active tab filter (0=ROM, 1=DSK, 2=ALL)
; --- multi-partition support (placed at #E800, above ENT_ARRAY C300..E700) ---
MAX_PARTS	equ	8
PART_TBL	equ	#E800			; up to 8 entries x 4 bytes = start LBA of each FAT16 partition
PART_CNT	equ	#E820			; 1 byte: number of partitions found
EXT_BASE	equ	#E821			; 4 bytes: extended-partition base LBA (0 = none)
CUR_PART	equ	#E825			; 1 byte: currently-selected partition index
EBR_CUR		equ	#E826			; 4 bytes: current EBR LBA while walking the chain
ADD_TMP		equ	#E82A			; 4 bytes: 32-bit add scratch
BOOT_RET	equ	#E82E			; 2 bytes: saved BIOS boot return address (survives WiFi ROM)
BOOT_FLAG	equ	#E830			; 1 byte: 0x99 = boot pending (skip menu on BIOS 2nd INIT pass)
CLK_STR		equ	#E831			; 9 bytes: "HH:MM:SS" + 0 (header clock)
CLK_LAST	equ	#E83A			; 1 byte: last seconds-units digit (clock change detect)
JOY_RPT		equ	#E83B			; 1 byte: joystick auto-repeat frame counter
JOY_RPT_DELAY equ 14			; frames before a held stick starts repeating
JOY_RPT_RATE  equ 2				; frames between repeats (lower = faster)
MEG_SLOT	equ	#02				; primary slot 2 (the OCM relocates the megaram here
								; when Slot2Mode is set via the SWIO smart command)
; mapper ids
MAP_PLAIN	equ	0
MAP_KON_ID	equ	2
MAP_SCC_ID	equ	3
MAP_A8_ID	equ	4
MAP_A16_ID	equ	5
MAP_UNK		equ	6
MAP_THRESH	equ	2				; min bank-writes to accept a mapper signature
SD_BUF		equ	#C100			; 512 bytes: sector transfer buffer
SD_SLOT_32	equ	#8B			; ENASLT slot id: expanded, primary 3, secondary 2 (SD)
SD_SLOT_31	equ	#87			; ENASLT slot id: expanded, primary 3, secondary 1 (menu)
SDC_SDATA	equ	#7C00			; 512-byte sector transfer window
SDC_ENABLE	equ	#7E00			; wo: bit0 = enable SDC register block
SDC_CMD		equ	#7E01			; wo: bit0=read
SDC_STATUS	equ	#7E02			; ro: bit7 = busy
SDC_SADDR	equ	#7E03			; wo: 4 bytes = LBA
SDC_CTYPE	equ	#7E0C			; ro: card type

main_action_sdrom:
	call cls_browser				; show feedback (the SD init can pause a moment)
	ld   hl, #0103
	call POSIT
	ld   hl, readingStr				; "Leyendo SD..."
	call print_string
	; --- read sector 0 (MBR with partition table) ---
	xor  a
	ld   (SD_LBA+0), a
	ld   (SD_LBA+1), a
	ld   (SD_LBA+2), a
	ld   (SD_LBA+3), a
	call sd_read_sector
	; --- SD-present check: if the init/read timed out (no card, or not the SD
	;     window) bail out cleanly instead of parsing garbage and hanging ---
	ld   a, (SD_STATUS)
	or   a
	jp   nz, sd_not_present
	ld   a, (SD_BUF+510)			; MBR boot signature must be 0x55 0xAA
	cp   #55
	jp   nz, sd_not_present
	ld   a, (SD_BUF+511)
	cp   #AA
	jp   nz, sd_not_present
	; --- enumerate ALL FAT16 partitions (4 primaries + extended-chain logicals) ---
	call enum_partitions
	ld   a, (PART_CNT)
	or   a
	jp   z, sd_not_present			; no readable FAT16 partition
	xor  a
	call select_partition			; open partition 0 (reads BPB, computes root, scans;
	jp   c, sd_not_present			; sets BR_SEL/BR_TOP/MQ_SEL/BROWSING)
	jp   browse						; scrolling browser (returns to menu on ESC)

; sd_not_present: no usable SD card (init/read timeout or bad MBR signature).
; In the unified UI the browser is the home screen, so DON'T loop back to it
; (that would re-read the SD and bounce here forever). Offer the global actions.
sd_not_present:
	call cls_browser
	ld   hl, #0103
	call POSIT
	ld   hl, noSdStr
	call print_string
	ld   hl, #0105
	call POSIT
	ld   hl, noSdStr2
	call print_string
.snp_key:
	call browse_getkey
	cp   #0D						; RETURN -> arrancar sistema
	jp   z, boot_system
	cp   #1B						; ESC -> arrancar sistema
	jp   z, boot_system
	cp   #53						; 'S' -> Settings (Ajustes)
	jp   z, config_menu_entry
	cp   #73						; 's'
	jp   z, config_menu_entry
	cp   #57						; 'W' -> WiFi config
	jp   z, main_action_wifi
	cp   #77						; 'w'
	jp   z, main_action_wifi
	jr   .snp_key

; =====================================================================
; Multi-partition support
; =====================================================================
; is_fat16: A = MBR/EBR partition type byte. CF=1 if it is a FAT12/16 type we
; can browse (0x01/0x04/0x06/0x0E). CF=0 otherwise. A preserved.
is_fat16:
	cp   #01
	jr   z, .if_yes
	cp   #04
	jr   z, .if_yes
	cp   #06
	jr   z, .if_yes
	cp   #0E
	jr   z, .if_yes
	or   a							; CF = 0
	ret
.if_yes:
	scf
	ret

; add_partition_at: HL = ptr to a 4-byte start LBA. Append it to PART_TBL if room.
add_partition_at:
	ld   a, (PART_CNT)
	cp   MAX_PARTS
	ret  nc							; table full -> ignore
	push hl							; src
	ld   l, a						; dest = PART_TBL + cnt*4
	ld   h, 0
	add  hl, hl						; *2
	add  hl, hl						; *4
	ld   de, PART_TBL
	add  hl, de
	ex   de, hl						; DE = dest
	pop  hl							; HL = src
	ld   bc, 4
	ldir
	ld   a, (PART_CNT)
	inc  a
	ld   (PART_CNT), a
	ret

; set_add_tmp: HL = ptr to 4-byte value -> ADD_TMP = value.
set_add_tmp:
	ld   de, ADD_TMP
	ld   bc, 4
	ldir
	ret

; add_to_tmp: HL = ptr to 4-byte addend -> ADD_TMP += (HL), 32-bit.
add_to_tmp:
	or   a							; clear carry
	ld   de, ADD_TMP
	ld   b, 4
.att_loop:
	ld   a, (de)
	adc  a, (hl)
	ld   (de), a
	inc  de
	inc  hl
	djnz .att_loop
	ret

; enum_partitions: SD_BUF holds the MBR. Fill PART_TBL / PART_CNT with every
; FAT16 partition: the 4 primary entries, plus the logical drives inside an
; extended partition (type 0x05/0x0F) by walking its EBR chain.
enum_partitions:
	xor  a
	ld   (PART_CNT), a
	ld   (EXT_BASE+0), a
	ld   (EXT_BASE+1), a
	ld   (EXT_BASE+2), a
	ld   (EXT_BASE+3), a
	ld   hl, SD_BUF + 446			; first primary entry
	ld   b, 4
.ep_pri:
	push bc
	push hl
	ld   de, 4
	add  hl, de						; HL -> type byte
	ld   a, (hl)
	cp   #05
	jr   z, .ep_ext
	cp   #0F
	jr   z, .ep_ext
	call is_fat16
	jr   nc, .ep_pnext
	pop  hl							; HL = entry base
	push hl
	ld   de, 8
	add  hl, de						; HL -> start LBA
	call add_partition_at
	jr   .ep_pnext
.ep_ext:
	pop  hl							; HL = entry base
	push hl
	ld   de, 8
	add  hl, de						; HL -> extended start LBA
	ld   de, EXT_BASE
	ld   bc, 4
	ldir							; EXT_BASE = this entry's start LBA
.ep_pnext:
	pop  hl							; HL = entry base
	ld   de, 16
	add  hl, de						; next primary entry
	pop  bc
	djnz .ep_pri
	; --- walk the extended chain, if any ---
	ld   a, (EXT_BASE+0)
	ld   hl, EXT_BASE+1
	or   (hl)
	inc  hl
	or   (hl)
	inc  hl
	or   (hl)
	ret  z							; EXT_BASE == 0 -> no extended partition
	ld   hl, EXT_BASE				; EBR_CUR = EXT_BASE
	ld   de, EBR_CUR
	ld   bc, 4
	ldir
	ld   b, MAX_PARTS				; bound the chain length
.ep_walk:
	push bc
	ld   hl, EBR_CUR				; SD_LBA = EBR_CUR
	ld   de, SD_LBA
	ld   bc, 4
	ldir
	call sd_read_sector
	ld   a, (SD_STATUS)
	or   a
	jr   nz, .ep_wend				; read error -> stop
	ld   a, (SD_BUF + 450)			; EBR entry0 type
	call is_fat16
	jr   nc, .ep_link				; not FAT16 -> skip recording
	ld   hl, EBR_CUR				; logical LBA = EBR_CUR + entry0.rel_start
	call set_add_tmp
	ld   hl, SD_BUF + 454
	call add_to_tmp
	ld   hl, ADD_TMP
	call add_partition_at
.ep_link:
	ld   a, (SD_BUF + 466)			; EBR entry1 type (link to next EBR)
	or   a
	jr   z, .ep_wend				; empty -> end of chain
	ld   hl, EXT_BASE				; next EBR = EXT_BASE + entry1.rel_start
	call set_add_tmp
	ld   hl, SD_BUF + 470
	call add_to_tmp
	ld   hl, ADD_TMP
	ld   de, EBR_CUR
	ld   bc, 4
	ldir
	pop  bc
	djnz .ep_walk
	ret
.ep_wend:
	pop  bc
	ret

; select_partition: A = partition index. Set PART_LBA from PART_TBL, read its
; boot sector (BPB), compute the root dir and scan it. Also (re)inits the browser
; selection/marquee. Returns CF=1 on SD error, CF=0 on success.
select_partition:
	ld   (CUR_PART), a
	ld   l, a						; src = PART_TBL + idx*4
	ld   h, 0
	add  hl, hl
	add  hl, hl
	ld   de, PART_TBL
	add  hl, de
	ld   de, PART_LBA				; PART_LBA = table[idx]
	ld   bc, 4
	ldir
	ld   hl, PART_LBA				; SD_LBA = PART_LBA
	ld   de, SD_LBA
	ld   bc, 4
	ldir
	call sd_read_sector
	ld   a, (SD_STATUS)
	or   a
	scf
	ret  nz							; SD error -> CF=1
	call fat_compute_root
	call scan_root
	xor  a
	ld   (BR_SEL), a
	ld   (BR_TOP), a
	xor  a
	ld   (DIR_SP), a				; reset folder back-stack (root of this partition)
	ld   a, #FF
	ld   (MQ_SEL), a
	ld   a, 1
	ld   (BROWSING), a
	or   a							; CF = 0 (success)
	ret

; -----------------------------------------------------------------------------
; fat_compute_root: ROOT_LBA = PART_LBA + RsvdSecCnt + NumFATs*FATSz16.
; Inputs: SD_BUF = FAT16 boot sector, PART_LBA = partition start LBA.
; -----------------------------------------------------------------------------
fat_compute_root:
	ld   a, (SD_BUF+16)				; NumFATs
	ld   (NUM_FATS), a
	ld   b, a
	ld   hl, 0
	ld   de, (SD_BUF+22)			; FATSz16
	ld   (FAT_SZ), de
.fcr_mul:
	add  hl, de
	djnz .fcr_mul					; hl = NumFATs * FATSz16
	ld   de, (SD_BUF+14)			; RsvdSecCnt
	add  hl, de						; hl = relative root-dir sector
	ld   de, (PART_LBA+0)			; + partition start (low word)
	add  hl, de
	ld   (ROOT_LBA+0), hl
	ld   hl, (PART_LBA+2)			; high word + carry (ld does not affect carry)
	ld   de, 0
	adc  hl, de
	ld   (ROOT_LBA+2), hl
	; --- also derive data-region geometry for subdirectory access ---
	ld   a, (SD_BUF+13)				; sectors per cluster
	ld   (SEC_PER_CLUS), a
	ld   hl, (SD_BUF+17)			; RootEntCnt
	srl  h
	rr   l
	srl  h
	rr   l
	srl  h
	rr   l
	srl  h
	rr   l							; HL = RootEntCnt/16 = root-dir sectors (32B entries, 512B/sec)
	ld   a, l
	ld   (ROOT_SECS), a
	ld   d, 0						; DATA_LBA = ROOT_LBA + ROOT_SECS
	ld   e, a
	ld   hl, (ROOT_LBA+0)
	add  hl, de
	ld   (DATA_LBA+0), hl
	ld   hl, (ROOT_LBA+2)
	ld   de, 0
	adc  hl, de
	ld   (DATA_LBA+2), hl
	; FAT_LBA = PART_LBA + RsvdSecCnt (first FAT table sector)
	ld   hl, (SD_BUF+14)			; RsvdSecCnt
	ld   de, (PART_LBA+0)
	add  hl, de
	ld   (FAT_LBA+0), hl
	ld   hl, (PART_LBA+2)
	ld   de, 0
	adc  hl, de
	ld   (FAT_LBA+2), hl
	ret

; -----------------------------------------------------------------------------
; set_scan_start: set SD_LBA (first sector) and sec_left (sector limit) for the
; directory whose cluster is CUR_CLUS (0 = the fixed root-dir region).
; -----------------------------------------------------------------------------
set_scan_start:
	ld   hl, (CUR_CLUS)
	ld   a, h
	or   l
	jr   nz, .sss_data
	ld   hl, (ROOT_LBA+0)			; root: fixed region after the FATs
	ld   (SD_LBA+0), hl
	ld   hl, (ROOT_LBA+2)
	ld   (SD_LBA+2), hl
	ld   a, (ROOT_SECS)
	ld   (sec_left), a
	ret
.sss_data:
	; SD_LBA = DATA_LBA + (CUR_CLUS-2) * SEC_PER_CLUS
	ld   hl, (DATA_LBA+0)
	ld   (SD_LBA+0), hl
	ld   hl, (DATA_LBA+2)
	ld   (SD_LBA+2), hl
	ld   hl, (CUR_CLUS)
	dec  hl
	dec  hl							; cluster - 2
	ex   de, hl						; DE = cluster-2
	ld   a, (SEC_PER_CLUS)
	ld   b, a
.sss_loop:
	call add32_de					; SD_LBA += (cluster-2), SEC_PER_CLUS times
	djnz .sss_loop
	ld   a, (SEC_PER_CLUS)
	ld   (sec_left), a
	ret

; add32_de: SD_LBA (32-bit) += DE (16-bit). DE preserved.
add32_de:
	push de
	ld   hl, (SD_LBA+0)
	add  hl, de
	ld   (SD_LBA+0), hl
	ld   hl, (SD_LBA+2)
	ld   de, 0
	adc  hl, de
	ld   (SD_LBA+2), hl
	pop  de
	ret

; -----------------------------------------------------------------------------
; scan_root / scan_current: read the current directory and store each [DIR]/.ROM
; entry into ENT_ARRAY as {type(1: 0=dir 1=rom), cluster(2), name(ASCIIZ)}.
; scan_root resets to the root; scan_current rescans whatever CUR_CLUS points to.
; -----------------------------------------------------------------------------
scan_root:
	xor  a
	ld   (CUR_CLUS+0), a
	ld   (CUR_CLUS+1), a
	ld   (DIR_SP), a
scan_current:
	xor  a
	ld   (ENT_COUNT), a
	ld   (HAVE_LFN), a
	ld   hl, ENT_ARRAY
	ld   (ARR_PTR), hl
	call set_scan_start
.scr_sec:
	call sd_read_sector
	ld   ix, SD_BUF
	ld   a, 16
	ld   (ent_in_sec), a
.scr_ent:
	ld   a, (ix+0)
	or   a
	jp   z, .scr_done				; 0x00 = end of directory
	cp   #E5
	jp   z, .scr_drop				; deleted -> skip, drop pending LFN
	ld   a, (ix+11)
	and  #0F
	cp   #0F
	jp   z, .scr_lfn				; LFN entry -> accumulate the long name
	ld   a, (ix+11)
	and  #08
	jp   nz, .scr_drop				; volume label -> skip
	ld   a, (ix+0)
	cp   '.'
	jp   z, .scr_drop				; "." and ".." entries -> skip
	ld   a, (ENT_COUNT)
	cp   MAX_ENT
	jp   nc, .scr_done				; array full
	ld   a, (ix+11)
	and  #10
	jr   z, .scr_file
	ld   c, 0						; type 0 = directory
	jr   .scr_store
.scr_file:
	call ix_is_rom
	jr   z, .scr_isrom
	call ix_is_dsk
	jp   nz, .scr_drop				; neither .ROM nor .DSK -> skip
	ld   c, 2						; type 2 = dsk (Nextor disk image)
	jr   .scr_store
.scr_isrom:
	ld   c, 1						; type 1 = rom
.scr_store:
	; active-tab filter: dirs (c=0) always kept; files filtered by type.
	ld   a, c
	or   a
	jr   z, .scr_fltok				; directory -> keep
	ld   a, (FILTER)
	cp   2
	jr   z, .scr_fltok				; ALL -> keep
	inc  a							; FILTER 0->1 (rom), 1->2 (dsk)
	cp   c							; c = type (1=rom, 2=dsk)
	jp   nz, .scr_drop				; type doesn't match the active tab -> skip
.scr_fltok:
	; name source: assembled LFN if any, else the 8.3 short name
	ld   a, (HAVE_LFN)
	or   a
	jr   z, .scr_short
	ld   hl, LFN_BUF
	jr   .scr_named
.scr_short:
	push bc							; preserve type across fmt_name83
	call fmt_name83					; -> name83 (uses ix)
	pop  bc
	ld   hl, name83
.scr_named:
	push hl							; name source ptr
	ld   hl, (ARR_PTR)
	ld   (hl), c					; +0 type
	inc  hl
	ld   a, (ix+26)					; +1 cluster low
	ld   (hl), a
	inc  hl
	ld   a, (ix+27)					; +2 cluster high
	ld   (hl), a
	inc  hl
	ld   a, (ix+28)					; +3 file size byte 0 (LE dword)
	ld   (hl), a
	inc  hl
	ld   a, (ix+29)					; +4 file size byte 1
	ld   (hl), a
	inc  hl
	ld   a, (ix+30)					; +5 file size byte 2
	ld   (hl), a
	inc  hl
	ld   a, (ix+31)					; +6 file size byte 3
	ld   (hl), a
	inc  hl							; hl = record+7 (name destination)
	ex   de, hl						; de = dest
	pop  hl							; hl = name source
	call copy_name					; copy up to NAME_MAX, NUL-terminated
	ld   hl, (ARR_PTR)				; advance ARR_PTR by one full record
	ld   de, ENT_SIZE
	add  hl, de
	ld   (ARR_PTR), hl
	ld   a, (ENT_COUNT)
	inc  a
	ld   (ENT_COUNT), a
.scr_drop:
	xor  a
	ld   (HAVE_LFN), a				; clear any pending LFN accumulation
	jr   .scr_next
.scr_lfn:
	call lfn_accumulate				; place this entry's 13 chars into LFN_BUF
	jr   .scr_next
.scr_next:
	ld   de, 32
	add  ix, de
	ld   a, (ent_in_sec)
	dec  a
	ld   (ent_in_sec), a
	jp   nz, .scr_ent
	call inc_sd_lba
	ld   a, (sec_left)
	dec  a
	ld   (sec_left), a
	jp   nz, .scr_sec
.scr_done:
	ret

; lfn_accumulate: place the 13 chars of this LFN entry (IX) into LFN_BUF at
; (seq-1)*13, where seq = (IX+0) & 0x3F. Clears LFN_BUF on the first entry.
lfn_accumulate:
	ld   a, (HAVE_LFN)
	or   a
	jr   nz, .lac_seq
	ld   hl, LFN_BUF				; first of group: clear 80-byte buffer
	ld   (hl), 0
	ld   de, LFN_BUF+1
	ld   bc, 79
	ldir
	ld   a, 1
	ld   (HAVE_LFN), a
.lac_seq:
	ld   a, (ix+0)
	and  #3F						; sequence number (1-based)
	dec  a							; 0-based
	cp   6
	ret  nc							; seq too high -> ignore (name truncated)
	ld   hl, 0
	or   a
	jr   z, .lac_dst
	ld   b, a
	ld   de, 13
.lac_mul:
	add  hl, de
	djnz .lac_mul					; hl = (seq-1)*13
.lac_dst:
	ld   de, LFN_BUF
	add  hl, de
	ex   de, hl						; de = LFN_BUF + (seq-1)*13
	jp   lfn_copy13					; copy 13 chars (ends with ret)

; lfn_copy13: copy the 13 name chars (UTF-16 low bytes) of the LFN entry at IX
; into (DE). Char byte offsets: 1,3,5,7,9, 14,16,18,20,22,24, 28,30.
lfn_copy13:
	ld   a, (ix+1)
	ld   (de), a
	inc  de
	ld   a, (ix+3)
	ld   (de), a
	inc  de
	ld   a, (ix+5)
	ld   (de), a
	inc  de
	ld   a, (ix+7)
	ld   (de), a
	inc  de
	ld   a, (ix+9)
	ld   (de), a
	inc  de
	ld   a, (ix+14)
	ld   (de), a
	inc  de
	ld   a, (ix+16)
	ld   (de), a
	inc  de
	ld   a, (ix+18)
	ld   (de), a
	inc  de
	ld   a, (ix+20)
	ld   (de), a
	inc  de
	ld   a, (ix+22)
	ld   (de), a
	inc  de
	ld   a, (ix+24)
	ld   (de), a
	inc  de
	ld   a, (ix+28)
	ld   (de), a
	inc  de
	ld   a, (ix+30)
	ld   (de), a
	inc  de
	ret

; copy_name: copy name from HL to DE, up to NAME_MAX chars, stopping at NUL or
; 0xFF (LFN padding); then NUL-terminate the destination.
copy_name:
	ld   b, NAME_MAX
.cn_loop:
	ld   a, (hl)
	or   a
	jr   z, .cn_end
	cp   #FF
	jr   z, .cn_end
	ld   (de), a
	inc  hl
	inc  de
	djnz .cn_loop
.cn_end:
	xor  a
	ld   (de), a
	ret

; fat_next_cluster: DE = current cluster -> DE = next cluster (>=0xFFF8 = end).
; FAT16: entry at FAT_LBA + cluster/256, byte offset (cluster&255)*2.
fat_next_cluster:
	ld   a, d						; cluster/256 = high byte
	ld   hl, (FAT_LBA+0)
	push de
	ld   d, 0
	ld   e, a
	add  hl, de
	ld   (SD_LBA+0), hl
	ld   hl, (FAT_LBA+2)
	ld   de, 0
	adc  hl, de
	ld   (SD_LBA+2), hl
	pop  de
	push de							; preserve cluster across sd_read_sector
	call sd_read_sector				; read the FAT sector into SD_BUF
	pop  de
	ld   l, e						; byte offset = (cluster&255)*2
	ld   h, 0
	add  hl, hl
	ld   de, SD_BUF
	add  hl, de
	ld   e, (hl)
	inc  hl
	ld   d, (hl)					; DE = next cluster
	ret

; inc16: HL = address of a 16-bit counter -> increment it.
inc16:
	inc  (hl)
	ret  nz
	inc  hl
	inc  (hl)
	ret

; classify_addr: DE = a "LD (nn),A" target address; bump exactly ONE mapper
; counter, counting only the DISTINGUISHING bank registers of each mapper.
; (Low byte of every bank register is 0; classify by the high byte.)
;   0x50/0x90/0xB0 -> SCC-only    0x80/0xA0 -> Konami-only
;   0x68/0x78      -> ASCII8-only 0x60/0x70 -> ASCII16/generic
classify_addr:
	ld   a, e
	or   a
	ret  nz							; low byte != 0 -> not a bank register
	ld   a, d
	cp   #50
	jr   z, .ca_scc
	cp   #90
	jr   z, .ca_scc
	cp   #B0
	jr   z, .ca_scc
	cp   #80
	jr   z, .ca_kon
	cp   #A0
	jr   z, .ca_kon
	cp   #68
	jr   z, .ca_a8
	cp   #78
	jr   z, .ca_a8
	cp   #60
	jr   z, .ca_a16
	cp   #70
	jr   z, .ca_a16
	ret
.ca_scc:
	ld   hl, MAP_SCC
	jp   inc16
.ca_kon:
	ld   hl, MAP_KON
	jp   inc16
.ca_a8:
	ld   hl, MAP_A8
	jp   inc16
.ca_a16:
	ld   hl, MAP_A16
	jp   inc16

; scan_sector_mapper: scan SD_BUF (512 bytes) for "32 lo hi" (LD (nn),A).
scan_sector_mapper:
	ld   hl, SD_BUF
	ld   bc, 510
.ssm:
	ld   a, (hl)
	cp   #32
	jr   nz, .ssm_n
	push hl
	push bc
	inc  hl
	ld   e, (hl)
	inc  hl
	ld   d, (hl)
	call classify_addr
	pop  bc
	pop  hl
.ssm_n:
	inc  hl
	dec  bc
	ld   a, b
	or   c
	jr   nz, .ssm
	ret

; scan_rom: read the ROM (FILE_CLUS chain), up to 256 sectors, scanning for
; mapper bank-writes into MAP_* counters. Restores CUR_CLUS.
scan_rom:
	ld   hl, 0
	ld   (MAP_SCC), hl
	ld   (MAP_KON), hl
	ld   (MAP_A8), hl
	ld   (MAP_A16), hl
	ld   (SCAN_N), hl
	ld   hl, (CUR_CLUS)
	push hl
	ld   hl, (FILE_CLUS)
	ld   (SCAN_CLUS), hl
.sr_clus:
	ld   hl, (SCAN_CLUS)
	ld   (CUR_CLUS), hl
	call set_scan_start
	ld   a, (SEC_PER_CLUS)
	ld   (SSEC_LEFT), a
.sr_sec:
	call sd_read_sector
	call scan_sector_mapper
	ld   hl, (SCAN_N)
	inc  hl
	ld   (SCAN_N), hl
	ld   a, h						; cap at 512 sectors (256 KB scanned)
	cp   2
	jr   nc, .sr_done
	call inc_sd_lba
	ld   a, (SSEC_LEFT)
	dec  a
	ld   (SSEC_LEFT), a
	jr   nz, .sr_sec
	ld   de, (SCAN_CLUS)
	call fat_next_cluster
	ld   a, d
	cp   #FF
	jr   nz, .sr_more
	ld   a, e
	cp   #F8
	jr   nc, .sr_done
.sr_more:
	ld   a, d
	or   e
	jr   z, .sr_done
	ld   (SCAN_CLUS), de
	jr   .sr_clus
.sr_done:
	pop  hl
	ld   (CUR_CLUS), hl
	ret

; sig_ok: HL = a counter -> CF=1 if it reaches MAP_THRESH (a real signature).
sig_ok:
	ld   a, h
	or   a
	jr   nz, .sok_yes				; high byte set -> well over threshold
	ld   a, l
	cp   MAP_THRESH
	jr   nc, .sok_yes				; l >= THRESH
	or   a							; CF = 0
	ret
.sok_yes:
	scf
	ret

; decide_mapper: priority by DISTINGUISHING signature (ASCII8 -> SCC -> Konami ->
; ASCII16). No signature -> plain/linear. Fixes ASCII16 being seen as Konami-SCC.
decide_mapper:
	ld   hl, (MAP_A8)
	call sig_ok
	jr   c, .dm_a8
	ld   hl, (MAP_SCC)
	call sig_ok
	jr   c, .dm_scc
	ld   hl, (MAP_KON)
	call sig_ok
	jr   c, .dm_kon
	ld   hl, (MAP_A16)
	call sig_ok
	jr   c, .dm_a16
	ld   a, MAP_PLAIN				; no mapper writes -> plain/linear
	ld   (MAPPER_ID), a
	ret
.dm_a8:
	ld   a, MAP_A8_ID
	ld   (MAPPER_ID), a
	ret
.dm_scc:
	ld   a, MAP_SCC_ID
	ld   (MAPPER_ID), a
	ret
.dm_kon:
	ld   a, MAP_KON_ID
	ld   (MAPPER_ID), a
	ret
.dm_a16:
	ld   a, MAP_A16_ID
	ld   (MAPPER_ID), a
	ret

; detect_mapper: decide MAPPER_ID for the selected file. <=32 KB -> plain; else
; scan the content. Uses the file size in the record (BR_REC+3 dword) for the rule.
detect_mapper:
	ld   hl, (BR_REC)
	ld   de, 5
	add  hl, de
	ld   a, (hl)					; size byte 2
	inc  hl
	or   (hl)						; | size byte 3
	jr   nz, .det_scan				; > 64 KB -> scan
	ld   hl, (BR_REC)
	ld   de, 4
	add  hl, de
	ld   a, (hl)					; size byte 1 (x256)
	cp   #80						; < 0x8000 (32 KB)?
	jr   nc, .det_scan				; 32..64 KB -> scan to be sure
	ld   a, MAP_PLAIN
	ld   (MAPPER_ID), a
	ret
.det_scan:
	call scan_rom
	jp   decide_mapper

; megaram_test: set the megaram to Konami-SCC mode (OCM SWIO), write-enable it,
; write A5/5A to bank 0, read them back into MEG_T0/MEG_T1. No reset (safe).
; If the readback is A5 5A the megaram load mechanism works.
megaram_test:
	di
	; --- OCM SWIO smart command: set Slot2 = Internal SCC-I (Konami-SCC mode) ---
	; (Slot2Mode is driven by the virtual DIP-SW, changed via a smart command on
	;  port 0x41, NOT by writing port 0x42 directly. 0x0F = Ext Slot1 + Int SCC-I
	;  Slot2 -> io42[5:3]="010" -> Slot2Mode=10 -> megaram map_sel[0]=0 = SCC mode.)
	ld   a, #D4
	out  (#40), a					; select smart device ID212
	ld   a, #0F
	out  (#41), a					; smart command: Internal SCC-I in Slot2
	in   a, (#42)					; diagnostic readback (expect bit4 set, bit5 clear)
	ld   (MEG_P42), a
	; --- map page 1 to the megaram slot ---
	ld   a, MEG_SLOT
	ld   hl, #4000
	call ENASLT
	ld   a, (#4000)					; diagnostic: megaram content BEFORE writing
	ld   (MEG_B0), a
	; bank 0 -> reg0 (write-enable must be OFF to set the bank register)
	xor  a
	ld   (#7FFE), a					; mode_a = 0
	xor  a
	ld   (#5000), a					; megaram_reg0 = 0 (segment 0 at 0x4000-0x5FFF)
	; enable writing
	ld   a, #10
	ld   (#7FFE), a					; mode_a bit4 = 1 (write enable)
	ld   a, #A5
	ld   (#4000), a
	ld   a, #5A
	ld   (#4001), a
	xor  a
	ld   (#7FFE), a					; write disable
	ld   a, (#4000)					; read back
	ld   (MEG_T0), a
	ld   a, (#4001)
	ld   (MEG_T1), a
	; restore page 1 -> slot 3-1 (this menu)
	ld   a, #87
	ld   hl, #4000
	call ENASLT
	ei
	ret

; write_sector_to_megaram: copy SD_BUF (512 B) into the megaram at LOAD_SEG/LOAD_OFF
; (8K-segment linear). Sets the bank + write-enable at each segment start.
write_sector_to_megaram:
	ld   a, MEG_SLOT				; page 1 -> megaram (slot 2)
	ld   hl, #4000
	call ENASLT
	ld   hl, (LOAD_OFF)
	ld   a, h
	or   l
	jr   nz, .wsm_copy				; mid-segment -> just copy
	xor  a							; new 8K segment: disable write, set bank, enable write
	ld   (#7FFE), a
	ld   a, (LOAD_SEG)
	ld   (#5000), a					; megaram_reg0 = segment
	ld   a, #10
	ld   (#7FFE), a
.wsm_copy:
	ld   hl, (LOAD_OFF)
	ld   de, #4000
	add  hl, de
	ex   de, hl						; de = 0x4000 + offset
	ld   hl, SD_BUF
	ld   bc, 512
	ldir
	ld   a, #87						; page 1 -> slot 3-1
	ld   hl, #4000
	call ENASLT
	ld   hl, (LOAD_OFF)				; advance offset, wrap to next segment at 8 KB
	ld   de, 512
	add  hl, de
	ld   (LOAD_OFF), hl
	ld   a, h
	cp   #20						; 0x2000 = 8192
	ret  c
	ld   hl, 0
	ld   (LOAD_OFF), hl
	ld   a, (LOAD_SEG)
	inc  a
	ld   (LOAD_SEG), a
	ret

; load_rom: load the whole ROM (FILE_CLUS chain) into the megaram, 8K linear.
load_rom:
	ld   a, #D4						; SWIO: Slot2 = Int SCC-I (megaram -> slot 2, SCC mode)
	out  (#40), a
	ld   a, #0F
	out  (#41), a
	ld   hl, #010D					; progress bar row (its own line; max 64 blocks)
	call POSIT
	xor  a
	ld   (LOAD_SEG), a
	ld   hl, 0
	ld   (LOAD_OFF), hl
	ld   hl, (CUR_CLUS)
	push hl
	ld   hl, (FILE_CLUS)
	ld   (LOAD_CLUS), hl
.lro_clus:
	ld   hl, (LOAD_CLUS)
	ld   (CUR_CLUS), hl
	call set_scan_start
	ld   a, (SEC_PER_CLUS)
	ld   (SSEC_LEFT), a
.lro_sec:
	call sd_read_sector
	call write_sector_to_megaram
	ld   hl, (LOAD_OFF)				; LOAD_OFF wrapped to 0 -> one 8K segment done
	ld   a, h
	or   l
	jr   nz, .lro_nobar
	ld   a, (LOAD_SEG)				; cap the bar at 64 blocks so it never wraps the
	cp   65							; line (a 2 MB ROM is 256 segments otherwise)
	jr   nc, .lro_nobar
	ld   a, #DB						; solid block -> progress bar tick
	call CHPUT
.lro_nobar:
	call inc_sd_lba
	ld   a, (SSEC_LEFT)
	dec  a
	ld   (SSEC_LEFT), a
	jr   nz, .lro_sec
	ld   de, (LOAD_CLUS)
	call fat_next_cluster
	ld   a, d
	cp   #FF
	jr   nz, .lro_more
	ld   a, e
	cp   #F8
	jr   nc, .lro_done
.lro_more:
	ld   a, d
	or   e
	jr   z, .lro_done
	ld   (LOAD_CLUS), de
	jr   .lro_clus
.lro_done:
	pop  hl
	ld   (CUR_CLUS), hl
	ret

; read_megaram_seg: A = segment; read its first 8 bytes from the megaram into MEG_RB.
read_megaram_seg:
	push af
	ld   a, MEG_SLOT
	ld   hl, #4000
	call ENASLT
	xor  a
	ld   (#7FFE), a					; write-disable so the bank register accepts the write
	pop  af
	ld   (#5000), a					; megaram_reg0 = segment
	ld   hl, #4000
	ld   de, MEG_RB
	ld   bc, 8
	ldir
	ld   a, #87
	ld   hl, #4000
	call ENASLT
	ret

; override_mapper_by_name: if the selected file's name contains a GoodMSX mapper
; tag ([ASCII16]/[ASCII8]/[KonamiSCC]/[SCC]/[Konami]) set MAPPER_ID from it. The
; name tag is far more reliable than scanning code for bank-write opcodes (many
; games bank-switch via LD (HL),A which the opcode scan misses, e.g. Ikari).
; BR_REC must point at the selected record (name ASCIIZ at +NAME_OFF).
override_mapper_by_name:
	ld   hl, (BR_REC)
	ld   de, NAME_OFF
	add  hl, de
	ld   (TAGPTR), hl				; haystack = filename
	ld   hl, tag_a16
	call name_contains
	jr   nc, .omn_a8
	ld   a, MAP_A16_ID
	jr   .omn_set
.omn_a8:
	ld   hl, tag_a8
	call name_contains
	jr   nc, .omn_scc
	ld   a, MAP_A8_ID
	jr   .omn_set
.omn_scc:
	ld   hl, tag_scc
	call name_contains
	jr   nc, .omn_kon
	ld   a, MAP_SCC_ID
	jr   .omn_set
.omn_kon:
	ld   hl, tag_kon
	call name_contains
	ret  nc							; no tag -> keep the code-scan result
	ld   a, MAP_KON_ID
.omn_set:
	ld   (MAPPER_ID), a
	ret

; name_contains: case-sensitive substring search. HL = needle (ASCIIZ);
; (TAGPTR) = haystack (ASCIIZ). Returns CF=1 if needle occurs in haystack.
name_contains:
	ld   (NEEDLE), hl
	ld   hl, (TAGPTR)
.ncs_try:
	ld   a, (hl)
	or   a
	jr   z, .ncs_nf					; end of haystack -> not found
	push hl							; remember this start position
	ld   de, (NEEDLE)
.ncs_cmp:
	ld   a, (de)
	or   a
	jr   z, .ncs_found				; end of needle -> matched
	ld   c, a						; needle char (tags are stored UPPER-case)
	ld   a, (hl)					; haystack char -> upper-case for case-insensitive cmp
	cp   'a'
	jr   c, .ncs_noup
	cp   'z' + 1
	jr   nc, .ncs_noup
	sub  #20						; 'a'..'z' -> 'A'..'Z'
.ncs_noup:
	cp   c
	jr   nz, .ncs_next
	inc  hl
	inc  de
	jr   .ncs_cmp
.ncs_next:
	pop  hl
	inc  hl
	jr   .ncs_try
.ncs_found:
	pop  hl
	scf
	ret
.ncs_nf:
	or   a							; CF = 0
	ret

tag_a16:
	.db "ASCII16",0
tag_a8:
	.db "ASCII8",0
tag_scc:
	.db "SCC",0
tag_kon:
	.db "KONAMI",0

; launch_rom: ROM already loaded into the megaram (SCC mode). Boot it DIRECTLY
; (no BIOS reset — the reset re-runs the menu cartridge in slot 3-1 instead of
; the game): leave the megaram clean (while still in SCC mode), set the game's
; real mapper mode via the OCM SWIO smart command, then run a tiny stub in
; page-3 RAM that switches pages 1+2 to slot 2 and jumps to the cart INIT.
launch_rom:
	di
	; 1) clean megaram to cartridge state -- MUST be in SCC mode (writes to
	;    0x7FFE/0x5000 are SCC control regs; in ASCII mode they are bank regs)
	ld   a, MEG_SLOT				; page 1 -> megaram (slot 2)
	ld   hl, #4000
	call ENASLT
	xor  a
	ld   (#7FFE), a					; mode_a = 0 : write-protect (normal cartridge)
	xor  a
	ld   (#5000), a					; bank reg0 = 0 (first 8 KB at 0x4000)
	; 2) set the game's real mapper mode via the OCM SWIO smart command
	ld   a, (MAPPER_ID)
	cp   MAP_A8_ID
	jr   z, .lr_a8
	cp   MAP_A16_ID
	jr   z, .lr_a16
	ld   a, #0F						; SCC / Konami / plain
	jr   .lr_setmap
.lr_a8:
	ld   a, #11						; Int ASCII8K
	jr   .lr_setmap
.lr_a16:
	ld   a, #13						; Int ASCII16K
.lr_setmap:
	ld   b, a
	ld   a, #D4						; SWIO: select ID212
	out  (#40), a
	ld   a, b
	out  (#41), a					; set Slot2Mode -> map_sel (mapper mode)
	; 2b) reset the VDP to a clean state. INIT32 fixes R0-R7 + the BIOS work-area
	;     mirror; then we clear the MSX2/V9958 registers R8-R23 + R25-R27 that the
	;     menu's TEXT2 80-col mode left dirty (display adjust R18, line-int R19,
	;     vertical scroll R23, ...). Without this, MSX2 games that only set some
	;     VDP regs inherit garbage -> distortion / top-of-screen rubbish (Metal
	;     Gear 2, Space Manbow). Done here (page 2, IRQs off); the stub afterwards
	;     only flips slots, so the VDP stays clean until the game's own INIT.
	call #006F						; INIT32 (SCREEN 1): R0-R7 + work-area mirror
	di								; INIT32 may have re-enabled IRQs
	ld   hl, vdp_clean_tbl
	ld   b, 19						; R8-R23 (16 regs) + R25-R27 (3 regs)
.lr_vdp:
	ld   a, (hl)
	inc  hl
	out  (#99), a					; data byte
	ld   a, (hl)
	inc  hl
	out  (#99), a					; register select (0x80 | reg)
	djnz .lr_vdp
	; 3) copy the boot stub to page-3 RAM (#E000) and jump to it
	ld   hl, boot_stub
	ld   de, #E000
	ld   bc, boot_stub_end - boot_stub
	ldir
	jp   #E000

; clean MSX2/V9958 VDP register values: (data, 0x80|reg) pairs for R8-R23,R25-27
vdp_clean_tbl:
	.db #08,#88						; R8  = 0x08 (VR=64K, color0 opaque)
	.db #00,#89						; R9  = 192 lines, no interlace
	.db #00,#8A, #00,#8B, #00,#8C, #00,#8D, #00,#8E, #00,#8F
	.db #00,#90, #00,#91
	.db #00,#92						; R18 = display adjust 0 (centered)
	.db #00,#93						; R19 = line-interrupt line 0
	.db #00,#94, #00,#95, #00,#96
	.db #00,#97						; R23 = vertical scroll 0
	.db #00,#99						; R25 = 0 (V9958 modes/scroll)
	.db #00,#9A						; R26 = 0 (V9958 horiz scroll H)
	.db #00,#9B						; R27 = 0 (V9958 horiz scroll L)

; boot_stub: runs from #E000 (page-3 RAM). Position-independent (absolute refs
; only). Switches pages 1+2 to slot 2 (megaram = the loaded ROM), then jumps to
; the cartridge INIT vector at 0x4002 the way the BIOS boots a cartridge.
boot_stub:
	ld   sp, #F380					; standard MSX boot stack (page-3 RAM)
	ld   a, #02						; page 1 (0x4000) -> slot 2
	ld   hl, #4000
	call ENASLT
	ld   a, #02						; page 2 (0x8000) -> slot 2
	ld   hl, #8000
	call ENASLT
	ld   hl, (#4002)				; cartridge INIT vector
	ei
	jp   (hl)
boot_stub_end:

; -----------------------------------------------------------------------------
; browse: scrolling browser over ENT_ARRAY. Cursor up/down move the selection,
; RETURN shows the selected entry, ESC returns to the main menu. Input goes via
; the BIOS (ei/halt/CHSNS/CHGET) so the cursor keys are delivered (same method as
; the config menu; the direct PPI matrix scan missed row 8).
; -----------------------------------------------------------------------------
browse:
.br_redraw:
	call draw_browser
.br_key:
	call browse_getkey				; A = key code
	cp   #1E						; cursor up
	jp   z, .br_up
	cp   #1F						; cursor down
	jp   z, .br_down
	cp   #1C						; cursor right (next column)
	jp   z, .br_right
	cp   #1D						; cursor left (prev column)
	jp   z, .br_left
	cp   #0D						; RETURN
	jp   z, .br_enter
	cp   #08						; BACKSPACE -> parent folder
	jp   z, .br_back
	cp   #09						; TAB -> next partition (multi-partition cards)
	jp   z, .br_nextpart
	cp   #53						; 'S' -> Settings (Ajustes)
	jp   z, config_menu_entry
	cp   #73						; 's'
	jp   z, config_menu_entry
	cp   #57						; 'W' -> WiFi config (ESP ROM menu)
	jp   z, main_action_wifi
	cp   #77						; 'w'
	jp   z, main_action_wifi
	cp   #48						; 'H' -> help overlay
	jp   z, .br_help
	cp   #68						; 'h'
	jp   z, .br_help
	cp   #52						; 'R' -> filter: ROMs only
	jp   z, .br_from
	cp   #72						; 'r'
	jp   z, .br_from
	cp   #44						; 'D' -> filter: disks only
	jp   z, .br_fdsk
	cp   #64						; 'd'
	jp   z, .br_fdsk
	cp   #41						; 'A' -> filter: all
	jp   z, .br_fall
	cp   #61						; 'a'
	jp   z, .br_fall
	cp   #1B						; ESC -> arrancar sistema (boot the OS)
	jp   z, boot_system
	jr   .br_key
.br_help:
	call help_screen
	jp   .br_redraw
.br_from:
	xor  a							; FILTER = 0 (ROM)
	jr   .br_setfilter
.br_fdsk:
	ld   a, 1						; FILTER = 1 (DSK)
	jr   .br_setfilter
.br_fall:
	ld   a, 2						; FILTER = 2 (ALL)
.br_setfilter:
	ld   (FILTER), a
	call scan_current				; re-scan current dir applying the new filter
	xor  a
	ld   (BR_SEL), a
	ld   (BR_TOP), a
	call draw_tabs					; update active-tab highlight
	call refresh_list				; soft repaint (no full-screen flicker)
	jp   .br_key
.br_nextpart:
	ld   a, (PART_CNT)
	cp   2
	jp   c, .br_key					; only one partition -> ignore TAB
	ld   a, (CUR_PART)
	inc  a							; next index, wrap to 0 at PART_CNT
	ld   hl, PART_CNT
	cp   (hl)
	jr   c, .bnp_go
	xor  a
.bnp_go:
	call select_partition			; switch partition (re-scans its root)
	jp   c, .br_key					; SD error -> stay
	call refresh_list				; repaint only the list+footer (bars don't flash)
	jp   .br_key
.br_up:
	ld   a, (BR_SEL)
	ld   (BR_OLD), a				; remember old selection
	or   a
	jr   nz, .bu_dec
	; at the top -> wrap to the LAST entry (fast jump to the end)
	ld   a, (ENT_COUNT)
	or   a
	jp   z, .br_key					; empty list
	dec  a
	ld   (BR_SEL), a
	jp   .br_move
.bu_dec:
	dec  a
	ld   (BR_SEL), a
	jp   .br_move
.br_down:
	ld   a, (ENT_COUNT)
	ld   b, a
	ld   a, (BR_SEL)
	ld   (BR_OLD), a				; remember old selection
	inc  a
	cp   b
	jr   c, .bd_set					; sel+1 < count -> normal move down
	; at the bottom -> wrap to the FIRST entry
	xor  a
	ld   (BR_SEL), a
	jp   .br_move
.bd_set:
	ld   (BR_SEL), a
	jp   .br_move
.br_right:
	ld   a, (BR_SEL)
	add  a, VISIBLE				; sel + 22 (jump to next column / down a page-half)
	ld   c, a
	ld   a, (ENT_COUNT)
	cp   c
	jp   c, .br_key					; candidate beyond list
	jp   z, .br_key
	ld   a, (BR_SEL)
	ld   (BR_OLD), a
	ld   a, c
	ld   (BR_SEL), a
	jp   .br_move
.br_left:
	ld   a, (BR_SEL)
	cp   VISIBLE
	jp   c, .br_key					; already in first column
	ld   (BR_OLD), a
	sub  VISIBLE
	ld   (BR_SEL), a
	jp   .br_move
.br_move:
	; Repaint only the old and new rows so the '>' marker moves without a
	; full-screen redraw (no flicker). Full redraw only when the page scrolls.
	ld   a, (BR_TOP)
	ld   (BR_OLDTOP), a
	call ensure_visible
	ld   a, (BR_TOP)
	ld   hl, BR_OLDTOP
	cp   (hl)
	jp   nz, .br_scroll				; page scrolled -> repaint rows in place (no clear)
	ld   a, (BR_OLD)
	call draw_entry					; repaint old row (clears its '>')
	ld   a, (BR_SEL)
	call draw_entry					; repaint new row (draws '>')
	jp   .br_key
.br_scroll:
	call draw_rows					; redraw the visible rows WITHOUT clearing screen
	jp   .br_key
.br_enter:
	ld   a, (ENT_COUNT)
	or   a
	jp   z, .br_key					; empty list
	ld   a, (BR_SEL)
	call ent_addr					; hl = record
	ld   a, (hl)					; type (0=dir, 1=rom, 2=dsk)
	or   a
	jr   z, .br_isdir				; 0 = directory
	dec  a
	jp   z, .br_selrom				; 1 = rom -> load to megaram + launch
	jp   .br_seldsk					; 2 = dsk -> Nextor disk emulation + boot
.br_isdir:
	; --- directory: push current cluster, descend ---
	ld   a, (DIR_SP)
	cp   8
	jp   nc, .br_key				; stack full -> ignore
	ld   e, a						; DIR_STACK[DIR_SP] = CUR_CLUS
	ld   d, 0
	ld   hl, DIR_STACK
	add  hl, de
	add  hl, de
	ld   de, (CUR_CLUS)
	ld   (hl), e
	inc  hl
	ld   (hl), d
	ld   a, (DIR_SP)
	inc  a
	ld   (DIR_SP), a
	ld   a, (BR_SEL)				; CUR_CLUS = selected dir's first cluster
	call ent_addr
	inc  hl
	ld   e, (hl)					; record+1 cluster low
	inc  hl
	ld   d, (hl)					; record+2 cluster high
	ld   (CUR_CLUS), de
	call scan_current
	xor  a
	ld   (BR_SEL), a
	ld   (BR_TOP), a
	call refresh_list				; soft repaint of the new directory (no flicker)
	jp   .br_key
.br_selrom:
	; --- selected file: load it straight into the megaram, then offer to launch.
	;     No debug dump, no separate "load" step -> fastest path to launch. ---
	ld   a, (BR_SEL)
	call ent_addr
	ld   (BR_REC), hl				; record (size at +3, name at +7)
	inc  hl
	ld   e, (hl)
	inc  hl
	ld   d, (hl)					; DE = first cluster
	ld   (FILE_CLUS), de
	ld   a, #FF						; mapper: prefer GoodMSX name tag (fast);
	ld   (MAPPER_ID), a				; only run the slow code scan if there is no tag
	call override_mapper_by_name
	ld   a, (MAPPER_ID)
	cp   #FF
	jr   nz, .bsr_have
	call detect_mapper
.bsr_have:
	call cls_browser
	ld   hl, #0101
	call POSIT
	ld   hl, romInfoStr				; "ROM seleccionada:"
	call print_string
	ld   hl, #0103
	call POSIT
	ld   hl, (BR_REC)
	ld   de, NAME_OFF
	add  hl, de
	call print_string				; ROM name
	ld   hl, #0105
	call POSIT
	ld   hl, romClusStr				; "Tamano: "
	call print_string
	call print_rom_kb
	ld   a, 'K'
	call CHPUT
	ld   hl, romSpcStr				; "  Mapper: "
	call print_string
	call print_mapper_name
	ld   hl, #0107
	call POSIT
	ld   hl, loadingStr				; "Cargando ROM en megaram..."
	call print_string
	call load_rom					; load now, automatically (progress bar)
	ld   hl, #0109
	call POSIT
	ld   hl, launch2Str				; "RETURN=LANZAR JUEGO   ESC=volver"
	call print_string
.bsr_lk:
	call browse_getkey
	cp   #0D
	jp   z, launch_rom
	cp   #1B
	jp   z, .br_redraw
	jr   .bsr_lk

.br_seldsk:
	; --- selected .dsk: set up Nextor disk-emulation mode and boot it ---
	; Nextor checks RAM #A000 for the "NEXTOR_EMU_DATA" record on every boot
	; (one-time mode). We run in the cartridge INIT (slot 3-1) DURING the cold-boot
	; slot scan, BEFORE Nextor (slot 3-2) initialises -> we just write the record
	; and let the boot continue; Nextor reads it and mounts the image as drive A:
	; in MSX-DOS 1 mode, then runs its boot sector. No reset needed.
	ld   a, (BR_SEL)
	call ent_addr
	ld   (BR_REC), hl
	inc  hl
	ld   e, (hl)
	inc  hl
	ld   d, (hl)					; DE = first cluster of the .dsk
	ld   (FILE_CLUS), de
	call cls_browser
	ld   hl, #0101
	call POSIT
	ld   hl, dskInfoStr				; "Disco seleccionado:"
	call print_string
	ld   hl, #0103
	call POSIT
	ld   hl, (BR_REC)
	ld   de, NAME_OFF
	add  hl, de
	call print_string				; .dsk name
	ld   hl, #0105
	call POSIT
	ld   hl, dskAskStr				; "RETURN=montar y lanzar   ESC=volver"
	call print_string
.bsd_ask:
	call browse_getkey
	cp   #0D
	jr   z, .bsd_go					; RETURN -> mount + launch
	cp   #1B
	jp   z, .br_redraw				; ESC -> back to the browser
	jr   .bsd_ask
.bsd_go:
	ld   hl, #0107
	call POSIT
	ld   hl, dskMountStr			; "Montando disco (Nextor) y arrancando..."
	call print_string
	; 1) the image must be unfragmented (Nextor maps a linear sector range)
	call dsk_check_contig
	jr   nc, .bsd_contig
	ld   hl, #0107
	call POSIT
	ld   hl, dskFragStr
	call print_string
	call browse_getkey
	jp   .br_redraw
.bsd_contig:
	; 2) absolute start LBA of the .dsk -> DSK_LBA
	ld   hl, (FILE_CLUS)
	ld   (CUR_CLUS), hl
	call set_scan_start				; SD_LBA = abs LBA of the .dsk first cluster
	ld   hl, (SD_LBA+0)
	ld   (DSK_LBA+0), hl
	ld   hl, (SD_LBA+2)
	ld   (DSK_LBA+2), hl
	; 3) image size in 512-byte sectors = ceil(size/512) = (size+511)>>9  (16-bit)
	ld   hl, (BR_REC)
	ld   de, 3
	add  hl, de						; hl -> size dword (LE) at record+3
	ld   e, (hl)
	inc  hl
	ld   d, (hl)
	inc  hl
	ld   c, (hl)
	inc  hl
	ld   b, (hl)					; bcde = 32-bit size (b=MSB, e=LSB)
	ld   hl, #01FF					; + 511
	add  hl, de
	ex   de, hl
	ld   hl, 0
	adc  hl, bc						; hl:de = size+511 (hl = high word)
	ld   b, h
	ld   c, l						; bc = high word -> c = byte2, b = byte3
	ld   l, d						; (size+511) >> 8  -> l=byte1, h=byte2 (floppy: byte3=0)
	ld   h, c
	srl  h							; >> 1  => >> 9 total
	rr   l
	ld   (DSK_SECS), hl				; sectors in the image
	; 4) locate (or auto-create) the NEXTOR.EMU helper file in this partition's root
	call find_emufile
	jr   nc, .bsd_haveemu
	call create_emufile				; not found -> create it (CF=1 on failure)
	jr   nc, .bsd_haveemu
.bsd_noemu:
	ld   hl, #0107
	call POSIT
	ld   hl, dskNoEmuStr
	call print_string
	call browse_getkey
	jp   .br_redraw
.bsd_haveemu:
	; FILE_CLUS now = NEXTOR.EMU first cluster -> its abs LBA = the data-file sector.
	; Safety net: never write with cluster < 2 (set_scan_start(0/1) would target the
	; root dir / reserved area and corrupt the filesystem).
	ld   hl, (FILE_CLUS)
	ld   a, h
	or   a
	jr   nz, .bsd_clok
	ld   a, l
	cp   2
	jp   c, .bsd_noemu				; invalid cluster -> abort, do NOT write
.bsd_clok:
	ld   (CUR_CLUS), hl
	call set_scan_start
	ld   hl, (SD_LBA+0)
	ld   (EMU_LBA+0), hl
	ld   hl, (SD_LBA+2)
	ld   (EMU_LBA+2), hl
	; 5) build the emulation data file in SD_BUF and write it to NEXTOR.EMU sector 0
	call build_emu_datafile
	call sd_write_sector			; SD_LBA still = EMU_LBA
	ld   a, (SD_STATUS)
	or   a
	jr   z, .bsd_wrok
	ld   hl, #0107
	call POSIT
	ld   hl, dskWrErrStr
	call print_string
	call browse_getkey
	jp   .br_redraw
.bsd_wrok:
	; 6) one-time pointer at #A000 -> the data file (device 1, LUN 1, EMU_LBA)
	ld   hl, emuSig
	ld   de, #A000
	ld   bc, 16
	ldir
	ld   a, 1
	ld   (#A010), a					; device index (WonderTANG SD) [verify if needed]
	ld   a, 1
	ld   (#A011), a					; LUN
	ld   hl, (EMU_LBA+0)
	ld   (#A012), hl
	ld   hl, (EMU_LBA+2)
	ld   (#A014), hl
	jp   boot_system				; continue boot with Nextor ON -> Nextor emulates A:
.br_back:
	ld   a, (DIR_SP)
	or   a
	jp   z, .br_key					; already at root
	dec  a
	ld   (DIR_SP), a
	ld   e, a						; CUR_CLUS = DIR_STACK[DIR_SP]
	ld   d, 0
	ld   hl, DIR_STACK
	add  hl, de
	add  hl, de
	ld   e, (hl)
	inc  hl
	ld   d, (hl)
	ld   (CUR_CLUS), de
	call scan_current
	xor  a
	ld   (BR_SEL), a
	ld   (BR_TOP), a
	call refresh_list				; soft repaint of the parent directory (no flicker)
	jp   .br_key

; print_rom_kb: print the selected ROM's size in KB (decimal) from BR_REC.
print_rom_kb:
	ld   hl, (BR_REC)
	ld   de, 4
	add  hl, de
	ld   a, (hl)					; size byte 1
	srl  a
	srl  a
	ld   c, a
	ld   hl, (BR_REC)
	ld   de, 5
	add  hl, de
	ld   e, (hl)
	inc  hl
	ld   d, (hl)
	ex   de, hl						; hl = size >> 16
	add  hl, hl
	add  hl, hl
	add  hl, hl
	add  hl, hl
	add  hl, hl
	add  hl, hl						; * 64
	ld   e, c
	ld   d, 0
	add  hl, de						; hl = KB
	jp   print_dec16

; print_mapper_name: print the detected mapper's name (MAPPER_ID).
print_mapper_name:
	ld   a, (MAPPER_ID)
	cp   MAP_KON_ID
	jr   z, .pmn_kon
	cp   MAP_SCC_ID
	jr   z, .pmn_scc
	cp   MAP_A8_ID
	jr   z, .pmn_a8
	cp   MAP_A16_ID
	jr   z, .pmn_a16
	cp   MAP_PLAIN
	jr   z, .pmn_plain
	ld   hl, mapUnkStr
	jp   print_string
.pmn_plain:
	ld   hl, mapPlainStr
	jp   print_string
.pmn_kon:
	ld   hl, mapKonStr
	jp   print_string
.pmn_scc:
	ld   hl, mapSccStr
	jp   print_string
.pmn_a8:
	ld   hl, mapA8Str
	jp   print_string
.pmn_a16:
	ld   hl, mapA16Str
	jp   print_string

; ensure_visible: adjust BR_TOP so BR_SEL is within the visible window.
ensure_visible:
	ld   a, (BR_SEL)
	ld   hl, BR_TOP
	cp   (hl)
	jr   nc, .ev1
	ld   (BR_TOP), a				; sel < top -> top = sel
	ret
.ev1:
	ld   a, (BR_TOP)
	add  a, VISIBLE
	ld   b, a						; top + VISIBLE
	ld   a, (BR_SEL)
	cp   b
	ret  c							; sel < top+VISIBLE -> already visible
	sub  VISIBLE - 1
	ld   (BR_TOP), a				; top = sel - (VISIBLE-1)
	ret

; browse_getkey: wait for input from the keyboard (cursors via CHGET) OR the
; joystick (GTSTCK/GTTRIG, edge-detected) and return it as a key code.
browse_getkey:
	ei
.bgk_loop:
	halt
	call marquee_tick				; scroll the selected long name while idle (browser only)
	call CHSNS						; keyboard pending?
	jr   z, .bgk_joy
	call CHGET
	or   a
	jr   z, .bgk_loop
	ret
.bgk_joy:
	call poll_joy					; A = joystick code (0 = nothing new)
	or   a
	jr   z, .bgk_loop
	ret

; poll_joy: read joystick 1, edge-detect against JOY_PREV. Returns a key code on
; a fresh press (0 otherwise) so holding the stick yields one event per push.
poll_joy:
	call read_joy_code				; A = code for the current joystick state
	ld   hl, JOY_PREV
	cp   (hl)
	jr   z, .pj_held				; unchanged -> held (maybe auto-repeat)
	ld   (hl), a					; state changed -> store
	ld   b, a
	ld   a, JOY_RPT_DELAY			; (re)arm the auto-repeat initial delay
	ld   (JOY_RPT), a
	ld   a, b
	or   a
	ret  nz							; fresh non-neutral press -> emit now
	xor  a
	ret
.pj_held:
	or   a
	jr   z, .pj_zero				; neutral held -> nothing
	cp   #1C						; only auto-repeat the 4 directions (1C..1F),
	jr   c, .pj_zero				; not the A/B buttons (RETURN 0D / BS 08)
	ld   b, a						; save the direction code
	ld   a, (JOY_RPT)
	dec  a
	ld   (JOY_RPT), a
	jr   nz, .pj_zero				; delay not elapsed -> nothing this frame
	ld   a, JOY_RPT_RATE			; reload interval for the next repeat
	ld   (JOY_RPT), a
	ld   a, b						; emit the held direction (fast repeat)
	ret
.pj_zero:
	xor  a
	ret

; read_joy_code: map joystick 1 direction/buttons to menu key codes.
;   up=VT_UP down=VT_DOWN left=VT_LEFT right=VT_RIGHT  A=RETURN  B=BACKSPACE
read_joy_code:
	ld   a, 1
	call GTSTCK						; A = direction 0..8 (joystick 1)
	cp   1
	jr   z, .rjc_up
	cp   5
	jr   z, .rjc_down
	cp   3
	jr   z, .rjc_right
	cp   7
	jr   z, .rjc_left
	ld   a, 1						; trigger A (joystick 1) -> select
	call GTTRIG
	or   a
	jr   nz, .rjc_a
	ld   a, 3						; trigger B (joystick 1) -> back
	call GTTRIG
	or   a
	jr   nz, .rjc_b
	xor  a
	ret
.rjc_up:
	ld   a, #1E
	ret
.rjc_down:
	ld   a, #1F
	ret
.rjc_right:
	ld   a, #1C
	ret
.rjc_left:
	ld   a, #1D
	ret
.rjc_a:
	ld   a, #0D
	ret
.rjc_b:
	ld   a, #08
	ret

; draw_hline: A = row (1-based). Draw a thin horizontal line using the custom glyph
; (char 0x10) written straight into the name table — CHPUT would interpret control
; codes, so we FILVRM the code into VRAM (name table at 0x0000, 80 cols/row).
draw_hline:
	dec  a							; physical row (0-based)
	ld   l, a
	ld   h, 0
	add  hl, hl						; *2
	add  hl, hl						; *4
	add  hl, hl						; *8
	add  hl, hl						; *16
	ld   d, h
	ld   e, l						; DE = row*16
	add  hl, hl						; *32
	add  hl, hl						; *64
	add  hl, de						; HL = row*80 (name-table offset)
	ld   a, #10						; thin-line glyph
	ld   bc, 78
	call FILVRM
	ret

; load_font: (re)load our custom glyphs into the TEXT2 pattern table (VRAM 0x1000).
; Must run after every INITXT (which reloads the BIOS font). Char 0x10 = thin line.
load_font:
	di
	ld   a, #80						; VRAM write addr = 0x1080 (0x1000 + 0x10*8)
	out  (#99), a
	ld   a, #50						; high 0x10 | write bit 0x40 -> char 0x10
	out  (#99), a
	ld   hl, font_pat
	ld   b, 8
.lf_loop:
	ld   a, (hl)
	out  (#98), a
	inc  hl
	djnz .lf_loop
	ei
	ret
font_pat:
	.db #00,#00,#00,#00,#FF,#00,#00,#00	; 0x10 thin horizontal line (row 4)

; draw_tabs: row 2 filter tabs "[R]OM [D]SK [A]LL"; active one inverse via blink.
draw_tabs:
	ld   hl, #0102					; X=1, Y=2
	call POSIT
	ld   hl, tabRStr
	call print_string
	ld   hl, #0902					; X=9, Y=2
	call POSIT
	ld   hl, tabDStr
	call print_string
	ld   hl, #1102					; X=17, Y=2
	call POSIT
	ld   hl, tabAStr
	call print_string
	; blink table: row 2 is physical row 1 -> base 0x0800 + 1*10 = 0x080A.
	; Tab cells live in bytes 0,1,2 of that row (cols 0-7, 8-15, 16-23).
	xor  a
	ld   bc, 3
	ld   hl, #080A
	call FILVRM						; clear the 3 tab attr bytes
	ld   a, (FILTER)				; active tab byte = FILTER (0=ROM,1=DSK,2=ALL)
	ld   e, a
	ld   d, 0
	ld   hl, #080A
	add  hl, de
	ld   a, #FF
	ld   bc, 1
	call FILVRM						; inverse-highlight the active tab
	; thin baseline under the tabs (row 3), with a gap under the active tab so it
	; "connects" into the list below (folder-tab look)
	ld   a, 3
	call draw_hline					; full thin line under the tabs (no gap; the active
	ret								; tab is already shown highlighted in inverse)

; draw_footer: bottom shortcut bar (row 23) with the partition indicator.
draw_footer:
	ld   hl, #0117					; X=1, Y=23
	call POSIT
	ld   a, (PART_CNT)
	cp   2
	jr   c, .df_keys
	ld   a, 'P'
	call CHPUT
	ld   a, (CUR_PART)
	inc  a
	add  a, '0'
	call CHPUT
	ld   a, '/'
	call CHPUT
	ld   a, (PART_CNT)
	add  a, '0'
	call CHPUT
	ld   a, ' '
	call CHPUT
	call CHPUT
.df_keys:
	ld   hl, footerStr
	call print_string
	ret

; help_screen: overlay listing the keys and how to move around. Any key returns.
help_screen:
	xor  a
	ld   (BROWSING), a				; freeze marquee/clock while help is shown
	call cls_browser
	ld   hl, #0101
	call POSIT
	ld   hl, helpTitleStr
	call print_string
	ld   a, 2
	call draw_hline
	ld   hl, #0204
	call POSIT
	ld   hl, help1Str
	call print_string
	ld   hl, #0206
	call POSIT
	ld   hl, help2Str
	call print_string
	ld   hl, #0207
	call POSIT
	ld   hl, help3Str
	call print_string
	ld   hl, #0208
	call POSIT
	ld   hl, help4Str
	call print_string
	ld   hl, #020A
	call POSIT
	ld   hl, help5Str
	call print_string
	ld   hl, #020B
	call POSIT
	ld   hl, help6Str
	call print_string
	ld   hl, #020C
	call POSIT
	ld   hl, help7Str
	call print_string
	ld   hl, #020D
	call POSIT
	ld   hl, help8Str
	call print_string
	ld   hl, #0217
	call POSIT
	ld   hl, helpEndStr
	call print_string
	call browse_getkey
	ld   a, 1
	ld   (BROWSING), a
	ret

; refresh_list: repaint ONLY the list area (rows 3..21) + the footer partition
; indicator, leaving the header/clock and separator lines untouched (no flash).
refresh_list:
	xor  a							; clear the list rows' blink attrs first, so rows
	ld   bc, 180					; that become empty don't keep a stale inverse bar
	ld   hl, #081E					; 0x0800 + physical row 3 * 10 (18 rows * 10 bytes)
	call FILVRM
	ld   a, 4
.rl_clear:
	push af
	ld   h, 1
	ld   l, a
	call POSIT
	ld   a, #1B
	call CHPUT
	ld   a, 'K'						; ESC K = clear to end of line
	call CHPUT
	pop  af
	inc  a
	cp   22
	jr   c, .rl_clear
	call draw_rows
	call draw_footer
	call draw_counter
	ret

; draw_browser: full repaint (clear + header), then fall into draw_rows.
draw_browser:
	call cls_browser
	; --- header row 1: title + build (left), live clock (right) ---
	ld   hl, #0101					; X=1, Y=1
	call POSIT
	ld   hl, hdrTitleStr			; "MSX Nano  v1.6"
	call print_string
	call draw_tabs					; row 2: filter tabs (active inverse)
	ld   a, 22
	call draw_hline					; thin separator above the footer
	call draw_footer
	call draw_counter				; "sel/total" centred on the bottom line
	; --- file list (rows 3..21) ---
	call draw_rows
	ret
; draw_rows: repaint the visible page in place (no clear, no header) so a scroll
; does not flash. Each row self-clears to end of line (draw_entry emits ESC K).
draw_rows:
	ld   a, (BR_TOP)
	ld   (BR_TMP2), a
	ld   b, VISIBLE
.dbw_loop:
	ld   a, (ENT_COUNT)
	ld   c, a
	ld   a, (BR_TMP2)
	cp   c
	jr   nc, .dbw_done				; idx >= count -> done
	push bc
	ld   a, (BR_TMP2)
	call draw_entry
	pop  bc
	ld   a, (BR_TMP2)
	inc  a
	ld   (BR_TMP2), a
	djnz .dbw_loop
.dbw_done:
	ret

; draw_entry: A = entry index. Print marker + [DIR]/file tag + name at its row.
draw_entry:
	ld   (BR_TMP), a
	; --- full-width inverse highlight on the SELECTED row (File-Hunter "hover") ---
	; A = idx on entry; set this row's 10 TEXT2 blink-attr bytes (VRAM 0x0800+Y*10)
	; to 0xFF when selected (-> R12 inverse colour), 0x00 otherwise.
	ld   hl, BR_SEL
	cp   (hl)
	ld   a, #FF
	jr   z, .de_blsel
	xor  a
.de_blsel:
	ld   (BR_BLINK), a
	ld   a, (BR_TMP)				; physical row (0-based) = 2 + (idx - BR_TOP)
	ld   c, a						; (POSIT row is 1-based Y=3; blink table is 0-based)
	ld   a, (BR_TOP)
	neg
	add  a, c
	add  a, 3
	ld   l, a
	ld   h, 0
	ld   c, l
	ld   b, h
	add  hl, hl
	add  hl, hl
	add  hl, bc
	add  hl, hl						; HL = row*10 (10 attr bytes per 80-col line)
	ld   bc, #0800
	add  hl, bc						; HL = 0x0800 + row*10
	ld   a, (BR_BLINK)
	ld   bc, 10
	call FILVRM						; paint the row's blink attribute
	ld   a, (BR_TMP)
	ld   c, a						; idx
	ld   a, (BR_TOP)
	neg
	add  a, c						; rel = idx - BR_TOP (0..21)
	add  a, 4						; Y = 4 + rel (list rows 4..21)
	ld   l, a
	ld   h, 1						; X = 1
	call POSIT
	ld   a, (BR_TMP)				; selection marker
	ld   hl, BR_SEL
	cp   (hl)
	ld   a, ' '
	jr   nz, .de0
	ld   a, '>'
.de0:
	call CHPUT
	ld   a, ' '
	call CHPUT
	ld   a, (BR_TMP)
	call ent_addr
	ld   (BR_REC), hl
	; --- name (no type tag; HL already = record) ---
	ld   de, NAME_OFF
	add  hl, de
	ld   b, NAME_WIN
	call print_name_win				; the name (record+7), padded to NAME_WIN
	ld   a, #1B						; ESC
	call CHPUT
	ld   a, 'K'						; VT-52 "erase to end of line"
	call CHPUT
	; --- right column (X=69): "[DIR]" for directories, size in KB for files ---
	ld   a, (BR_TMP)
	ld   c, a
	ld   a, (BR_TOP)
	neg
	add  a, c
	add  a, 4
	ld   l, a
	ld   h, 69						; X = 69 (right column)
	call POSIT
	ld   hl, (BR_REC)
	ld   a, (hl)					; type
	or   a
	jr   nz, .de_size				; file -> show KB size
	ld   hl, tagDirStr				; directory -> "[DIR]" in the right column
	call print_string
	ret
.de_size:
	; KB = (size>>16)*64 + (size_byte1 >> 2)
	ld   hl, (BR_REC)
	ld   de, 4
	add  hl, de
	ld   a, (hl)					; size byte 1
	srl  a
	srl  a
	ld   c, a
	ld   hl, (BR_REC)
	ld   de, 5
	add  hl, de
	ld   e, (hl)					; size byte 2
	inc  hl
	ld   d, (hl)					; size byte 3
	ex   de, hl						; hl = size >> 16
	add  hl, hl
	add  hl, hl
	add  hl, hl
	add  hl, hl
	add  hl, hl
	add  hl, hl						; * 64
	ld   e, c
	ld   d, 0
	add  hl, de						; hl = size in KB
	call print_dec16
	ld   a, 'K'
	call CHPUT
	ret

; print_dec16: print HL as unsigned decimal (no leading zeros).
print_dec16:
	ld   b, 0						; b = "a non-zero digit was printed" flag
	ld   de, 10000
	call .pd_dig
	ld   de, 1000
	call .pd_dig
	ld   de, 100
	call .pd_dig
	ld   de, 10
	call .pd_dig
	ld   a, l						; units digit (always shown)
	add  a, '0'
	jp   CHPUT
.pd_dig:
	xor  a
.pd_loop:
	or   a							; clear carry
	sbc  hl, de
	jr   c, .pd_done
	inc  a
	jr   .pd_loop
.pd_done:
	add  hl, de						; restore remainder
	or   a							; digit == 0 ?
	jr   nz, .pd_show
	ld   a, b
	or   a
	ret  z							; leading zero -> suppress
	xor  a							; print a '0'
.pd_show:
	ld   b, 1
	add  a, '0'
	jp   CHPUT

; print_name_win: print exactly B chars from (HL) — the name, then spaces to pad.
; Stops copying at NUL and pads the rest with blanks so the window is fully drawn.
print_name_win:
	ld   a, (hl)
	or   a
	jr   z, .pnw_pad
	push hl
	push bc
	call CHPUT
	pop  bc
	pop  hl
	inc  hl
	djnz print_name_win
	ret
.pnw_pad:
	ld   a, ' '
	push bc
	call CHPUT
	pop  bc
	djnz .pnw_pad
	ret

; strlen_name: HL = string -> A = length (B clobbered, HL advanced).
strlen_name:
	ld   b, 0
.snl:
	ld   a, (hl)
	or   a
	jr   z, .snd
	inc  hl
	inc  b
	jr   .snl
.snd:
	ld   a, b
	ret

; marquee_tick: while in the browser, if the selected entry's name is longer than
; the window, scroll it horizontally (one step every few frames).
marquee_tick:
	ld   a, (BROWSING)
	or   a
	ret  z
	ld   a, (ENT_COUNT)
	or   a
	ret  z
	ld   a, (BR_SEL)
	call ent_addr
	ld   de, NAME_OFF
	add  hl, de						; hl -> name
	call strlen_name				; a = len
	cp   NAME_WIN + 1
	ret  c							; len <= window -> fits, no scroll
	ld   c, a						; c = name length
	ld   a, (BR_SEL)				; selection changed since last tick?
	ld   b, a
	ld   a, (MQ_SEL)
	cp   b
	jr   z, .mt_same
	ld   a, b
	ld   (MQ_SEL), a
	xor  a
	ld   (MQ_OFF), a
	ld   (MQ_TICK), a
.mt_same:
	ld   a, (MQ_TICK)
	inc  a
	cp   5							; advance one column every 5 frames
	jr   c, .mt_savetick
	xor  a
	ld   (MQ_TICK), a
	ld   a, (MQ_OFF)
	inc  a
	ld   b, a						; b = candidate offset
	ld   a, c						; len
	sub  NAME_WIN					; a = max offset (len - window)
	cp   b
	jr   nc, .mt_okoff				; max >= candidate -> keep
	ld   b, 0						; wrap back to the start
.mt_okoff:
	ld   a, b
	ld   (MQ_OFF), a
	jp   draw_sel_name_window		; redraw the selected name window
.mt_savetick:
	ld   (MQ_TICK), a
	ret

; draw_sel_name_window: redraw the selected row's name window at offset MQ_OFF
; (leaves the marker, tag and size columns intact).
draw_sel_name_window:
	ld   a, (BR_SEL)				; screen row = 4 + (BR_SEL - BR_TOP)
	ld   c, a
	ld   a, (BR_TOP)
	neg
	add  a, c
	add  a, 4
	ld   l, a
	ld   h, 3						; X = name column (no type tag now)
	call POSIT
	ld   a, (BR_SEL)
	call ent_addr
	ld   de, NAME_OFF
	add  hl, de
	ld   a, (MQ_OFF)				; hl = name + MQ_OFF
	ld   e, a
	ld   d, 0
	add  hl, de
	ld   b, NAME_WIN
	jp   print_name_win				; padded -> size column survives

; ent_addr: A = index -> HL = ENT_ARRAY + index*ENT_SIZE (44, not a power of 2).
ent_addr:
	ld   hl, ENT_ARRAY
	or   a
	ret  z
	ld   b, a
	ld   de, ENT_SIZE
.ea_mul:
	add  hl, de
	djnz .ea_mul
	ret

; cls_browser: SCREEN 0 + clear the TEXT2 blink colour table (removes the white bar).
cls_browser:
	call INITXT
	call load_font					; INITXT reloads the BIOS font -> restore our glyphs
	ld   a, 0
	ld   bc, 240
	ld   hl, #0800
	call FILVRM
	ret

; draw_counter: show "sel/total" centred over the bottom separator line (row 22).
draw_counter:
	ld   hl, #2316					; X=35, Y=22 (roughly centred on 80 cols)
	call POSIT
	ld   a, ' '
	call CHPUT
	ld   a, (BR_SEL)
	inc  a
	ld   l, a
	ld   h, 0
	call print_dec16
	ld   a, '/'
	call CHPUT
	ld   a, (ENT_COUNT)
	ld   l, a
	ld   h, 0
	call print_dec16
	ld   a, ' '
	call CHPUT
	ret

; ix_is_rom: Z set if the entry's extension (ix+8..10) is "ROM" (upper-case).
ix_is_rom:
	ld   a, (ix+8)
	cp   'R'
	ret  nz
	ld   a, (ix+9)
	cp   'O'
	ret  nz
	ld   a, (ix+10)
	cp   'M'
	ret

; ix_is_dsk: Z set if the entry's extension (ix+8..10) is "DSK" (upper-case).
ix_is_dsk:
	ld   a, (ix+8)
	cp   'D'
	ret  nz
	ld   a, (ix+9)
	cp   'S'
	ret  nz
	ld   a, (ix+10)
	cp   'K'
	ret

; dsk_check_contig: verify the file whose first cluster is FILE_CLUS occupies
; CONSECUTIVE clusters (Nextor disk emulation maps a linear sector range, so the
; image must be unfragmented). Returns CF=0 if contiguous, CF=1 if fragmented.
dsk_check_contig:
	ld   de, (FILE_CLUS)
.dcc_loop:
	ld   a, d
	or   e
	jr   z, .dcc_bad				; cluster 0 -> invalid chain
	push de							; save current cluster
	call fat_next_cluster			; DE = next cluster
	pop  hl							; HL = current cluster
	ld   a, d						; end of chain? (next >= 0xFFF8)
	cp   #FF
	jr   c, .dcc_chk
	ld   a, e
	cp   #F8
	jr   nc, .dcc_ok				; >=0xFFF8 -> last cluster, contiguous so far
.dcc_chk:
	inc  hl							; next must equal current+1
	ld   a, h
	cp   d
	jr   nz, .dcc_bad
	ld   a, l
	cp   e
	jr   nz, .dcc_bad
	jr   .dcc_loop					; DE already = next cluster, continue
.dcc_ok:
	or   a							; CF = 0 (contiguous)
	ret
.dcc_bad:
	scf								; CF = 1 (fragmented / invalid)
	ret

; fmt_name83: format the 11-byte 8.3 name at IX into name83 as "NAME.EXT",0
fmt_name83:
	ld   de, name83
	push ix
	pop  hl							; hl -> name field
	ld   b, 8
.fn_base:
	ld   a, (hl)
	cp   ' '
	jr   z, .fn_ext
	ld   (de), a
	inc  de
	inc  hl
	djnz .fn_base
.fn_ext:
	ld   a, (ix+8)
	cp   ' '
	jr   z, .fn_term				; no extension
	ld   a, '.'
	ld   (de), a
	inc  de
	ld   a, (ix+8)
	ld   (de), a
	inc  de
	ld   a, (ix+9)
	cp   ' '
	jr   z, .fn_term
	ld   (de), a
	inc  de
	ld   a, (ix+10)
	cp   ' '
	jr   z, .fn_term
	ld   (de), a
	inc  de
.fn_term:
	xor  a
	ld   (de), a
	ret

; inc_sd_lba: 32-bit increment of SD_LBA.
inc_sd_lba:
	ld   hl, SD_LBA
	inc  (hl)
	ret  nz
	inc  hl
	inc  (hl)
	ret  nz
	inc  hl
	inc  (hl)
	ret  nz
	inc  hl
	inc  (hl)
	ret

; sd_read_sector: read the 512-byte sector at SD_LBA into SD_BUF.
; The WonderTANG card is NOT auto-initialized: after reset the FPGA state machine
; sits in STANDBY with busy=1 FOREVER until we kick CMD0 via the init bit. The
; menu runs at cartridge INIT, BEFORE Nextor inits the card, so we must init it
; ourselves. Every busy-wait has a timeout so the CPU can NEVER hang (which would
; freeze the whole menu with interrupts off). SD_STATUS: 0=OK 1=init-TO 2=read-TO.
; Maps page 1 to slot 3-2 only for the transfer; menu code in page 2 is untouched.
sd_read_sector:
	di
	xor  a
	ld   (SD_STATUS), a				; assume OK
	ld   a, SD_SLOT_32				; page 1 -> slot 3-2 (SD window)
	ld   hl, #4000
	call ENASLT
	ld   a, #1
	ld   (SDC_ENABLE), a			; enable SDC register block

	ld   a, #80						; SDC_CMD bit7 = init (STANDBY -> CMD0 -> ... -> IDLING)
	ld   (SDC_CMD), a
	call sd_wait_idle				; wait busy->0, CARRY=timeout
	jr   nc, .init_ok
	ld   a, #1
	ld   (SD_STATUS), a				; init timed out
	jr   .sd_done
.init_ok:
	ld   a, (SD_LBA+0)
	ld   (SDC_SADDR+0), a
	ld   a, (SD_LBA+1)
	ld   (SDC_SADDR+1), a
	ld   a, (SD_LBA+2)
	ld   (SDC_SADDR+2), a
	ld   a, (SD_LBA+3)
	ld   (SDC_SADDR+3), a
	ld   a, #1						; SDC_CMD bit0 = read
	ld   (SDC_CMD), a
	ld   b, 0						; settle: let the FSM leave IDLING before polling
.sd_settle:
	djnz .sd_settle
	call sd_wait_idle
	jr   nc, .read_ok
	ld   a, #2
	ld   (SD_STATUS), a				; read timed out
	jr   .sd_done
.read_ok:
	ld   a, (SDC_CTYPE)
	ld   (SD_CTYPE), a
	ld   hl, SDC_SDATA				; copy 512 bytes window -> page-3 RAM
	ld   de, SD_BUF
	ld   bc, 512
	ldir
.sd_done:
	ld   a, SD_SLOT_31				; restore page 1 -> slot 3-1 (menu)
	ld   hl, #4000
	call ENASLT
	ei
	ret

; sd_wait_idle: poll SDC busy (status bit7) until 0. Returns CARRY clear on
; success, CARRY set on timeout (~a few seconds backstop so we never hang).
sd_wait_idle:
	ld   d, 6						; outer count (~2-3 s backstop; card responds in ms)
.swo:
	ld   bc, 0						; 65536 inner iterations
.swi:
	ld   a, (SDC_STATUS)
	and  #80
	ret  z							; busy=0 -> AND cleared carry -> OK
	dec  bc
	ld   a, b
	or   c
	jr   nz, .swi
	dec  d
	jr   nz, .swo
	scf								; timeout
	ret

; sd_write_sector: write the 512-byte SD_BUF to the sector at SD_LBA.
; Mirrors sd_read_sector but fills the SDC_SDATA window first and triggers
; SDC_CMD bit1 = write. SD_STATUS: 0=OK, 1=init timeout, 3=write timeout.
sd_write_sector:
	di
	xor  a
	ld   (SD_STATUS), a
	ld   a, SD_SLOT_32				; page 1 -> slot 3-2 (SD window)
	ld   hl, #4000
	call ENASLT
	ld   a, #1
	ld   (SDC_ENABLE), a
	ld   a, #80						; init the card (same as read path)
	ld   (SDC_CMD), a
	call sd_wait_idle
	jr   nc, .sw_init_ok
	ld   a, #1
	ld   (SD_STATUS), a
	jr   .sw_done
.sw_init_ok:
	ld   hl, SD_BUF					; fill the 512-byte transfer window
	ld   de, SDC_SDATA
	ld   bc, 512
	ldir
	ld   a, (SD_LBA+0)
	ld   (SDC_SADDR+0), a
	ld   a, (SD_LBA+1)
	ld   (SDC_SADDR+1), a
	ld   a, (SD_LBA+2)
	ld   (SDC_SADDR+2), a
	ld   a, (SD_LBA+3)
	ld   (SDC_SADDR+3), a
	ld   a, #2						; SDC_CMD bit1 = write
	ld   (SDC_CMD), a
	ld   b, 0
.sw_settle:
	djnz .sw_settle
	call sd_wait_idle
	jr   nc, .sw_done
	ld   a, #3
	ld   (SD_STATUS), a				; write timed out
.sw_done:
	ld   a, SD_SLOT_31				; restore page 1 -> slot 3-1 (menu)
	ld   hl, #4000
	call ENASLT
	ei
	ret

; find_emufile: search the SD ROOT directory for "NEXTOR  EMU" (8.3). On success
; CF=0 and (FILE_CLUS) = its first cluster; on not-found / SD error CF=1.
find_emufile:
	xor  a
	ld   (CUR_CLUS+0), a
	ld   (CUR_CLUS+1), a
	call set_scan_start				; root dir region (SD_LBA, sec_left=ROOT_SECS)
.fe_sec:
	call sd_read_sector
	ld   a, (SD_STATUS)
	or   a
	jr   nz, .fe_bad
	ld   ix, SD_BUF
	ld   a, 16
	ld   (ent_in_sec), a
.fe_ent:
	ld   a, (ix+0)
	or   a
	jr   z, .fe_bad					; 0x00 = end of directory -> not found
	cp   #E5
	jr   z, .fe_next				; deleted entry
	ld   a, (ix+11)
	and  #0F
	cp   #0F
	jr   z, .fe_next				; LFN sub-entry
	push ix
	pop  hl							; hl -> 11-byte 8.3 name
	ld   de, emuFileName
	ld   b, 11
.fe_cmp:
	ld   a, (de)
	cp   (hl)
	jr   nz, .fe_next
	inc  hl
	inc  de
	djnz .fe_cmp
	; name matches -> require first cluster >= 2. A 0-byte file has cluster 0, and
	; set_scan_start(0) points at the ROOT DIR, so writing the data file there would
	; CORRUPT the root directory. Skip such an entry and keep searching.
	ld   a, (ix+27)
	or   a
	jr   nz, .fe_take
	ld   a, (ix+26)
	cp   2
	jr   c, .fe_next				; cluster 0 or 1 -> unusable
.fe_take:
	ld   a, (ix+26)					; match -> first cluster
	ld   (FILE_CLUS+0), a
	ld   a, (ix+27)
	ld   (FILE_CLUS+1), a
	or   a							; CF=0
	ret
.fe_next:
	ld   de, 32
	add  ix, de
	ld   a, (ent_in_sec)
	dec  a
	ld   (ent_in_sec), a
	jr   nz, .fe_ent
	call inc_sd_lba
	ld   a, (sec_left)
	dec  a
	ld   (sec_left), a
	jr   nz, .fe_sec
.fe_bad:
	scf
	ret

; build_emu_datafile: fill SD_BUF with a Nextor disk-emulation data file describing
; ONE image: header (signature, 1 entry, boot entry #1) + one 8-byte entry pointing
; at the .dsk (DSK_LBA, DSK_SECS). Uses device 0 (= same device as the data file).
build_emu_datafile:
	ld   hl, SD_BUF					; zero the whole 512-byte sector
	ld   de, SD_BUF+1
	ld   bc, 511
	ld   (hl), 0
	ldir
	ld   hl, emuSig					; +0  signature (16 bytes)
	ld   de, SD_BUF
	ld   bc, 16
	ldir
	ld   a, 1
	ld   (SD_BUF+16), a				; +16 entry count = 1
	ld   a, 1
	ld   (SD_BUF+17), a				; +17 1-based index of image to mount at boot
	; +18 work area (2) = 0, +20 reserved (4) = 0  -> already zeroed
	; entry #0 starts at +24
	xor  a
	ld   (SD_BUF+24), a				; entry device = 0 (same device as data file)
	ld   a, 1
	ld   (SD_BUF+25), a				; entry LUN = 1
	ld   hl, (DSK_LBA+0)			; +26 absolute start sector of the .dsk (4 bytes)
	ld   (SD_BUF+26), hl
	ld   hl, (DSK_LBA+2)
	ld   (SD_BUF+28), hl
	ld   hl, (DSK_SECS)				; +30 size in sectors (2 bytes)
	ld   (SD_BUF+30), hl
	ret

; create_emufile: create a 1-cluster file "NEXTOR.EMU" in the current partition's
; root dir to hold the emulation data file. On success CF=0 and (FILE_CLUS) = its
; first cluster. CF=1 on failure (no free cluster / no dir slot / SD error).
; Only ever writes to: one FAT sector (x NUM_FATS) + one root-dir sector. It does
; NOT touch any other file's data.
create_emufile:
	call find_free_cluster			; DE = free cluster, CF=1 if none
	ret  c
	ld   (NEW_CLUS), de
	call mark_cluster_eof			; FAT entry -> 0xFFFF (both copies)
	ret  c
	call write_dir_entry			; root dir entry for NEXTOR.EMU
	ret  c
	ld   hl, (NEW_CLUS)
	ld   (FILE_CLUS), hl
	or   a							; CF=0 success
	ret

; find_free_cluster: scan FAT copy 1 for a free entry (0x0000). Returns DE = cluster,
; CF=0; or CF=1 if none / SD error. Clusters 0 and 1 are reserved (skipped).
find_free_cluster:
	ld   hl, (FAT_LBA+0)
	ld   (SD_LBA+0), hl
	ld   hl, (FAT_LBA+2)
	ld   (SD_LBA+2), hl
	ld   hl, 0
	ld   (FFC_BASE), hl
	ld   hl, (FAT_SZ)
	ld   (FFC_LEFT), hl
.ffc_sec:
	ld   hl, (FFC_LEFT)
	ld   a, h
	or   l
	jr   z, .ffc_none
	call sd_read_sector
	ld   a, (SD_STATUS)
	or   a
	jr   nz, .ffc_none
	ld   ix, SD_BUF
	ld   c, 0
	ld   hl, (FFC_BASE)				; first FAT sector (base 0) holds clusters 0,1 -> skip
	ld   a, h
	or   l
	jr   nz, .ffc_ent
	ld   ix, SD_BUF+4
	ld   c, 2
.ffc_ent:
	ld   a, (ix+0)
	or   (ix+1)
	jr   z, .ffc_found
	inc  ix
	inc  ix
	inc  c
	jr   nz, .ffc_ent				; 256 entries/sector (c wraps to 0)
	ld   hl, (FFC_BASE)				; next sector: base += 256
	ld   de, 256
	add  hl, de
	ld   (FFC_BASE), hl
	ld   hl, (FFC_LEFT)
	dec  hl
	ld   (FFC_LEFT), hl
	call inc_sd_lba
	jr   .ffc_sec
.ffc_found:
	ld   hl, (FFC_BASE)
	ld   e, c
	ld   d, 0
	add  hl, de
	ex   de, hl						; DE = cluster
	or   a							; CF=0
	ret
.ffc_none:
	scf
	ret

; mark_cluster_eof: set the FAT entry for NEW_CLUS to 0xFFFF in FAT copy 1 and, if
; NUM_FATS>=2, copy 2. CF=1 on SD error.
mark_cluster_eof:
	ld   hl, (NEW_CLUS)
	ld   a, h
	ld   (MCE_SEC), a				; FAT sector offset = cluster >> 8
	ld   l, l						; (entry byte offset = (cluster&255)*2)
	ld   h, 0
	ld   a, (NEW_CLUS+0)
	ld   l, a
	add  hl, hl						; *2
	ld   (MCE_OFF), hl
	ld   hl, (FAT_LBA+0)			; SD_LBA = FAT_LBA + sector offset
	ld   a, (MCE_SEC)
	ld   e, a
	ld   d, 0
	add  hl, de
	ld   (SD_LBA+0), hl
	ld   hl, (FAT_LBA+2)
	ld   de, 0
	adc  hl, de
	ld   (SD_LBA+2), hl
	call sd_read_sector
	ld   a, (SD_STATUS)
	or   a
	jr   nz, .mce_err
	ld   hl, SD_BUF
	ld   de, (MCE_OFF)
	add  hl, de
	ld   (hl), #FF
	inc  hl
	ld   (hl), #FF
	call sd_write_sector			; FAT copy 1
	ld   a, (SD_STATUS)
	or   a
	jr   nz, .mce_err
	ld   a, (NUM_FATS)
	cp   2
	jr   c, .mce_ok					; only one FAT -> done
	ld   hl, (SD_LBA+0)				; FAT copy 2 sector = same + FAT_SZ
	ld   de, (FAT_SZ)
	add  hl, de
	ld   (SD_LBA+0), hl
	ld   hl, (SD_LBA+2)
	ld   de, 0
	adc  hl, de
	ld   (SD_LBA+2), hl
	call sd_write_sector			; same buffer (FAT copies are identical)
	ld   a, (SD_STATUS)
	or   a
	jr   nz, .mce_err
.mce_ok:
	or   a
	ret
.mce_err:
	scf
	ret

; write_dir_entry: find a free slot in the current partition's root dir and write a
; 32-byte entry for NEXTOR.EMU (first cluster = NEW_CLUS, size = 512). CF=1 on error.
write_dir_entry:
	ld   hl, (ROOT_LBA+0)
	ld   (SD_LBA+0), hl
	ld   hl, (ROOT_LBA+2)
	ld   (SD_LBA+2), hl
	ld   a, (ROOT_SECS)
	ld   (WDE_LEFT), a
.wde_sec:
	ld   a, (WDE_LEFT)
	or   a
	jr   z, .wde_err
	call sd_read_sector
	ld   a, (SD_STATUS)
	or   a
	jr   nz, .wde_err
	ld   ix, SD_BUF
	ld   b, 16
.wde_ent:
	ld   a, (ix+0)
	or   a
	jr   z, .wde_found				; 0x00 = free (end of dir)
	cp   #E5
	jr   z, .wde_found				; deleted -> reuse
	ld   de, 32
	add  ix, de
	djnz .wde_ent
	call inc_sd_lba
	ld   a, (WDE_LEFT)
	dec  a
	ld   (WDE_LEFT), a
	jr   .wde_sec
.wde_found:
	push ix							; zero the 32-byte slot
	pop  hl
	ld   d, h
	ld   e, l
	inc  de
	ld   (hl), 0
	ld   bc, 31
	ldir
	push ix							; name "NEXTOR  EMU"
	pop  hl
	ld   de, emuFileName
	ld   b, 11
.wde_name:
	ld   a, (de)
	ld   (hl), a
	inc  hl
	inc  de
	djnz .wde_name
	ld   (ix+11), #20				; attr = archive
	ld   hl, (NEW_CLUS)
	ld   (ix+26), l					; first cluster low
	ld   (ix+27), h					; first cluster high
	ld   (ix+28), #00				; size = 512 bytes (0x00000200)
	ld   (ix+29), #02
	ld   (ix+30), #00
	ld   (ix+31), #00
	call sd_write_sector
	ld   a, (SD_STATUS)
	or   a
	jr   nz, .wde_err
	or   a							; CF=0
	ret
.wde_err:
	scf
	ret

; print A as two upper-case hex digits via CHPUT
print_hex_a:
	push af
	rrca
	rrca
	rrca
	rrca
	call .ph_nib
	pop  af
.ph_nib:
	and  #0f
	add  a, #90
	daa
	adc  a, #40
	daa
	jp   CHPUT

; print HL as four upper-case hex digits (high byte first)
print_hex_hl:
	ld   a, h
	call print_hex_a
	ld   a, l
	jp   print_hex_a

; --- Option 3: Configuracion WiFi (PLACEHOLDER, M3) -------------------------
; main_action_wifi: open the ESP8266 WiFi config menu that already lives in the
; ESP ROM (slot 0-2, esp8266e.rom). Its INIT (which ran at boot, before our menu,
; since slot 0 < slot 3) shows that menu when F1 is held: 'jp z,#4202'. We reach
; the same entry on demand: map page 1 to slot 0-2 and CALL #4202; the WiFi menu
; runs there (page 0 BIOS + page 3 RAM + UART I/O all stay valid) and returns on
; exit, then we restore page 1 and go back to the SD browser.
ESP_SLOT	equ	#88				; slot 0-2 (expanded: pri 0, sec 2)
main_action_wifi:
	di
	ld   a, ESP_SLOT				; page 1 -> ESP8266 WiFi ROM
	ld   hl, #4000
	call ENASLT
	ei
	call #4202						; ESP WiFi config menu (returns on exit)
	di
	ld   a, #87						; page 1 -> our menu ROM (slot 3-1)
	ld   hl, #4000
	call ENASLT
	ei
	jp   main_menu_restart			; back to the SD browser (home)

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
	ld   a, '>'						; draw the selection marker
	jr   main_selection_common
; Clears the selection marker on the current main-menu row.
main_clear_selection:
	ld   a, ' '
main_selection_common:
	ld   (var_selColor), a			; marker char ('>' or ' ')
	ld   a, (var_mainSel)
	add  a, a						; sel*2
	add  a, 6						; Y = 6 + sel*2 (options are at rows 6,8,10,12)
	ld   l, a						; L = Y
	ld   h, 26						; H = X (column 26, just left of the option text)
	call POSIT
	ld   a, (var_selColor)
	call CHPUT						; print '>' (or ' ' to clear)
	ret

; Shared screen initialization: SCREEN 0 / 80 columns + blink mode ON, with a
; DETERMINISTIC palette so the menu looks EXACTLY the same on cold boot and on
; every redraw (placeholder return, etc.). On cold boot the menu used to inherit
; whatever text colours / palette the FM logo left behind; on a redraw those had
; changed -> "different blue". We now force the colours ourselves every time:
;   - FORCLR/BAKCLR/BDRCLR BIOS vars -> INITXT programs VDP r7 from them
;   - palette entry 4  = blue  (background / normal text bg, blink fg)
;   - palette entry 15 = white (normal text fg, blink bg / header box)
; so the result is byte-for-byte identical regardless of prior screen state.
init_screen:
	; Fixed text colours: foreground 15 (white), background/border 4 (blue)
	ld   a, 15
	ld   (FORCLR), a				; foreground = white (palette index 15)
	ld   a, 4
	ld   (BAKCLR), a				; background = blue  (palette index 4)
	ld   (BDRCLR), a				; border     = blue
	ld   a, 80
	ld   (LINL40), a
	call INITXT						; SCREEN 0 / 80 col; programs VDP r7 from FORCLR/BAKCLR
	; Blink mode ON: r12 = blink colours (fg 4 / bg 15) -> blue-on-white inverse
	ld   bc, #4f0c
	call WRTVDP
	ld   bc, #100d					; r13 = blink rate (steady)
	call WRTVDP
	; Force palette entries 4 and 15 to fixed RGB so the blue/white never drift.
	call set_menu_palette
	ret

; Reprograms VDP palette entries 4 (blue) and 15 (white) deterministically.
; V9938/V9958 palette write: select entry in r16, then write 2 bytes to port
; 0x9A: byte1 = (R<<4)|B, byte2 = G  (each component 0..7).
set_menu_palette:
	di
	; --- entry 4 = blue (R=1, G=1, B=7) ---
	ld   a, 4
	out  (#99), a					; low byte = palette index 4
	ld   a, 16 | #80				; select VDP register 16 (palette pointer)
	out  (#99), a
	ld   a, #17						; byte1 = (R<<4)|B = (1<<4)|7 = 0x17
	out  (#9A), a
	ld   a, #01						; byte2 = G = 1
	out  (#9A), a
	; --- entry 15 = white (R=7, G=7, B=7) ---
	ld   a, 15
	out  (#99), a
	ld   a, 16 | #80
	out  (#99), a
	ld   a, #77						; byte1 = (7<<4)|7 = 0x77
	out  (#9A), a
	ld   a, #07						; byte2 = G = 7
	out  (#9A), a
	ei
	ret

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
sdTestStr:
	.db "SD READ TEST - sector 0",0
sdStatusStr:
	.db "Status (00=OK 01=initTO 02=readTO): ",0
sdTypeStr:
	.db "Card type (1=v1 2=v2 3=SDHC): ",0
tagDirStr:
	.db "[DIR] ",0
tagRomStr:
	.db "[ROM] ",0
tagDskStr:
	.db "[DSK] ",0
hdrTitleStr:
	.db "MSX Nano  v1.6",0
tabRStr:
	.db "[R]OM",0
tabDStr:
	.db "[D]SK",0
tabAStr:
	.db "[A]LL",0
footerStr:
	.db "R/D/A=Filtro  ESC=Boot  S=Set  W=WiFi  TAB=Part  H=Ayuda",0
helpTitleStr:
	.db "MSXnano - AYUDA",0
help1Str:
	.db "Arriba/Abajo          : mover (Izq/Der = pagina)",0
help2Str:
	.db "RETURN / Boton A      : abrir carpeta o lanzar ROM",0
help3Str:
	.db "BACKSPACE / Boton B   : carpeta anterior",0
help4Str:
	.db "TAB                   : cambiar de particion",0
help5Str:
	.db "ESC                   : arrancar el sistema (MSX-DOS)",0
help6Str:
	.db "S                     : Ajustes (configuracion goauld)",0
help7Str:
	.db "W                     : configuracion WiFi (ESP)",0
help8Str:
	.db "H                     : esta ayuda",0
helpEndStr:
	.db "Pulsa una tecla para volver...",0
romInfoStr:
	.db "ROM seleccionada:",0
romClusStr:
	.db "Tamano: ",0
romSpcStr:
	.db "  Mapper: ",0
mapPlainStr:
	.db "Plain (lineal)",0
mapKonStr:
	.db "Konami",0
mapSccStr:
	.db "Konami-SCC",0
mapA8Str:
	.db "ASCII8",0
mapA16Str:
	.db "ASCII16",0
mapUnkStr:
	.db "? (desconocido)",0
loadingStr:
	.db "Cargando ROM en megaram...",0
launch2Str:
	.db "RETURN=LANZAR JUEGO   ESC=volver",0
dskInfoStr:
	.db "Disco seleccionado:",0
dskMountStr:
	.db "Montando disco (Nextor) y arrancando...",0
dskFragStr:
	.db "DSK fragmentado: copialo de nuevo. Pulsa tecla",0
dskAskStr:
	.db "RETURN=montar y lanzar   ESC=volver",0
dskNoEmuStr:
	.db "Falta NEXTOR.EMU (>=512B) en la raiz. Tecla",0
dskWrErrStr:
	.db "Error escribiendo en la SD. Pulsa una tecla",0
; Nextor disk-emulation "one-time" signature (16-byte field: 15 chars + NUL)
emuSig:
	.db "NEXTOR_EMU_DATA",0
; 8.3 name of the helper file that holds the emulation data file (root dir)
emuFileName:
	.db "NEXTOR  EMU"
readingStr:
	.db "Leyendo SD...",0
noSdStr:
	.db "No se detecta la tarjeta SD.",0
noSdStr2:
	.db "RETURN=Boot MSX   S=Settings   W=WiFi",0
brSelStr:
	.db "Sel: ",0
partTypeStr:
	.db "Ptype=",0
partLbaStr:
	.db " pLBA=",0
bpbBpsStr:
	.db "BPS=",0
bpbSpcStr:
	.db " SPC=",0
bpbRsvStr:
	.db " RSV=",0
bpbNfatStr:
	.db "NFAT=",0
bpbRentStr:
	.db " REnt=",0
bpbFs16Str:
	.db " FS16=",0
bpbFs32Str:
	.db "FS32=",0
bpbRclusStr:
	.db " RtClus=",0

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

