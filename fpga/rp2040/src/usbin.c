/*
 * The MIT License (MIT)
 *
 * Copyright (c) 2024 No0ne (https://github.com/No0ne)
 *           (c) 2024 Bernd Strobel
 *           (c) 2024 pdaxrom (https://github.com/pdaxrom)
 * Modified by Chandler Klüser for MSX Goa'uld Friend, 2024
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 *
 */
#include "usbin.h"
#include "pico/time.h"   // time_us_64() for the status-LED keypress flash
#include "hardware/pio.h"
#include "hardware/gpio.h"
#include "uart_tx.pio.h"  // PIO UART TX (FPGA link on GP15, a non-HW-UART pin)
#include <string.h>
#include "xinput_host.h"  // vendored Ryzee119 XInput host driver (MIT) -> same joystick path

// ---------------------------------------------------------------------------
// MSX Goa'uld keyboard link -- event-driven make/break model.
//
// We mirror the USB key state onto the FPGA matrix as MAKE/BREAK events and
// resync the full shadow matrix periodically. The FPGA owns the matrix and
// the MSX BIOS does autorepeat, so we never block and never auto-release.
//
// Wire protocol (FROZEN -- must match the FPGA RX side exactly):
//   PIO UART @ 115200 8N1, GP15 = TX -> FPGA pin 75 (RX).
//   cell byte         = 0x80 | (bit<<4) | row     row 0..10, bit 0..7
//   0x90 <cell>       = MAKE
//   0xA0 <cell>       = BREAK
//   commands (bit7=0) = 0x01 scanline, 0x02 reset, 0x03 OSD (sent raw)
//   full resync       = 0xFE, vmatrix[0..10] (active-low), 0xFF
// ---------------------------------------------------------------------------

// FPGA link = PIO UART TX on GP15. The RP2040 HW UART0/1 TX only reach
// GP0/12/16/28 or GP4/8/20/24; the carrier redesign needs GP15, so we drive it
// from PIO (pio1 SM0 -- pio0 SM0/SM1 are the on-board + case WS2812 strips).
#define KB_UART_PIN    15
#define KB_PIO         pio1
#define KB_SM          0u
#define OP_MAKE        0x90
#define OP_BREAK       0xA0
#define OP_VERSION     0xC0   // 0xC0 <FW_VERSION> = version-guard announce (additive; old FPGAs ignore it)
#define RESYNC_START   0xFE
#define RESYNC_END     0xFF

// Generic USB HID gamepad/joystick -> MSX joystick port.
//   0xB0 <port> <joybyte>   port: 0 = MSX port 1, 1 = MSX port 2
//   joybyte ACTIVE-HIGH (1 = pressed): bit0=Right bit1=Left bit2=Down
//   bit3=Up bit4=A(TrigA/fire1) bit5=B(TrigB/fire2) bits6-7=0.
//   (The FPGA inverts to MSX active-low.)
#define OP_JOY         0xB0
#define JOY_RIGHT      0x01
#define JOY_LEFT       0x02
#define JOY_DOWN       0x04
#define JOY_UP         0x08
#define JOY_A          0x10
#define JOY_B          0x20

// Autofire / turbo: while an autofire button is held, the matching fire bit is
// square-waved press/release at AF_HALF_PERIOD_US to simulate rapid tapping.
// 50 ms half-period = 10 Hz (50% duty) => >= 2 PSG frames asserted AND released
// even on a 50 Hz PAL MSX, so every shot is scanned. Only the existing JOY_A /
// JOY_B bits are toggled, so the 0xB0 wire protocol stays frozen.
#define AF_HALF_PERIOD_US 50000ull  // 50 ms -> 10 Hz autofire (keep >= ~40 ms for PAL)
#define AF_HID_BTN_A      2         // 3rd HID button bit -> autofire trigger A (JOY_A)
#define AF_HID_BTN_B      3         // 4th HID button bit -> autofire trigger B (JOY_B)

// Derived-modifier bit positions (logical, OR of L/R HID bits).
#define DRV_SHIFT      0x01
#define DRV_CTRL       0x02
#define DRV_GRAPH      0x04
#define DRV_CODE       0x08

// Matrix cells for the four MSX modifiers, all on row 6.
// SHIFT=row6 bit0 (0x86), CTRL=row6 bit1 (0x96), GRAPH=row6 bit2 (0xA6),
// CODE=row6 bit4 (0xC6).
#define MOD_CELL_SHIFT 0x86
#define MOD_CELL_CTRL  0x96
#define MOD_CELL_GRAPH 0xA6
#define MOD_CELL_CODE  0xC6

// Active-low shadow of the 11 matrix rows. bit=1 -> released, bit=0 -> pressed.
static uint8_t vmatrix[11];
// Previous non-modifier key set (HID usage codes), as last seen in a report.
static uint8_t prev_keys[16];
// Previous derived (logical) modifier state: {SHIFT,CTRL,GRAPH,CODE}.
static uint8_t prev_derived = 0;
volatile uint64_t g_last_key_us = 0;  // updated on each MAKE; read by the status LED in main.c
volatile uint64_t g_last_kbd_us = 0;  // keyboard-only MAKE timestamp (case-strip "typing" LED)
volatile uint8_t  g_kbd_mounted = 0;  // nonzero while a USB keyboard is mounted (case-strip)
volatile uint8_t  g_joy_out     = 0;  // live transmitted joystick byte, port 0 (case-strip panel)

// Non-blocking TX ring buffer (drained in main() by kb_tx_pump()).
static volatile uint8_t txbuf[256];
static volatile uint8_t tx_head = 0;
static volatile uint8_t tx_tail = 0;

static inline void tx_push(uint8_t b) {
    uint8_t next = (uint8_t)(tx_head + 1);
    if(next == tx_tail) {
        // Ring full: drop the oldest byte to keep the stream moving. A dropped
        // event self-heals on the next 250 ms full-matrix resync.
        tx_tail++;
    }
    txbuf[tx_head] = b;
    tx_head = next;
}

