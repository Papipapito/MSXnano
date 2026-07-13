#ifndef  KEYMAPS_H
#define KEYMAPS_H

/*
 * USB HID usage code -> MSX matrix cell, for the MSX Goa'uld USB keyboard.
 *
 * Cell byte format (matches the FROZEN FPGA contract exactly):
 *     cell = 0x80 | (bit << 4) | row      row in 0..10, bit in 0..7
 * The MAKE/BREAK opcodes (0x90 / 0xA0) are sent as a SEPARATE leading byte
 * before the cell, so a cell value that happens to equal 0xA0 (e.g. digit '2')
 * is never confused with the BREAK opcode -- they are positional on the wire.
 *
 * A value of 0 means "not mapped" (ignored). For bit7==0 values (0x00..0x03)
 * the firmware treats the entry as a COMMAND opcode (scanline/reset/OSD) and
 * sends it raw; the FPGA ignores commands in v1 but it is harmless.
 *
 * Coordinates are the verified MSXnano translator
 * (MSXnano/fpga/src/usb/usb_keyboard_msx.vhd), layout International/US.
 *
 * NOTE: the SHIFT/CTRL/GRAPH/CODE modifiers (row 6) are NOT in this table.
 * They are driven from the HID modifier byte by the derived-modifier logic in
 * usbin.c (MOD_* cells), not from a key usage code. CapsLock (0x39) IS a
 * regular key (row6/bit3) and stays here.
 */

