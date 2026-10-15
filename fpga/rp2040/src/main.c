#include <stdio.h>
#include "pico/stdlib.h"
#include "pico/multicore.h"
#include "hardware/timer.h"
#include "hardware/uart.h"
#include "bsp/board_api.h"
#include "tusb_config.h"
#include "class/hid/hid_host.h"
#include "usbin.h"
#include "dbg_log.h"

#if MSXNANO_CARRIER
#include "tusb.h"
#include "pio_usb.h"
#include "pio_usb_ll.h"
#include "port_watch.h"
#include "hardware/dma.h"
#include "hardware/sync.h"
#endif

// ============== Defines ==============

#define KEYBOARD_REPORT_LEN 6

// ===== Status LED =====
// RP2040-Zero: on-board WS2812 (NeoPixel) on GPIO16, driven via PIO -- a plain
// gpio_put() cannot speak the 800kHz NeoPixel protocol. Raspberry Pi Pico: a
// plain mono LED on GPIO25. States (see the main loop):
//   boot                 -> blue blink (you can see it powered up)
//   idle (no USB kbd)     -> solid red
//   USB keyboard mounted  -> solid green
//   key pressed           -> brief white flash
//   USB mouse mounted     -> solid cyan
//   mouse moving          -> magenta flash
#ifndef RP2040_ZERO
#define RP2040_ZERO 1
#endif

// WS2812 PIO is needed both for the on-board NeoPixel (RP2040-Zero) and for the
// external status strip on the case -- include it unconditionally.
#include "hardware/pio.h"
#include "hardware/clocks.h"
#include "ws2812.pio.h"

static int  s_ws2812_off = -1;    // shared ws2812 program offset (loaded once)

#if !MSXNANO_CARRIER
// ---- External WS2812 status STRIP on the case (visible status bar) ----------
// Daisy-chained WS2812 on STRIP_PIN, driven by its own PIO state machine; all
// LEDs mirror the on-board status LED's colour (a bright bar). Wiring:
//   STRIP_PIN (GPIO26) -> strip DIN  (3.3V data, direct from the RP2040)
//   strip GND         -> common GND
//   strip +V          -> ~4.3V: one silicon diode (1N4007) from the MSX +5V.
//     The 4-7V strip's VIH (~0.7*Vcc) then sits below 3.3V, so it accepts the
//     RP2040's 3.3V data with NO level shifter. (5V direct also works on many
//     4-7V strips; add the diode only if colours glitch.)
#define STRIP_PIN   26    // GP26 (carrier redesign; UART link moved to GP15 via PIO)
#define STRIP_LEDS  8
static PIO  s_strip_pio  = pio0;
static uint s_strip_sm   = 1;     // on-board NeoPixel uses SM0; the strip uses SM1
#endif

#if RP2040_ZERO
#define WS2812_PIN 16
#if MSXNANO_CARRIER
// Portadora: pio0 es entero de Pico-PIO-USB (TX, RX y EOP; su programa TX va en el offset 0).
// El NeoPixel de la Zero va en pio1, SM1: la SM0 de pio1 es la del enlace UART (kb_uart_init()).
static PIO  s_led_pio = pio1;
static uint s_led_sm  = 1;
#else
static PIO  s_led_pio = pio0;
static uint s_led_sm  = 0;
#endif
static void status_led_init(void) {
    s_ws2812_off = pio_add_program(s_led_pio, &ws2812_program);
    ws2812_program_init(s_led_pio, s_led_sm, (uint)s_ws2812_off, WS2812_PIN, 800000.f, false);
}
// r,g,b in 0..255 -> WS2812 wants GRB, MSB-first, left-justified in 32 bits.
static inline void status_led_rgb(uint8_t r, uint8_t g, uint8_t b) {
    uint32_t grb = ((uint32_t)g << 16) | ((uint32_t)r << 8) | (uint32_t)b;
    pio_sm_put_blocking(s_led_pio, s_led_sm, grb << 8u);
}
#else
#define PICO_LED_PIN 25
static void status_led_init(void) {
    gpio_init(PICO_LED_PIN);
    gpio_set_dir(PICO_LED_PIN, GPIO_OUT);
}
// Pico has a single mono LED: lit for any non-black colour.
static inline void status_led_rgb(uint8_t r, uint8_t g, uint8_t b) {
    gpio_put(PICO_LED_PIN, (r | g | b) ? 1 : 0);
}
#endif