// Drain the TX ring into the PIO UART's TX FIFO without blocking. From main loop.
void kb_tx_pump(void) {
    while(tx_tail != tx_head && !pio_sm_is_tx_fifo_full(KB_PIO, KB_SM)) {
        pio_sm_put(KB_PIO, KB_SM, (uint32_t)txbuf[tx_tail++]);
    }
}

// Emit a MAKE/BREAK event for a matrix cell and update the shadow matrix.
static void emit_event(uint8_t op, uint8_t cell) {
    if(op == OP_MAKE) { g_last_key_us = time_us_64(); g_last_kbd_us = g_last_key_us; }  // status LED + case-strip typing
    uint8_t row = cell & 0x0F;
    uint8_t bit = (cell >> 4) & 0x07;
    if(row <= 10) {
        if(op == OP_MAKE) vmatrix[row] &= (uint8_t)~(1u << bit); // pressed -> 0
        else              vmatrix[row] |=  (uint8_t)(1u << bit);  // released -> 1
    }
    tx_push(op);
    tx_push(cell);
}

// Emit a raw command opcode (bit7==0). FPGA ignores in v1, harmless.
static void emit_command(uint8_t cmd) {
    tx_push(cmd);
}

// Push a full-matrix resync frame onto the TX ring.
void kb_send_resync(void) {
    // Version-guard announce rides on every resync so the FPGA always knows the
    // firmware version (self-healing, like the matrix itself).
    tx_push(OP_VERSION);
    tx_push(FW_VERSION);
    tx_push(RESYNC_START);
    for(uint8_t r = 0; r < 11; r++) tx_push(vmatrix[r]);
    tx_push(RESYNC_END);
}

// ---------------------------------------------------------------------------
// Joystick link. Active-high shadow of the two MSX joystick ports; we send the
// 3-byte 0xB0 frame only when a port's byte changes (non-blocking, via the same
// TX ring the keyboard uses), and re-emit both ports on every 250 ms resync.
// ---------------------------------------------------------------------------
static uint8_t joy_state[2] = {0, 0};   // active-high shadow, indexed by port

// ---- Autofire / turbo intent (port-indexed; only port 0 has a pad today) ----
// The report callbacks latch two layers; the main-loop tick (joy_autofire_tick)
// is the SOLE emitter and composes: out = joy_base | (af_phase ? af_arm : 0).
static uint8_t  joy_base[2] = {0, 0};   // real held byte: directions + manual fire1/fire2
static uint8_t  af_arm[2]   = {0, 0};   // fire bits (JOY_A/JOY_B) currently armed for autofire
static bool     af_phase    = false;    // shared square-wave phase (keeps both ports in sync)
static uint64_t af_next_us  = 0;        // time_us_64() deadline of the next phase flip

// Send-on-change core. bump_led=true re-arms the white keypress/activity flash;
// the autofire tick passes false so its 10 Hz edges keep the status LED on the
// yellow "gamepad connected" colour instead of stealing it to white.
static void joy_emit(uint8_t port, uint8_t b, bool bump_led) {
    if(port > 1 || b == joy_state[port]) return;
    joy_state[port] = b;
    if(port == 0) g_joy_out = b;                 // live joy byte for the case-strip panel (A/B/dirs)
    if(bump_led) g_last_key_us = time_us_64();   // flash status LED on real joystick activity
    tx_push(OP_JOY);
    tx_push(port);
    tx_push(b);
}

// Send-on-change: update the shadow and emit 0xB0 <port> <byte> when it changes.
static void joy_set_state(uint8_t port, uint8_t b) {
    joy_emit(port, b, true);
}

// Re-emit both joystick ports (self-heals any dropped 0xB0 byte). Mirrors
// kb_send_resync(); called from the 250 ms resync block in main.c.
void joy_send_resync(void) {
    for(uint8_t p = 0; p < 2; p++) {
        tx_push(OP_JOY);
        tx_push(p);
        tx_push(joy_state[p]);
    }
}

// Autofire square-wave tick. MUST run from the main super-loop (NOT the
// event-driven report callbacks): a held-but-motionless pad sends no new USB
// reports, so a callback-driven autofire would freeze the bit. Composes each
// port as joy_base | (af_phase ? af_arm : 0) and emits via send-on-change with
// NO LED bump, so autofire keeps the status LED yellow ("gamepad connected").
void joy_autofire_tick(uint64_t now_us) {
    if(af_next_us == 0) af_next_us = now_us + AF_HALF_PERIOD_US;   // lazy init
    if((int64_t)(now_us - af_next_us) >= 0) {
        af_phase   = !af_phase;
        af_next_us = now_us + AF_HALF_PERIOD_US;   // = now+HALF (not +=): no catch-up bursts
    }
    for(uint8_t p = 0; p < 2; p++) {
        uint8_t out = joy_base[p];
        if(af_phase) out |= af_arm[p];             // assert armed fire bits this phase
        joy_emit(p, out, false);                   // no LED bump: autofire stays yellow
    }
}

// Initialize the dedicated keyboard UART link: uart0 @ 115200 8N1, GPIO0=TX.
// This is the ONLY owner of uart0 -- stdio must not be routed here (see main.c).
void kb_uart_init(void) {
    memset(vmatrix, 0xFF, sizeof(vmatrix)); // all keys released at boot
    // PIO UART TX on GP15 -> FPGA pin 75 (RX), 115200 8N1. pio1 SM0.
    uint off = pio_add_program(KB_PIO, &uart_tx_program);
    uart_tx_program_init(KB_PIO, KB_SM, off, KB_UART_PIN, 115200);
}

typedef struct {
  const hid_report_item_t *x;
  const hid_report_item_t *y;
  const hid_report_item_t *z;
  const hid_report_item_t *lb;
  const hid_report_item_t *mb;
  const hid_report_item_t *rb;
  const hid_report_item_t *bw;
  const hid_report_item_t *fw;
} ms_items_t;