// `static` so this table can be safely included by more than one translation
// unit (usbin.c uses it; main.c pulls the header in transitively for the kb_*
// prototypes). Each TU that does not reference it has the unused copy elided
// by the optimizer, and there is no multiple-definition at link time.
static const uint8_t keycode_to_goauld[256] = {
    // ---- Letters (a-z), rows 2..5 ----
    [0x04] = 0x80 | (6 << 4) | 2, // 'a' -> row2 bit6  (0xE2)
    [0x05] = 0x80 | (7 << 4) | 2, // 'b' -> row2 bit7  (0xF2)
    [0x06] = 0x80 | (0 << 4) | 3, // 'c' -> row3 bit0  (0x83)
    [0x07] = 0x80 | (1 << 4) | 3, // 'd' -> row3 bit1  (0x93)
    [0x08] = 0x80 | (2 << 4) | 3, // 'e' -> row3 bit2  (0xA3)
    [0x09] = 0x80 | (3 << 4) | 3, // 'f' -> row3 bit3  (0xB3)
    [0x0A] = 0x80 | (4 << 4) | 3, // 'g' -> row3 bit4  (0xC3)
    [0x0B] = 0x80 | (5 << 4) | 3, // 'h' -> row3 bit5  (0xD3)
    [0x0C] = 0x80 | (6 << 4) | 3, // 'i' -> row3 bit6  (0xE3)
    [0x0D] = 0x80 | (7 << 4) | 3, // 'j' -> row3 bit7  (0xF3)
    [0x0E] = 0x80 | (0 << 4) | 4, // 'k' -> row4 bit0  (0x84)
    [0x0F] = 0x80 | (1 << 4) | 4, // 'l' -> row4 bit1  (0x94)
    [0x10] = 0x80 | (2 << 4) | 4, // 'm' -> row4 bit2  (0xA4)
    [0x11] = 0x80 | (3 << 4) | 4, // 'n' -> row4 bit3  (0xB4)
    [0x12] = 0x80 | (4 << 4) | 4, // 'o' -> row4 bit4  (0xC4)
    [0x13] = 0x80 | (5 << 4) | 4, // 'p' -> row4 bit5  (0xD4)
    [0x14] = 0x80 | (6 << 4) | 4, // 'q' -> row4 bit6  (0xE4)
    [0x15] = 0x80 | (7 << 4) | 4, // 'r' -> row4 bit7  (0xF4)
    [0x16] = 0x80 | (0 << 4) | 5, // 's' -> row5 bit0  (0x85)
    [0x17] = 0x80 | (1 << 4) | 5, // 't' -> row5 bit1  (0x95)
    [0x18] = 0x80 | (2 << 4) | 5, // 'u' -> row5 bit2  (0xA5)
    [0x19] = 0x80 | (3 << 4) | 5, // 'v' -> row5 bit3  (0xB5)
    [0x1A] = 0x80 | (4 << 4) | 5, // 'w' -> row5 bit4  (0xC5)
    [0x1B] = 0x80 | (5 << 4) | 5, // 'x' -> row5 bit5  (0xD5)
    [0x1C] = 0x80 | (6 << 4) | 5, // 'y' -> row5 bit6  (0xE5)
    [0x1D] = 0x80 | (7 << 4) | 5, // 'z' -> row5 bit7  (0xF5)

    // ---- Top-row digits, rows 0 and 1 ----
    [0x1E] = 0x80 | (1 << 4) | 0, // '1' -> row0 bit1  (0x90)
    [0x1F] = 0x80 | (2 << 4) | 0, // '2' -> row0 bit2  (0xA0)
    [0x20] = 0x80 | (3 << 4) | 0, // '3' -> row0 bit3  (0xB0)
    [0x21] = 0x80 | (4 << 4) | 0, // '4' -> row0 bit4  (0xC0)
    [0x22] = 0x80 | (5 << 4) | 0, // '5' -> row0 bit5  (0xD0)
    [0x23] = 0x80 | (6 << 4) | 0, // '6' -> row0 bit6  (0xE0)
    [0x24] = 0x80 | (7 << 4) | 0, // '7' -> row0 bit7  (0xF0)
    [0x25] = 0x80 | (0 << 4) | 1, // '8' -> row1 bit0  (0x81)
    [0x26] = 0x80 | (1 << 4) | 1, // '9' -> row1 bit1  (0x91)
    [0x27] = 0x80 | (0 << 4) | 0, // '0' -> row0 bit0  (0x80)

    // ---- Characters on row 1 ----
    [0x2D] = 0x80 | (2 << 4) | 1, // '-' '_'   -> row1 bit2  (0xA1)
    [0x2E] = 0x80 | (3 << 4) | 1, // '=' '+'   -> row1 bit3  (0xB1)
    [0x31] = 0x80 | (4 << 4) | 1, // '\' '|' (US backslash, HID 0x31; VHDL WHEN 49) -> row1 bit4 (0xC1)
    [0x2F] = 0x80 | (5 << 4) | 1, // '[' '{'   -> row1 bit5  (0xD1)
    [0x30] = 0x80 | (6 << 4) | 1, // ']' '}'   -> row1 bit6  (0xE1)
    [0x33] = 0x80 | (7 << 4) | 1, // ';' ':'   -> row1 bit7  (0xF1)

    // ---- Row 2: punctuation / dead key ----
    [0x34] = 0x80 | (0 << 4) | 2, // '\'' '"'  -> row2 bit0  (0x82)
    [0x35] = 0x80 | (1 << 4) | 2, // '`' '~'   -> row2 bit1  (0x92)
    [0x36] = 0x80 | (2 << 4) | 2, // ',' '<'   -> row2 bit2  (0xA2)
    [0x37] = 0x80 | (3 << 4) | 2, // '.' '>'   -> row2 bit3  (0xB2)
    [0x38] = 0x80 | (4 << 4) | 2, // '/' '?'   -> row2 bit4  (0xC2)
    [0x32] = 0x80 | (5 << 4) | 2, // Non-US '#'/'~' (HID 0x32; VHDL WHEN 50, DEAD/accent) -> row2 bit5 (0xD2)

    // ---- CapsLock as MSX CAPS (row 6, bit3) ----
    [0x39] = 0x80 | (3 << 4) | 6, // CapsLock -> row6 bit3  (0xB6)

    // ---- Space / Enter / Esc / Tab / BS / Stop / Select ----
    [0x2C] = 0x80 | (0 << 4) | 8, // Space  -> row8 bit0  (0x88)
    [0x28] = 0x80 | (7 << 4) | 7, // Enter  -> row7 bit7  (0xF7)
    [0x29] = 0x80 | (2 << 4) | 7, // Esc    -> row7 bit2  (0xA7)
    [0x2B] = 0x80 | (3 << 4) | 7, // Tab    -> row7 bit3  (0xB7)
    [0x2A] = 0x80 | (5 << 4) | 7, // Backspace -> row7 bit5 (0xD7)
    [0x47] = 0x80 | (4 << 4) | 7, // ScrollLock -> MSX STOP   row7 bit4 (0xC7)
    [0x4D] = 0x80 | (6 << 4) | 7, // End        -> MSX SELECT row7 bit6 (0xE7)

    // ---- Arrows + Home / Ins / Del (row 8) ----
    [0x4F] = 0x80 | (7 << 4) | 8, // RightArrow -> row8 bit7 (0xF8)
    [0x51] = 0x80 | (6 << 4) | 8, // DownArrow  -> row8 bit6 (0xE8)
    [0x52] = 0x80 | (5 << 4) | 8, // UpArrow    -> row8 bit5 (0xD8)
    [0x50] = 0x80 | (4 << 4) | 8, // LeftArrow  -> row8 bit4 (0xC8)
    [0x4C] = 0x80 | (3 << 4) | 8, // Delete     -> row8 bit3 (0xB8)
    [0x49] = 0x80 | (2 << 4) | 8, // Insert     -> row8 bit2 (0xA8)
    [0x4A] = 0x80 | (1 << 4) | 8, // Home       -> row8 bit1 (0x98)

    // ---- Numeric keypad (rows 9 and 10) ----
    [0x5C] = 0x80 | (7 << 4) | 9, // KP 4  -> row9 bit7 (0xF9)
    [0x5B] = 0x80 | (6 << 4) | 9, // KP 3  -> row9 bit6 (0xE9)
    [0x5A] = 0x80 | (5 << 4) | 9, // KP 2  -> row9 bit5 (0xD9)
    [0x59] = 0x80 | (4 << 4) | 9, // KP 1  -> row9 bit4 (0xC9)
    [0x62] = 0x80 | (3 << 4) | 9, // KP 0  -> row9 bit3 (0xB9)
    [0x54] = 0x80 | (2 << 4) | 9, // KP /  -> row9 bit2 (0xA9)
    [0x57] = 0x80 | (1 << 4) | 9, // KP +  -> row9 bit1 (0x99)
    [0x55] = 0x80 | (0 << 4) | 9, // KP *  -> row9 bit0 (0x89)

    [0x63] = 0x80 | (7 << 4) | 10, // KP .  -> row10 bit7 (0xFA)
    [0x56] = 0x80 | (5 << 4) | 10, // KP -  -> row10 bit5 (0xDA)
    [0x61] = 0x80 | (4 << 4) | 10, // KP 9  -> row10 bit4 (0xCA)
    [0x60] = 0x80 | (3 << 4) | 10, // KP 8  -> row10 bit3 (0xBA)
    [0x5F] = 0x80 | (2 << 4) | 10, // KP 7  -> row10 bit2 (0xAA)
    [0x5E] = 0x80 | (1 << 4) | 10, // KP 6  -> row10 bit1 (0x9A)
    [0x5D] = 0x80 | (0 << 4) | 10, // KP 5  -> row10 bit0 (0x8A)

    // ---- Function keys F1..F5 -> MSX matrix cells (VHDL rows 6/7) ----
    [0x3A] = 0x80 | (5 << 4) | 6, // F1 -> row6 bit5 (0xD6)
    [0x3B] = 0x80 | (6 << 4) | 6, // F2 -> row6 bit6 (0xE6)
    [0x3C] = 0x80 | (7 << 4) | 6, // F3 -> row6 bit7 (0xF6)
    [0x3D] = 0x80 | (0 << 4) | 7, // F4 -> row7 bit0 (0x87)
    [0x3E] = 0x80 | (1 << 4) | 7, // F5 -> row7 bit1 (0x97)

    // ---- F6, F7 -> MSX STOP / GRAPH matrix cells (preserves original
    //       firmware behaviour; the FPGA has these cells via ScrollLock/End
    //       and the GRAPH modifier, so driving them from F6/F7 is harmless). ----
    [0x3F] = 0x80 | (4 << 4) | 7, // F6 -> row7 bit4 (0xC7) MSX STOP
    [0x40] = 0x80 | (2 << 4) | 6, // F7 -> row6 bit2 (0xA6) MSX GRAPH

    // ---- F8..F12 -> COMMAND opcodes (bit7==0), sent raw. FPGA ignores them
    //       in v1 but the wire stays well-defined (OSD was dropped). ----
    [0x41] = 0x01, // F8  -> command 0x01 (scanline)
    [0x42] = 0x03, // F9  -> command 0x03 (OSD)
    [0x43] = 0x03, // F10 -> command 0x03 (OSD)
    [0x44] = 0x01, // F11 -> command 0x01 (scanline)
    [0x45] = 0x02, // F12 -> command 0x02 (reset)
};

#endif