#if !MSXNANO_CARRIER
// Set up the external strip's PIO state machine. Reuses the ws2812 program that
// status_led_init() already loaded on RP2040-Zero; loads it itself on a plain
// Pico. Must be called AFTER status_led_init().
static void strip_init(void) {
    if (s_ws2812_off < 0)
        s_ws2812_off = pio_add_program(s_strip_pio, &ws2812_program);
    ws2812_program_init(s_strip_pio, s_strip_sm, (uint)s_ws2812_off, STRIP_PIN, 800000.f, false);
}
// Fill all STRIP_LEDS with one colour (used for the boot blink).
static inline void strip_rgb(uint8_t r, uint8_t g, uint8_t b) {
    uint32_t grb = ((uint32_t)g << 16) | ((uint32_t)r << 8) | (uint32_t)b;
    for (int i = 0; i < STRIP_LEDS; i++)
        pio_sm_put_blocking(s_strip_pio, s_strip_sm, grb << 8u);
}
// Push a per-LED frame (STRIP_LEDS colours packed as 0xRRGGBB) to the strip.
static inline void strip_push(const uint32_t *c) {
    for (int i = 0; i < STRIP_LEDS; i++) {
        uint8_t r = (uint8_t)(c[i] >> 16), g = (uint8_t)(c[i] >> 8), b = (uint8_t)c[i];
        uint32_t grb = ((uint32_t)g << 16) | ((uint32_t)r << 8) | (uint32_t)b;
        pio_sm_put_blocking(s_strip_pio, s_strip_sm, grb << 8u);
    }
}
#endif

#define BUF_COUNT   4

// Full-matrix resync cadence (microseconds). Self-heals any dropped event.
#define RESYNC_INTERVAL_US 250000ull

// ============== Global Variables ==============

tusb_desc_device_t desc_device;
uint8_t buf_pool[BUF_COUNT][64];
uint8_t buf_owner[BUF_COUNT] = { 0 };
uint8_t isMounted = 0;       // set by the HID mount/unmount callbacks (usbin.c)
uint8_t kb_leds = 0;
uint8_t kb_modifiers = 0;
// NKRO scratch sizing only (the event model uses its own internal state in
// usbin.c). Kept so the NKRO expansion in tuh_hid_report_received_cb is
// unchanged; kb_report_receive() caps the effective key count safely.
uint8_t kb_keys[120] = {0};

#if MSXNANO_CARRIER
// ============== Host USB de la portadora (Pico-PIO-USB, tres puertos raiz) ==============
//
// Puertos USB-A de la portadora MSXnano v2 (D- = D+ + 1, pinout DPDM; cualquier dispositivo
// va en cualquier puerto). El orden fija el puerto raiz de PIO-USB y el rhport de TinyUSB:
//   J1 (trasero, "teclado")   D+ = GP26 -> puerto raiz 0, rhport 1
//   J2 (trasero, "mando")     D+ = GP28 -> puerto raiz 1, rhport 2
//   J5 (interno, frontal)     D+ = GP0  -> puerto raiz 2, rhport 3
#define CARRIER_J1_DP   26
#define CARRIER_J2_DP   28
#define CARRIER_J5_DP   0

// Pico-PIO-USB dimensiona sus tablas con PIO_USB_ROOT_PORT_CNT; sin los tres puertos el
// segundo pio_usb_host_add_port() falla en silencio. El 3 lo pone cmake/stage_pio_usb.cmake.
_Static_assert(PIO_USB_ROOT_PORT_CNT == 3, "Pico-PIO-USB sin parchear: hacen falta 3 puertos raiz");