struct {
  u8 report_count;
  hid_report_info_t report_info[MAX_REPORT];
} hid_info[CFG_TUH_HID];

// hid_info[] is a shared pool keyed by (dev_addr, instance). TinyUSB numbers
// `instance` PER DEVICE (0-based), so a USB keyboard and a USB joystick are two
// SEPARATE devices that BOTH enumerate as instance 0. The original code indexed
// hid_info[instance] directly, so the second device clobbered the first's parsed
// report descriptor in hid_info[0] -- exactly why keyboard+joystick together
// broke (each then read the other's descriptor and did nothing). We map every
// (dev_addr, instance) to its own slot instead. dev_addr 0 = free slot (real USB
// devices are addr >= 1). NOTE: XInput pads never hit this table (separate
// driver), which is why an Xbox pad + keyboard used to coexist fine.
static struct { u8 dev_addr; u8 instance; } hid_slot_key[CFG_TUH_HID];

// Find the hid_info[] slot for (dev_addr, instance). With alloc=true, claims a
// free slot if none exists yet. Returns 0..CFG_TUH_HID-1, or 0xFF if full/absent.
static u8 hid_slot_get(u8 dev_addr, u8 instance, bool alloc) {
  for(u8 i = 0; i < CFG_TUH_HID; i++)
    if(hid_slot_key[i].dev_addr == dev_addr && hid_slot_key[i].instance == instance &&
       hid_slot_key[i].dev_addr != 0)
      return i;
  if(!alloc) return 0xFF;
  for(u8 i = 0; i < CFG_TUH_HID; i++)
    if(hid_slot_key[i].dev_addr == 0) {
      hid_slot_key[i].dev_addr = dev_addr;
      hid_slot_key[i].instance = instance;
      return i;
    }
  return 0xFF;
}

// Release the slot held by (dev_addr, instance) on unmount so it can be reused.
static void hid_slot_free(u8 dev_addr, u8 instance) {
  for(u8 i = 0; i < CFG_TUH_HID; i++)
    if(hid_slot_key[i].dev_addr == dev_addr && hid_slot_key[i].instance == instance) {
      hid_slot_key[i].dev_addr = 0;
      hid_slot_key[i].instance = 0;
      return;
    }
}

ms_items_t ms_items;

struct {
  u8 dev_addr;
  u8 instance;
} keyboards[8];

// Generic HID gamepads/joysticks. Mirrors keyboards[]: a registered (addr,inst)
// is one whose parsed top-level collection is Generic Desktop / Game Pad (0x05)
// or Joystick (0x04). Used to route reports to gamepad_report_receive().
struct {
  u8 dev_addr;
  u8 instance;
} gamepads[8];

// Status-LED aid: nonzero while at least one USB gamepad is registered.
volatile uint8_t g_joy_mounted = 0;

// True if a parsed top-level collection is a generic-desktop gamepad/joystick.
static inline bool is_gamepad_usage(const hid_report_info_t *info) {
  return info != NULL &&
         info->usage_page == HID_USAGE_PAGE_DESKTOP &&
         (info->usage == HID_USAGE_DESKTOP_GAMEPAD ||
          info->usage == HID_USAGE_DESKTOP_JOYSTICK);
}

// True if instance `inst` of `dev_addr` is registered as a gamepad.
static bool is_registered_gamepad(u8 dev_addr, u8 instance) {
  for(u8 i = 0; i < 8; i++) {
    if(gamepads[i].dev_addr == dev_addr && gamepads[i].instance == instance &&
       (gamepads[i].dev_addr != 0 || gamepads[i].instance != 0)) {
      return true;
    }
  }
  return false;
}

bool hid_parse_find_bit_item_by_page(hid_report_info_t* report_info_arr, u8 type, u16 page, u8 bit, const hid_report_item_t **item) {
  for(u8 i = 0; i < report_info_arr->num_items; i++) {
	if(report_info_arr->item[i].item_type == type && report_info_arr->item[i].attributes.usage.page == page) {
	  if(item) {
		if(i+bit < report_info_arr->num_items && report_info_arr->item[i+bit].item_type == type && report_info_arr->item[i+bit].attributes.usage.page == page) {
		  *item = &report_info_arr->item[i + bit];
		} else {
		  return false;
		}
	  }
	  return true;
	}
  }
  return false;
}

bool hid_parse_find_item_by_usage(hid_report_info_t* report_info_arr, u8 type, u16 usage, const hid_report_item_t **item) {
  for(u8 i = 0; i < report_info_arr->num_items; i++) {
	if(report_info_arr->item[i].item_type == type && report_info_arr->item[i].attributes.usage.usage == usage) {
	  if(item) {
		*item = &report_info_arr->item[i];
	  }
	  return true;
	}
  }
  return false;
}

bool hid_parse_get_item_value(const hid_report_item_t *item, const u8 *report, u8 len, s32 *value) {
  (void)len;
  if(item == NULL || report == NULL) return false;
  u8 boffs = item->bit_offset & 0x07;
  u8 pos = 8 - boffs;
  u8 offs  = item->bit_offset >> 3;
  u32 mask = ~(0xffffffff << item->bit_size);
  s32 val = report[offs++] >> boffs;
  while(item->bit_size > pos) {
	val |= (report[offs++] << pos);
	pos += 8;
  }
  val &= mask;
  if(item->attributes.logical.min < 0) {
	if(val & (1 << (item->bit_size - 1))) {
	  val |= (0xffffffff << item->bit_size);
	}
  }
  *value = val;
  return true;
}

s32 to_signed_value(const hid_report_item_t *item, const u8 *report, u16 len) {
  s32 value = 0;
  if(hid_parse_get_item_value(item, report, len, &value)) {
	s32 midval = ((item->attributes.logical.max - item->attributes.logical.min) >> 1) + 1;
	value -= midval;
	value <<= (16 - item->bit_size);
  }
  if(value > 32767) value = 32767;
  if(value < -32767) value = -32767;
  return value;
}

s8 to_signed_value8(const hid_report_item_t *item, const u8 *report, u16 len) {
  s32 value = 0;
  if(hid_parse_get_item_value(item, report, len, &value)) {
	value = (value > 127) ? 127 : (value < -127) ? -127 : value;
  }
  return value;
}

bool to_bit_value(const hid_report_item_t *item, const u8 *report, u16 len) {
  s32 value = 0;
  hid_parse_get_item_value(item, report, len, &value);
  return value ? true : false;
}

u8 hid_parse_report_descriptor(hid_report_info_t* report_info_arr, u8 arr_count, u8 const* desc_report, u16 desc_len) {
  union TU_ATTR_PACKED {
	u8 byte;
	struct TU_ATTR_PACKED {
	  u8 size: 2;
	  u8 type: 2;
	  u8 tag: 4;
	};
  } header;

  tu_memclr(report_info_arr, arr_count * sizeof(tuh_hid_report_info_t));

  u8 report_num = 0;
  hid_report_info_t* info = report_info_arr;

  u16 ri_global_usage_page = 0;
  s32 ri_global_logical_min = 0;
  s32 ri_global_logical_max = 0;
  s32 ri_global_physical_min = 0;
  s32 ri_global_physical_max = 0;
  u8 ri_report_count = 0;
  u8 ri_report_size = 0;
  u8 ri_report_usage_count = 0;

  u8 ri_collection_depth = 0;

  while(desc_len && report_num < arr_count) {
	header.byte = *desc_report++;
	desc_len--;

	u8 const tag  = header.tag;
	u8 const type = header.type;
	u8 const size = header.size;

	u32 data;
	u32 sdata;
	switch(size) {
	  case 1: data = desc_report[0]; sdata = ((data & 0x80) ? 0xffffff00 : 0 ) | data; break;
	  case 2: data = (desc_report[1] << 8) | desc_report[0]; sdata = ((data & 0x8000) ? 0xffff0000 : 0 ) | data;  break;
	  case 3: data = (desc_report[3] << 24) | (desc_report[2] << 16) | (desc_report[1] << 8) | desc_report[0]; sdata = data; break;
	  default: data = 0; sdata = 0;
	}

	switch(type) {
	  case RI_TYPE_MAIN:
		switch(tag) {
		  case RI_MAIN_INPUT:
		  case RI_MAIN_OUTPUT:
		  case RI_MAIN_FEATURE: ;  /* empty stmt: a label can't be followed directly by a declaration in C */
			u16 offset = (info->num_items == 0) ? 0 : (info->item[info->num_items - 1].bit_offset + info->item[info->num_items - 1].bit_size);
			for(u8 i = 0; i < ri_report_count; i++) {
			  if(info->num_items + i < MAX_REPORT_ITEMS) {
				info->item[info->num_items + i].bit_offset = offset;
				info->item[info->num_items + i].bit_size = ri_report_size;
				info->item[info->num_items + i].bit_count = ri_report_count;
				info->item[info->num_items + i].item_type = tag;
				info->item[info->num_items + i].attributes.logical.min = ri_global_logical_min;
				info->item[info->num_items + i].attributes.logical.max = ri_global_logical_max;
				info->item[info->num_items + i].attributes.physical.min = ri_global_physical_min;
				info->item[info->num_items + i].attributes.physical.max = ri_global_physical_max;
				info->item[info->num_items + i].attributes.usage.page = ri_global_usage_page;
				if(ri_report_usage_count != ri_report_count && ri_report_usage_count > 0) {
				  if(i >= ri_report_usage_count) {
					info->item[info->num_items + i].attributes.usage = info->item[info->num_items + i - 1].attributes.usage;
				  }
				}
			  }
			  offset += ri_report_size;
			}
			info->num_items += ri_report_count;
			ri_report_usage_count = 0;
		  break;

		  case RI_MAIN_COLLECTION:
			ri_collection_depth++;
		  break;

		  case RI_MAIN_COLLECTION_END:
			ri_collection_depth--;
			if(ri_collection_depth == 0) {
			  info++;
			  report_num++;
			}
		  break;
		}
	  break;

	  case RI_TYPE_GLOBAL:
		switch(tag) {
		  case RI_GLOBAL_USAGE_PAGE:
			if(ri_collection_depth == 0) {
			  info->usage_page = data;
			}
			ri_global_usage_page = data;
		  break;

		  case RI_GLOBAL_LOGICAL_MIN:
			ri_global_logical_min = sdata;
		  break;
		  case RI_GLOBAL_LOGICAL_MAX:
			ri_global_logical_max = sdata;
		  break;
		  case RI_GLOBAL_PHYSICAL_MIN:
			ri_global_physical_min = sdata;
		  break;
		  case RI_GLOBAL_PHYSICAL_MAX:
			ri_global_physical_max = sdata;
		  break;
		  case RI_GLOBAL_REPORT_ID:
			info->report_id = data;
		  break;
		  case RI_GLOBAL_REPORT_SIZE:
			ri_report_size = data;
		  break;
		  case RI_GLOBAL_REPORT_COUNT:
			ri_report_count = data;
		  break;
		}
	  break;

	  case RI_TYPE_LOCAL:
		if(tag == RI_LOCAL_USAGE) {
		  if(ri_collection_depth == 0) {
			info->usage = data;
		  } else {
			if(ri_report_usage_count < MAX_REPORT_ITEMS) {
			  info->item[info->num_items + ri_report_usage_count].attributes.usage.usage = data;
			  ri_report_usage_count++;
			}
		  }
		}
	  break;
	}

	desc_report += size;
	desc_len -= size;
  }

  return report_num;
}