// Todo el host vive en el nucleo 0: tuh_init() va aqui, asi que la alarma de 1 ms de PIO-USB
// (SOF y todas las transferencias, dentro de su IRQ) tambien corre en este nucleo, igual que
// tuh_task(), los callbacks de usbin.c, las bombas del enlace y el LED. Un solo dueno de todo
// ese estado (sin cerrojos); el nucleo 1 no se lanza. No partir tuh_task() y las bombas.
static void carrier_usb_init(void) {
    // PIO-USB usa pio0 entero (TX en la SM0, RX en la SM1, EOP en la SM2); el enlace UART y el
    // LED van en pio1. Reclama el canal DMA con dma_claim_mask(): se elige uno libre y se
    // suelta para que lo reclame el, en vez de fiar en que el 0 esta libre.
    int ch = dma_claim_unused_channel(true);
    dma_channel_unclaim((uint)ch);

    pio_usb_configuration_t cfg = PIO_USB_DEFAULT_CONFIG;
    cfg.pin_dp     = CARRIER_J1_DP;
    cfg.pio_tx_num = 0;
    cfg.sm_tx      = 0;
    cfg.pio_rx_num = 0;
    cfg.sm_rx      = 1;
    cfg.sm_eop     = 2;
    cfg.tx_ch      = (uint8_t)ch;
    bool cfg_ok = tuh_configure(BOARD_TUH_RHPORT, TUH_CFGID_RPI_PIO_USB_CONFIGURATION, &cfg);

#if MSXNANO_DEBUG_CDC
    // El USB-C de la Zero como dispositivo CDC (rhport 0), para dbg_printf().
    const tusb_rhport_init_t dev_init = { .role = TUSB_ROLE_DEVICE, .speed = TUSB_SPEED_AUTO };
    tusb_init(BOARD_TUD_RHPORT, &dev_init);
#endif

    const tusb_rhport_init_t host_init = { .role = TUSB_ROLE_HOST, .speed = TUSB_SPEED_AUTO };
    bool host_ok = tusb_init(BOARD_TUH_RHPORT, &host_init);

    // Puertos extra: despues de tuh_init (pio_usb_host_add_port usa el estado que crea).
    int r2 = pio_usb_host_add_port(CARRIER_J2_DP, PIO_USB_PINOUT_DPDM);
    int r5 = pio_usb_host_add_port(CARRIER_J5_DP, PIO_USB_PINOUT_DPDM);

    dbg_printf("MSXnano carrier fw 0x%02x, TinyUSB %s, sys %lu kHz, PIO-USB pio0 dma%d\n",
               FW_VERSION, TUSB_VERSION_STRING, (unsigned long)(clock_get_hz(clk_sys) / 1000u), ch);
    dbg_printf("PIO-USB configure=%d host_init=%d | J1 D+=GP%u (rhport 1) | J2 D+=GP%u add=%d (rhport 2) | J5 D+=GP%u add=%d (rhport 3)\n",
               cfg_ok, host_ok, CARRIER_J1_DP, CARRIER_J2_DP, r2, CARRIER_J5_DP, r5);
    (void)cfg_ok; (void)host_ok; (void)r2; (void)r5;
}

#if MSXNANO_DEBUG_CDC
// Registro de montajes: direccion, VID:PID y de que puerto raiz cuelga (J1/J2/J5).
static uint16_t s_dev_vid[CFG_TUH_DEVICE_MAX + CFG_TUH_HUB + 1];
static uint16_t s_dev_pid[CFG_TUH_DEVICE_MAX + CFG_TUH_HUB + 1];

static const char *carrier_port_name(uint8_t rhport) {
    switch (rhport) {
        case 1:  return "J1";
        case 2:  return "J2";
        case 3:  return "J5";
        default: return "?";
    }
}

void tuh_mount_cb(uint8_t daddr) {
    uint16_t vid = 0, pid = 0;
    tuh_vid_pid_get(daddr, &vid, &pid);
    tuh_bus_info_t bus;
    tuh_bus_info_get(daddr, &bus);
    if (daddr < sizeof(s_dev_vid) / sizeof(s_dev_vid[0])) { s_dev_vid[daddr] = vid; s_dev_pid[daddr] = pid; }
    dbg_printf("USB mount   addr=%u %04x:%04x puerto=%s hub=%u/%u\n",
               daddr, vid, pid, carrier_port_name(bus.rhport), bus.hub_addr, bus.hub_port);
}

void tuh_umount_cb(uint8_t daddr) {
    uint16_t vid = 0, pid = 0;
    if (daddr < sizeof(s_dev_vid) / sizeof(s_dev_vid[0])) { vid = s_dev_vid[daddr]; pid = s_dev_pid[daddr]; }
    dbg_printf("USB umount  addr=%u %04x:%04x\n", daddr, vid, pid);
}
#endif