u8 hid_parse_keyboard_modifiers(hid_report_info_t* report_info_arr, const u8 *report, u8 len) {
	u8 modifiers = 0;
	u8 bit = 0;
	for(u8 i = 0; i < report_info_arr->num_items; i++) {
		if(report_info_arr->item[i].item_type == RI_MAIN_INPUT &&
		report_info_arr->item[i].attributes.usage.page == HID_USAGE_PAGE_KEYBOARD &&
		report_info_arr->item[i].bit_size == 1 &&
		report_info_arr->item[i].bit_count == 8) {
			modifiers |= to_bit_value(&report_info_arr->item[i], report, len) << bit;
			bit++;
			if(bit == 8) break;
		}
	}
	return modifiers;
}

bool hid_parse_keyboard_is_nkro(hid_report_info_t* report_info_arr) {
	for(u8 i = 0; i < report_info_arr->num_items; i++) {
		if(report_info_arr->item[i].item_type == RI_MAIN_INPUT &&
		report_info_arr->item[i].attributes.usage.page == HID_USAGE_PAGE_KEYBOARD &&
		report_info_arr->item[i].bit_size == 1 &&
		report_info_arr->item[i].bit_count >= 32) {
		return true;
		}
	}
	return false;
}

// Pack the raw HID modifier byte into the 4 logical MSX modifiers, ORing the
// left/right HID bits so that releasing one Shift while the other is still
// held does NOT drop the MSX SHIFT.
//   HID bits: 0 LCtrl,1 LShift,2 LAlt,3 LGUI,4 RCtrl,5 RShift,6 RAlt,7 RGUI
//   SHIFT = bits 1|5 (0x22)   CTRL = bits 0|4 (0x11)
//   GRAPH = bit  2   (0x04)   CODE = bit  6   (0x40)
static inline uint8_t derive_modifiers(uint8_t mods) {
    uint8_t d = 0;
    if(mods & 0x22) d |= DRV_SHIFT;
    if(mods & 0x11) d |= DRV_CTRL;
    if(mods & 0x04) d |= DRV_GRAPH;
    if(mods & 0x40) d |= DRV_CODE;
    return d;
}

// Map a USB HID usage code to an MSX matrix cell.
// US / International layout (keycode_to_goauld), matching the international BIOS.
static inline uint8_t map_cell(uint8_t k) {
    return keycode_to_goauld[k];
}

// Event-driven make/break translation. Called on every HID keyboard report.
// `report` is exactly 6 bytes of HID usage codes (0 = empty slot) for boot and
// 6KRO reports; NKRO is expanded to the same flat form by the dispatcher.
void kb_report_receive(uint8_t modifiers, uint8_t const* report, u16 len) {
	if(len > sizeof(prev_keys)) len = sizeof(prev_keys);

	// ---- 1. Modifiers: diff the 4 DERIVED logical bits, not raw HID bits ----
	uint8_t derived = derive_modifiers(modifiers);
	if(derived != prev_derived) {
		uint8_t changed = derived ^ prev_derived;
		if(changed & DRV_SHIFT)
			emit_event((derived & DRV_SHIFT) ? OP_MAKE : OP_BREAK, MOD_CELL_SHIFT);
		if(changed & DRV_CTRL)
			emit_event((derived & DRV_CTRL)  ? OP_MAKE : OP_BREAK, MOD_CELL_CTRL);
		if(changed & DRV_GRAPH)
			emit_event((derived & DRV_GRAPH) ? OP_MAKE : OP_BREAK, MOD_CELL_GRAPH);
		if(changed & DRV_CODE)
			emit_event((derived & DRV_CODE)  ? OP_MAKE : OP_BREAK, MOD_CELL_CODE);
		prev_derived = derived;
	}
	kb_modifiers = modifiers;

	// ---- 2. BREAKs: keys present in prev_keys but absent from report ----
	for(uint8_t i = 0; i < sizeof(prev_keys); i++) {
		uint8_t k = prev_keys[i];
		if(k == 0) continue;
		bool still_down = false;
		for(uint8_t j = 0; j < len; j++) {
			if(report[j] == k) { still_down = true; break; }
		}
		if(!still_down) {
			uint8_t cell = map_cell(k);
			if(cell & 0x80) emit_event(OP_BREAK, cell); // commands have no break
		}
	}

	// ---- 3. MAKEs: keys present in report but absent from prev_keys ----
	for(uint8_t i = 0; i < len; i++) {
		uint8_t k = report[i];
		if(k == 0) continue;
		bool was_down = false;
		for(uint8_t j = 0; j < sizeof(prev_keys); j++) {
			if(prev_keys[j] == k) { was_down = true; break; }
		}
		if(!was_down) {
			uint8_t cell = map_cell(k);
			if(cell & 0x80) emit_event(OP_MAKE, cell);   // matrix key
			else if(cell)   emit_command(cell);          // command opcode (F6..F12)
		}
	}

	// ---- 4. Snapshot the new key set ----
	memset(prev_keys, 0, sizeof(prev_keys));
	memcpy(prev_keys, report, len);
}

// Digital threshold on the SCALED axis value. to_signed_value() centers the
// axis at 0 and left-justifies it into a signed 16-bit range (+-32767),
// independent of the axis' native bit width, so a fixed scaled threshold ==
// "half of the logical range" for any resolution. ~16384 = half of full scale.
#define JOY_AXIS_T 16384

// Translate one generic-HID gamepad/joystick report into the active-high MSX
// joy byte and push it (send-on-change) to MSX joystick port 0 (MSX port 1).
//
// Robustness / assumptions:
//  * Usage-based parsing only (works across pad layouts, no per-VID quirks).
//  * X axis = Generic Desktop / X (0x30), Y = Y (0x31); thresholded to digital.
//  * Hat switch (0x39): 0=N,1=NE,2=E,3=SE,4=S,5=SW,6=W,7=NW, >=8 centered;
//    decoded to U/D/L/R and OR'd with the axis result so pads exposing a hat,
//    analog stick, or both all work.
//  * Buttons = Button page (0x09): button 1 -> A (fire1), button 2 -> B (fire2).
//  * `report`/`len` here have already had any report-ID byte stripped by the
//    caller, and `rpt_info` is the matching parsed collection.
//  * If the pad exposes neither X/Y nor a hat we still process buttons; a pad
//    with no usable controls simply yields byte 0 (idle).
void gamepad_report_receive(uint8_t dev_addr, uint8_t instance, uint8_t const* report, u16 len) {
  u8 slot = hid_slot_get(dev_addr, instance, false);
  if(slot == 0xFF) return;
  hid_report_info_t* rpt_info_arr = hid_info[slot].report_info;
  hid_report_info_t* rpt_info = NULL;

  // Resolve the collection for this report exactly like the keyboard path:
  // single report w/ id 0 -> first collection; otherwise match the report-id.
  if(hid_info[slot].report_count == 1 && rpt_info_arr[0].report_id == 0) {
    rpt_info = &rpt_info_arr[0];
  } else {
    uint8_t const rpt_id = report[0];
    for(uint8_t i = 0; i < hid_info[slot].report_count; i++) {
      if(rpt_id == rpt_info_arr[i].report_id) { rpt_info = &rpt_info_arr[i]; break; }
    }
    report++;
    len--;
  }
  if(!rpt_info || !is_gamepad_usage(rpt_info)) return;

  uint8_t byte = 0;
  const hid_report_item_t *item;

  // ---- Analog X/Y axes -> digital directions (thresholded) ----
  if(hid_parse_find_item_by_usage(rpt_info, RI_MAIN_INPUT, HID_USAGE_DESKTOP_X, &item)) {
    s32 x = to_signed_value(item, report, len);
    if(x < -JOY_AXIS_T) byte |= JOY_LEFT;
    if(x >  JOY_AXIS_T) byte |= JOY_RIGHT;
  }
  if(hid_parse_find_item_by_usage(rpt_info, RI_MAIN_INPUT, HID_USAGE_DESKTOP_Y, &item)) {
    s32 y = to_signed_value(item, report, len);
    if(y < -JOY_AXIS_T) byte |= JOY_UP;     // HID +Y is down; up = small/negative
    if(y >  JOY_AXIS_T) byte |= JOY_DOWN;
  }

  // ---- Hat switch -> directions, OR'd with the axis result ----
  if(hid_parse_find_item_by_usage(rpt_info, RI_MAIN_INPUT, HID_USAGE_DESKTOP_HAT_SWITCH, &item)) {
    s32 hat = 0;
    if(hid_parse_get_item_value(item, report, len, &hat)) {
      // Normalize to 0..7 using the logical minimum (some pads report 1..8).
      hat -= item->attributes.logical.min;
      switch(hat) {
        case 0: byte |= JOY_UP;               break; // N
        case 1: byte |= JOY_UP   | JOY_RIGHT; break; // NE
        case 2: byte |= JOY_RIGHT;            break; // E
        case 3: byte |= JOY_DOWN | JOY_RIGHT; break; // SE
        case 4: byte |= JOY_DOWN;             break; // S
        case 5: byte |= JOY_DOWN | JOY_LEFT;  break; // SW
        case 6: byte |= JOY_LEFT;             break; // W
        case 7: byte |= JOY_UP   | JOY_LEFT;  break; // NW
        default: break;                              // >=8 (or out of range) = centered
      }
    }
  }

  // ---- Buttons (Button page): btn1 -> A, btn2 -> B (manual fire) ----
  if(hid_parse_find_bit_item_by_page(rpt_info, RI_MAIN_INPUT, HID_USAGE_PAGE_BUTTON, 0, &item)) {
    if(to_bit_value(item, report, len)) byte |= JOY_A;
  }
  if(hid_parse_find_bit_item_by_page(rpt_info, RI_MAIN_INPUT, HID_USAGE_PAGE_BUTTON, 1, &item)) {
    if(to_bit_value(item, report, len)) byte |= JOY_B;
  }

  // ---- btn3 -> autofire A, btn4 -> autofire B (toggled by joy_autofire_tick) ----
  // Pads with <3/<4 buttons: the lookup returns false, `item` is left untouched,
  // to_bit_value is not called, and that trigger simply stays disarmed.
  uint8_t af = 0;
  if(hid_parse_find_bit_item_by_page(rpt_info, RI_MAIN_INPUT, HID_USAGE_PAGE_BUTTON, AF_HID_BTN_A, &item)) {
    if(to_bit_value(item, report, len)) af |= JOY_A;
  }
  if(hid_parse_find_bit_item_by_page(rpt_info, RI_MAIN_INPUT, HID_USAGE_PAGE_BUTTON, AF_HID_BTN_B, &item)) {
    if(to_bit_value(item, report, len)) af |= JOY_B;
  }

  (void)dev_addr;
  // Latch intent for the autofire tick (the sole emitter). Flash the LED here on
  // real activity so the white flash survives; the tick's autofire edges do not.
  if(byte != joy_base[0] || af != af_arm[0]) g_last_key_us = time_us_64();
  joy_base[0] = byte;   // base layer: directions + manual fire
  af_arm[0]   = af;     // arm layer: which fires autofire (re-derived each report)
}

void tuh_kb_set_leds(uint8_t leds) {
	for(uint8_t i = 0; i < 8; i++) {
		if(keyboards[i].dev_addr != 0) {
		kb_leds = leds;
		tuh_hid_set_report(keyboards[i].dev_addr, keyboards[i].instance, 0, HID_REPORT_TYPE_OUTPUT, &kb_leds, sizeof(kb_leds));
		}
	}
}

// ===========================================================================
// USB XInput (Xbox-style) gamepads -> SAME MSX joystick path as the HID pads.
// Driver: Ryzee119/tusb_xinput (MIT), registered below via the app-driver hook.
// Covers Xbox 360 / One / Series and most 2.4GHz "XInput-mode" dongles, which
// the built-in HID host cannot claim. The HID keyboard + HID gamepad paths are
// completely untouched.
// ===========================================================================