// Pico-PIO-USB deja un puerto connected+suspended con la linea en SE0 si el dispositivo se saca
// antes de que TinyUSB lo reinicie (ver inc/port_watch.h) y ya no detecta nada hasta apagar. Cada
// 100 ms se mira cada puerto raiz; si lleva 3 pasadas asi y no hay un reset de bus en curso (D+ con
// el habilitador de salida forzado) se marca desconectado, y la IRQ de SOF volvera a ver la
// proxima conexion. La lectura y el cambio van con las interrupciones cortadas: la alarma de 1 ms
// de PIO-USB toca esos mismos campos.
static void __noinline carrier_port_watch(uint64_t now) {
    static uint64_t next = 0;
    static uint8_t  se0_passes[PIO_USB_ROOT_PORT_CNT];
    if ((int64_t)(now - next) < 0) return;
    next = now + PW_INTERVAL_US;
    for (uint i = 0; i < PIO_USB_ROOT_PORT_CNT; i++) {
        root_port_t *root = PIO_USB_ROOT_PORT(i);
        uint32_t irq = save_and_disable_interrupts();
        bool release = false;
        if (root->initialized) {
            uint32_t oeover = (io_bank0_hw->io[root->pin_dp].ctrl & IO_BANK0_GPIO0_CTRL_OEOVER_BITS)
                              >> IO_BANK0_GPIO0_CTRL_OEOVER_LSB;
            release = pw_step(&se0_passes[i], root->connected, root->suspended, oeover != GPIO_OVERRIDE_NORMAL,
                              pio_usb_bus_get_line_state(root) == PORT_PIN_SE0);
            if (release) root->connected = false;
        }
        restore_interrupts(irq);
        if (release) dbg_printf("PIO-USB %s: linea en SE0 sin enumerar, puerto liberado\n", carrier_port_name((uint8_t)(i + 1)));
    }
}
#else
// ============== Core 1 ==============

void core1_entry() {
    while (1) {
        sleep_ms(200);
    }
}
#endif

// ============== Main ==============