// Register the vendored XInput class driver ALONGSIDE TinyUSB's built-in host
// drivers (HID keyboard/gamepad keep working; this is additive).
usbh_class_driver_t const* usbh_app_driver_get_cb(uint8_t* driver_count) {
    *driver_count = 1;
    return &usbh_xinput_driver;
}

void tuh_xinput_mount_cb(uint8_t dev_addr, uint8_t instance, const xinputh_interface_t* xinput_itf) {
    (void)xinput_itf;
    // NOTE (RP2040 native host + hub): do NOT send LED/rumble here. Those are
    // BLOCKING interrupt-OUT transfers; behind a hub they arm a second hub-split
    // interrupt endpoint that the RP2040's single SIE cannot poll concurrently
    // with the keyboard's interrupt-IN -> the pad's first report never arrives
    // (not detected) AND the wedged OUT poisons the shared SIE, killing the
    // keyboard too. Keeping the pad interrupt-IN-only (like a keyboard) matches
    // the one topology the native host handles behind a hub. Rumble/LED are
    // cosmetic and unused by the MSX joystick path, so we simply drop them.
    //   tuh_xinput_set_led(dev_addr, instance, 0, true);   // removed (OUT xfer)
    //   tuh_xinput_set_led(dev_addr, instance, 1, true);   // removed (OUT xfer)
    //   tuh_xinput_set_rumble(dev_addr, instance, 0, 0, true); // removed (OUT xfer)
    g_joy_mounted = 1;                              // status LED -> yellow
    joy_set_state(0, 0);                            // clean baseline (no dir/fire)
    joy_base[0] = 0; af_arm[0] = 0;                 // clear autofire intent on connect
    tuh_xinput_receive_report(dev_addr, instance);  // start polling (interrupt-IN only)
}

void tuh_xinput_umount_cb(uint8_t dev_addr, uint8_t instance) {
    (void)dev_addr; (void)instance;
    g_joy_mounted = 0;
    joy_set_state(0, 0);                            // release direction/fire
    joy_base[0] = 0; af_arm[0] = 0;                 // clear autofire intent on disconnect
}

void tuh_xinput_report_received_cb(uint8_t dev_addr, uint8_t instance,
                                   xinputh_interface_t const* xid_itf, uint16_t len) {
    (void)len;
    const xinput_gamepad_t* p = &xid_itf->pad;
    if (xid_itf->connected && xid_itf->new_pad_data) {
        uint8_t b = 0;
        // D-pad
        if (p->wButtons & XINPUT_GAMEPAD_DPAD_RIGHT) b |= JOY_RIGHT;
        if (p->wButtons & XINPUT_GAMEPAD_DPAD_LEFT)  b |= JOY_LEFT;
        if (p->wButtons & XINPUT_GAMEPAD_DPAD_DOWN)  b |= JOY_DOWN;
        if (p->wButtons & XINPUT_GAMEPAD_DPAD_UP)    b |= JOY_UP;
        // Left stick: XInput Y is +up; MSX "up" is active bit3. Half-scale deadzone.
        if (p->sThumbLX >  JOY_AXIS_T) b |= JOY_RIGHT;
        if (p->sThumbLX < -JOY_AXIS_T) b |= JOY_LEFT;
        if (p->sThumbLY < -JOY_AXIS_T) b |= JOY_DOWN;
        if (p->sThumbLY >  JOY_AXIS_T) b |= JOY_UP;
        // Buttons: A -> trigger A (fire 1), B -> trigger B (fire 2)
        if (p->wButtons & XINPUT_GAMEPAD_A) b |= JOY_A;
        if (p->wButtons & XINPUT_GAMEPAD_B) b |= JOY_B;
        // Spare face buttons X/Y arm autofire for trigger A/B (bumpers left free).
        uint8_t af = 0;
        if (p->wButtons & XINPUT_GAMEPAD_X) af |= JOY_A;
        if (p->wButtons & XINPUT_GAMEPAD_Y) af |= JOY_B;
        // Latch intent for the autofire tick (sole emitter); flash LED on real activity.
        if (b != joy_base[0] || af != af_arm[0]) g_last_key_us = time_us_64();
        joy_base[0] = b;
        af_arm[0]   = af;
    }
    tuh_xinput_receive_report(dev_addr, instance);  // re-arm polling
}

void tuh_hid_mount_cb(uint8_t dev_addr, uint8_t instance, uint8_t const* desc_report, u16 desc_len) {
	// This happens if report descriptor length > CFG_TUH_ENUMERATION_BUFSIZE.
	// Consider increasing #define CFG_TUH_ENUMERATION_BUFSIZE 256 in tusb_config.h
	if(desc_report == NULL && desc_len == 0) {
		// Report descriptor didn't fit CFG_TUH_ENUMERATION_BUFSIZE (now 2048); skip it.
		return;
	}

	hid_interface_protocol_enum_t hid_if_proto = tuh_hid_interface_protocol(dev_addr, instance);
	u16 vid, pid;
	tuh_vid_pid_get(dev_addr, &vid, &pid);

	char* hidprotostr = "none";
	if(hid_if_proto == HID_ITF_PROTOCOL_KEYBOARD) hidprotostr = "keyboard";
	if(hid_if_proto == HID_ITF_PROTOCOL_MOUSE) hidprotostr = "mouse";
	// Claim this (dev_addr, instance)'s own hid_info[] slot so a second device
	// (e.g. joystick alongside the keyboard) can't clobber the first's descriptor.
	u8 slot = hid_slot_get(dev_addr, instance, true);
	if(slot == 0xFF) return;   // hid_info pool full (>16 interfaces): ignore extra
	hid_info[slot].report_count = hid_parse_report_descriptor(hid_info[slot].report_info, MAX_REPORT, desc_report, desc_len);
	if(!tuh_hid_receive_report(dev_addr, instance)) {
	} else {
		if(hid_if_proto == HID_ITF_PROTOCOL_KEYBOARD) {
			for(uint8_t i = 0; i < 8; i++) {
				if(keyboards[i].dev_addr == 0 && keyboards[i].instance == 0) {
					keyboards[i].dev_addr = dev_addr;
					keyboards[i].instance = instance;
					break;
				}
			}
			g_kbd_mounted = 1;   // case-strip: a USB keyboard is connected
			// Establish a clean baseline on the FPGA: nothing pressed yet.
			memset(vmatrix, 0xFF, sizeof(vmatrix));
			memset(prev_keys, 0, sizeof(prev_keys));
			prev_derived = 0;
			kb_send_resync();
		} else {
			// Generic HID: detect a gamepad/joystick by its parsed top-level
			// collection (Generic Desktop / Game Pad 0x05 or Joystick 0x04).
			// Such devices enumerate with interface protocol NONE, so we key off
			// the report descriptor already parsed into hid_info[slot].
			bool is_pad = false;
			for(uint8_t r = 0; r < hid_info[slot].report_count; r++) {
				if(is_gamepad_usage(&hid_info[slot].report_info[r])) { is_pad = true; break; }
			}
			if(is_pad) {
				for(uint8_t i = 0; i < 8; i++) {
					if(gamepads[i].dev_addr == 0 && gamepads[i].instance == 0) {
						gamepads[i].dev_addr = dev_addr;
						gamepads[i].instance = instance;
						break;
					}
				}
				joy_set_state(0, 0); joy_base[0] = 0; af_arm[0] = 0; // clean baseline; clear autofire
					g_joy_mounted = 1;   // status LED: a USB gamepad is connected
			}
		}
		isMounted = 1; board_led_write(1);
	}
}

void tuh_hid_umount_cb(uint8_t dev_addr, uint8_t instance) {
	isMounted = 0; board_led_write(0);
	hid_slot_free(dev_addr, instance);   // release this device's hid_info[] slot

	for(uint8_t i = 0; i < 8; i++) {
		if(keyboards[i].dev_addr == dev_addr && keyboards[i].instance == instance) {
			keyboards[i].dev_addr = 0;
			keyboards[i].instance = 0;
			break;
		}
	}
	g_kbd_mounted = 0;
	for(uint8_t i = 0; i < 8; i++) if(keyboards[i].dev_addr) { g_kbd_mounted = 1; break; }
	// Keyboard gone: release everything on the FPGA so no key stays stuck.
	memset(vmatrix, 0xFF, sizeof(vmatrix));
	memset(prev_keys, 0, sizeof(prev_keys));
	prev_derived = 0;
	kb_send_resync();

	// If a gamepad unmounted, drop its slot and release the joystick so no
	// direction/fire stays stuck on the MSX side.
	for(uint8_t i = 0; i < 8; i++) {
		if(gamepads[i].dev_addr == dev_addr && gamepads[i].instance == instance &&
		   (gamepads[i].dev_addr != 0 || gamepads[i].instance != 0)) {
			gamepads[i].dev_addr = 0;
			gamepads[i].instance = 0;
			joy_set_state(0, 0);
			joy_base[0] = 0; af_arm[0] = 0; // clear autofire intent on disconnect
			g_joy_mounted = 0;
			break;
		}
	}
}

void tuh_hid_report_received_cb(uint8_t dev_addr, uint8_t instance, uint8_t const* report, u16 len) {
	// Generic HID gamepad/joystick: handle and re-arm here, leaving the keyboard
	// path below completely untouched. gamepad_report_receive() does its own
	// report-ID resolution on the raw report (same as the keyboard path).
	if(is_registered_gamepad(dev_addr, instance)) {
		gamepad_report_receive(dev_addr, instance, report, len);
		tuh_hid_receive_report(dev_addr, instance);
		return;
	}

	u8 slot = hid_slot_get(dev_addr, instance, false);
	if(slot == 0xFF) return;
	hid_report_info_t* rpt_info_arr = hid_info[slot].report_info;
	hid_report_info_t* rpt_info = NULL;

	if(hid_info[slot].report_count == 1 && rpt_info_arr[0].report_id == 0) {
		rpt_info = &rpt_info_arr[0];
	} else {
		uint8_t const rpt_id = report[0];
		for(uint8_t i = 0; i < hid_info[slot].report_count; i++) {
		if(rpt_id == rpt_info_arr[i].report_id) {
			rpt_info = &rpt_info_arr[i];
			break;
		}
		}
		report++;
		len--;
	}

  	if(!rpt_info) return;

	if(tuh_hid_get_protocol(dev_addr, instance) == HID_PROTOCOL_BOOT) {
	  u8 modifiers = report[0];
	  report++; report++;
	  kb_report_receive(modifiers, report, 6);
	} else if(rpt_info->usage_page == HID_USAGE_PAGE_DESKTOP && rpt_info->usage == HID_USAGE_DESKTOP_KEYBOARD) {
	  u8 modifiers = hid_parse_keyboard_modifiers(rpt_info, report, len);
	  if(hid_parse_keyboard_is_nkro(rpt_info)) {
		u8 current_key = 0;
		u8 newreport[sizeof(kb_keys)] = {0};
		u8 newindex = 0;
		for(u8 i = 1; i < len && i < 16; i++) {
		  for(u8 j = 0; j < 8; j++) {
			if(report[i] >> j & 1 && newindex < sizeof(kb_keys)) {
			  newreport[newindex] = current_key;
			  newindex++;
			}
			current_key++;
		  }
		}
		kb_report_receive(modifiers, newreport, sizeof(kb_keys));
	  } else if(len == 7) {
		report++;
		kb_report_receive(modifiers, report, 6);

	  } else if(len == 8 || len == 9) {
		report++; report++;
		kb_report_receive(modifiers, report, 6);
	  }
	}
  tuh_hid_receive_report(dev_addr, instance);
}