int main() {
#if MSXNANO_CARRIER
    // Pico-PIO-USB exige un reloj de sistema multiplo de 12 MHz (TX a 48 MHz): lo primero de
    // todo, antes de que nada calcule divisores a partir de clk_sys.
    set_sys_clock_khz(120000, true);
#endif

    // stdio is routed to USB-CDC only (PICO_STDIO_UART disabled in CMakeLists),
    // so this never touches uart0. Any DEBUG printf goes over USB-CDC.
    stdio_init_all();

    // Dedicated keyboard link: PIO UART TX on GP15 -> FPGA pin 31 (see usbin.c).
    // Must run AFTER stdio_init_all() so our explicit pin mux owns GP15.
    kb_uart_init();

#if MSXNANO_CARRIER
    status_led_init();
    carrier_usb_init();
#else
    tusb_init();

    status_led_init();
    strip_init();          // external 8-LED status strip on the case (GPIO26)

    // Launch Core 1
    multicore_launch_core1(core1_entry);
#endif

#ifdef DEBUG
    printf("Firmware Boot Done\n");
#endif

    // Boot indicator: blink blue a few times so it is visibly alive.
    for (int i = 0; i < 3; i++) {
#if MSXNANO_CARRIER
        status_led_rgb(0, 0, 40); sleep_ms(120);
        status_led_rgb(0, 0, 0);  sleep_ms(120);
#else
        status_led_rgb(0, 0, 40); strip_rgb(0, 0, 40); sleep_ms(120);
        status_led_rgb(0, 0, 0);  strip_rgb(0, 0, 0);  sleep_ms(120);
#endif
    }

    tuh_hid_set_default_protocol(HID_PROTOCOL_REPORT);

    uint64_t next_resync = time_us_64() + RESYNC_INTERVAL_US;
    uint32_t led_prev = 0xFFFFFFFFu;
#if !MSXNANO_CARRIER
    uint32_t strip_prev[STRIP_LEDS];
    for (int i = 0; i < STRIP_LEDS; i++) strip_prev[i] = 0xFFFFFFFFu;  // force first push
#endif

    while (1) {
        dbg_task();      // tud_task() + registro por CDC (nada sin MSXNANO_DEBUG_CDC)
        tuh_task();      // service USB host (fills the TX ring via callbacks)
        kb_tx_pump();    // drain TX ring into uart0 FIFO -- never blocks

        uint64_t now = time_us_64();

#if MSXNANO_CARRIER
        carrier_port_watch(now);  // suelta un puerto raiz que se ha quedado colgado (J1/J2/J5)
#endif

        joy_autofire_tick(now);   // advance autofire square wave + emit composed joy byte

        mouse_tick(now);          // vuelca el acumulador del raton a 100 Hz (0xD0)

        // Periodic full-matrix resync (also self-heals any dropped byte).
        if ((int64_t)(now - next_resync) >= 0) {
            kb_send_resync();
            joy_send_resync();   // re-emit both MSX joystick ports (0xB0 frames)
            mouse_send_resync(); // mouse keepalive + button state (nothing without a mouse)
            kb_tx_pump();
            next_resync = now + RESYNC_INTERVAL_US;
        }

        // ---- LED de a bordo: un color por prioridad ----------------------
        //   magenta parpadeo = el RATON esta mandando informes (se mueve)
        //   cian fijo        = raton MONTADO pero sin informes  <- diagnostico
        //   blanco parpadeo  = actividad de teclado/joystick
        //   amarillo         = gamepad montado
        //   verde            = teclado montado
        //   rojo             = nada montado
        // Los dos primeros separan las DOS cosas que pueden fallar con un raton:
        // que no llegue a montarse, o que se monte y no mande nada (que era el
        // fallo del 03/09: el SET_PROTOCOL invalidaba la peticion de informe).
        uint32_t led;
        if      ((uint64_t)(now - g_last_mouse_us) < 70000ull && g_mouse_mounted)
                                                             led = 0x200020u;  // magenta: raton moviendose
        else if ((uint64_t)(now - g_last_key_us) < 70000ull)  led = 0x202020u;  // blanco: actividad
        else if (g_mouse_mounted)                            led = 0x002020u;  // cian: raton montado
        else if (g_joy_mounted)                              led = 0x141400u;  // amarillo: gamepad
        else if (isMounted)                                  led = 0x002000u;  // verde: teclado
        else                                                 led = 0x1A0000u;  // rojo: nada
        if (led != led_prev) {
            status_led_rgb((uint8_t)(led >> 16), (uint8_t)(led >> 8), (uint8_t)led);
            led_prev = led;
        }

#if !MSXNANO_CARRIER
        // ---- Case strip: an 8-LED panel, each LED a different signal --------
        //  [0] power red (always)      [1] keyboard blue (mounted)
        //  [2] joystick yellow (mounted) [3] typing white (key flash)
        //  [4] fire A green             [5] fire B magenta   (both blink at 10Hz on autofire)
        //  [6] direction cyan (any dir) [7] heartbeat dim-green (~1Hz, "alive")
        uint8_t  joy    = g_joy_out;
        bool     typing = (uint64_t)(now - g_last_kbd_us) < 90000ull;
        uint32_t f[STRIP_LEDS];
        f[0] = 0x140000u;                                                          // power: red
        f[1] = g_kbd_mounted ? 0x000018u : 0;                                      // keyboard: blue
        f[2] = g_joy_mounted ? 0x141400u : 0;                                      // joystick: yellow
        f[3] = typing ? 0x101010u : 0;                                             // typing: white
        f[4] = (joy & JOYO_A) ? 0x001400u : 0;                                     // fire A: green
        f[5] = (joy & JOYO_B) ? 0x140014u : 0;                                     // fire B: magenta
        f[6] = (joy & (JOYO_UP|JOYO_DOWN|JOYO_LEFT|JOYO_RIGHT)) ? 0x001414u : 0;   // direction: cyan
        f[7] = ((now / 500000ull) & 1ull) ? 0x000600u : 0;                         // heartbeat: ~1Hz dim green
        bool strip_changed = false;
        for (int i = 0; i < STRIP_LEDS; i++) if (f[i] != strip_prev[i]) strip_changed = true;
        if (strip_changed) {                       // send-on-change: crisp blinks, PIO not flooded
            strip_push(f);
            for (int i = 0; i < STRIP_LEDS; i++) strip_prev[i] = f[i];
        }
#endif
    }

    return 0;
}
