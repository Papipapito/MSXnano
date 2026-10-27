/*
 * Banco de pruebas del usbin.c REAL compilado en el PC: SDK y TinyUSB sustituidos
 * por test/stubs/, sin PIO ni USB. Se llama a los mismos callbacks que llamaria
 * TinyUSB (mount / umount / report) y se lee lo que el firmware pondria en el
 * cable hacia el FPGA (lo que sale por pio_sm_put).
 *
 *   test_usbin                 pruebas con afirmaciones (varios teclados y mandos)
 *   test_usbin dump            escribe los casos de UN solo dispositivo por stdout
 *   test_usbin check <fichero> compara esos mismos casos con el fichero dorado
 *
 * Se compila dos veces: normal, y con -DMSXNANO_DEBUG_CDC=1, que activa el registro
 * dbg_printf() de usbin.c (montajes y desmontajes) capturado en un buffer. La segunda
 * pasa las mismas pruebas y el mismo dorado (el registro no cambia lo que sale al
 * cable) y ademas comprueba el texto del registro.
 *
 * El fichero dorado (golden/single_device.txt) sale de dump con el usbin.c ANTERIOR
 * a los varios dispositivos: check demuestra que con un solo teclado / mando / raton
 * el firmware manda los mismos bytes que antes.
 */
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include "usbin.h"
#include "dbg_log.h"
#include "xinput_host.h"
#include "hardware/pio.h"
#include "pico/time.h"
#include "kbd_merge.h"   // solo KBM_UNION_MAX, para dimensionar las pruebas de desborde

// ---- Lo que normalmente define main.c ----
tusb_desc_device_t desc_device;
uint8_t isMounted = 0;
uint8_t kb_leds = 0;
uint8_t kb_modifiers = 0;
uint8_t kb_keys[120] = {0};
usbh_class_driver_t const usbh_xinput_driver = {0};

// ---- Registro de depuracion (dbg_log.h): solo existe con -DMSXNANO_DEBUG_CDC=1 ----
#if MSXNANO_DEBUG_CDC
static char   g_log[16384];
static size_t g_logn;
void dbg_printf(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    if(g_logn < sizeof g_log) g_logn += (size_t)vsnprintf(g_log + g_logn, sizeof g_log - g_logn, fmt, ap);
    va_end(ap);
}
void dbg_task(void) {}
#endif

// ---- Reloj y cable simulados ----
static uint64_t g_now = 1000000;
uint64_t time_us_64(void) { return g_now; }

static uint8_t g_tx[1 << 16];
static size_t  g_txn;
uint pio_add_program(PIO pio, const pio_program_t *p) { (void)pio; (void)p; return 0; }
bool pio_sm_is_tx_fifo_full(PIO pio, uint sm) { (void)pio; (void)sm; return false; }
void pio_sm_put(PIO pio, uint sm, uint32_t d) {
    (void)pio; (void)sm;
    if(g_txn < sizeof g_tx) g_tx[g_txn++] = (uint8_t)d;
}

// ---- TinyUSB simulado: protocolo de interfaz y de informe por dispositivo ----
static uint8_t itf_proto[16][4];
static uint8_t cur_proto[16][4];
static int     g_led;
bool    tuh_hid_receive_report(uint8_t d, uint8_t i) { (void)d; (void)i; return true; }
uint8_t tuh_hid_interface_protocol(uint8_t d, uint8_t i) { return itf_proto[d][i]; }
uint8_t tuh_hid_get_protocol(uint8_t d, uint8_t i) { return cur_proto[d][i]; }
bool    tuh_hid_set_protocol(uint8_t d, uint8_t i, uint8_t p) { cur_proto[d][i] = p; return true; }
bool    tuh_hid_set_report(uint8_t d, uint8_t i, uint8_t id, uint8_t t, void *r, uint16_t l) {
    (void)d; (void)i; (void)id; (void)t; (void)r; (void)l; return true;
}
bool    tuh_vid_pid_get(uint8_t d, uint16_t *v, uint16_t *p) { (void)d; *v = 0x1234; *p = 0x5678; return true; }
void    board_led_write(bool s) { g_led = s; }
bool    tuh_xinput_receive_report(uint8_t d, uint8_t i) { (void)d; (void)i; return true; }

// ---- Descriptores de informe (bytes HID reales) ----
static const uint8_t DESC_KBD[] = {          // teclado estandar, informe de 8 bytes
    0x05,0x01, 0x09,0x06, 0xA1,0x01,
    0x05,0x07, 0x19,0xE0, 0x29,0xE7, 0x15,0x00, 0x25,0x01, 0x75,0x01, 0x95,0x08, 0x81,0x02,
    0x95,0x01, 0x75,0x08, 0x81,0x01,
    0x95,0x05, 0x75,0x01, 0x05,0x08, 0x19,0x01, 0x29,0x05, 0x91,0x02,
    0x95,0x01, 0x75,0x03, 0x91,0x01,
    0x95,0x06, 0x75,0x08, 0x15,0x00, 0x25,0x65, 0x05,0x07, 0x19,0x00, 0x29,0x65, 0x81,0x00,
    0xC0 };
static const uint8_t DESC_KBD_NKRO[] = {     // modificadores + mapa de 120 bits
    0x05,0x01, 0x09,0x06, 0xA1,0x01,
    0x05,0x07, 0x19,0xE0, 0x29,0xE7, 0x15,0x00, 0x25,0x01, 0x75,0x01, 0x95,0x08, 0x81,0x02,
    0x05,0x07, 0x19,0x00, 0x29,0x77, 0x15,0x00, 0x25,0x01, 0x75,0x01, 0x95,0x78, 0x81,0x02,
    0xC0 };
static const uint8_t DESC_PAD[] = {          // gamepad: X, Y (8 bits) y 8 botones
    0x05,0x01, 0x09,0x05, 0xA1,0x01,
    0x09,0x30, 0x09,0x31, 0x15,0x00, 0x26,0xFF,0x00, 0x75,0x08, 0x95,0x02, 0x81,0x02,
    0x05,0x09, 0x19,0x01, 0x29,0x08, 0x15,0x00, 0x25,0x01, 0x75,0x01, 0x95,0x08, 0x81,0x02,
    0xC0 };
static const uint8_t DESC_PAD2[] = {         // adaptador doble: DOS colecciones Joystick (Report ID 1 y 2) en una interfaz
    0x05,0x01, 0x09,0x04, 0xA1,0x01, 0x85,0x01,
    0x09,0x30, 0x09,0x31, 0x15,0x00, 0x26,0xFF,0x00, 0x75,0x08, 0x95,0x02, 0x81,0x02,
    0x05,0x09, 0x19,0x01, 0x29,0x08, 0x15,0x00, 0x25,0x01, 0x75,0x01, 0x95,0x08, 0x81,0x02,
    0xC0,
    0x05,0x01, 0x09,0x04, 0xA1,0x01, 0x85,0x02,
    0x09,0x30, 0x09,0x31, 0x15,0x00, 0x26,0xFF,0x00, 0x75,0x08, 0x95,0x02, 0x81,0x02,
    0x05,0x09, 0x19,0x01, 0x29,0x08, 0x15,0x00, 0x25,0x01, 0x75,0x01, 0x95,0x08, 0x81,0x02,
    0xC0 };
static const uint8_t DESC_MOUSE[] = {        // raton de 3 botones
    0x05,0x01, 0x09,0x02, 0xA1,0x01, 0x09,0x01, 0xA1,0x00,
    0x05,0x09, 0x19,0x01, 0x29,0x03, 0x15,0x00, 0x25,0x01, 0x95,0x03, 0x75,0x01, 0x81,0x02,
    0x95,0x01, 0x75,0x05, 0x81,0x03,
    0x05,0x01, 0x09,0x30, 0x09,0x31, 0x15,0x81, 0x25,0x7F, 0x75,0x08, 0x95,0x02, 0x81,0x06,
    0xC0, 0xC0 };

// ---- Utilidades de simulacion ----
static void pump(void) { kb_tx_pump(); }

static void plug_hid(uint8_t dev, uint8_t itf, uint8_t cur, const uint8_t *desc, uint16_t len) {
    itf_proto[dev][0] = itf;
    cur_proto[dev][0] = cur;
    tuh_hid_mount_cb(dev, 0, desc, len);
    pump();
}
static void unplug_hid(uint8_t dev) { tuh_hid_umount_cb(dev, 0); pump(); }

// Teclado
#define PROTO_REPORT HID_PROTOCOL_REPORT
#define PROTO_BOOT   HID_PROTOCOL_BOOT
static void kbd_plug(uint8_t dev, uint8_t cur)  { plug_hid(dev, HID_ITF_PROTOCOL_KEYBOARD, cur, DESC_KBD, sizeof DESC_KBD); }
static void nkro_plug(uint8_t dev)              { plug_hid(dev, HID_ITF_PROTOCOL_KEYBOARD, PROTO_REPORT, DESC_KBD_NKRO, sizeof DESC_KBD_NKRO); }
// Informe de 8 bytes: [mods][0][6 teclas]
static void kbd_send(uint8_t dev, uint8_t mods, const uint8_t k[6]) {
    uint8_t r[8] = { mods, 0, k[0], k[1], k[2], k[3], k[4], k[5] };
    tuh_hid_report_received_cb(dev, 0, r, 8);
    pump();
}
// Informe de 7 bytes: [mods][6 teclas]
static void kbd_send7(uint8_t dev, uint8_t mods, const uint8_t k[6]) {
    uint8_t r[7] = { mods, k[0], k[1], k[2], k[3], k[4], k[5] };
    tuh_hid_report_received_cb(dev, 0, r, 7);
    pump();
}
// Informe NKRO: [mods][15 bytes de mapa]; la tecla u esta en el byte 1 + u/8, bit u%8
static void nkro_send(uint8_t dev, uint8_t mods, const uint8_t *usages, int n) {
    uint8_t r[16] = { mods };
    for(int i = 0; i < n; i++) r[1 + usages[i] / 8] |= (uint8_t)(1u << (usages[i] % 8));
    tuh_hid_report_received_cb(dev, 0, r, 16);
    pump();
}
static const uint8_t NOKEYS[6] = {0, 0, 0, 0, 0, 0};

// Mando HID
static void pad_plug(uint8_t dev)   { plug_hid(dev, HID_ITF_PROTOCOL_NONE, PROTO_REPORT, DESC_PAD, sizeof DESC_PAD); }
static void pad_send(uint8_t dev, uint8_t x, uint8_t y, uint8_t btn) {
    uint8_t r[3] = { x, y, btn };
    tuh_hid_report_received_cb(dev, 0, r, 3);
    pump();
}
// Adaptador doble (una interfaz, Report ID 1 = jugador 1, 2 = jugador 2)
static void pad2_plug(uint8_t dev)  { plug_hid(dev, HID_ITF_PROTOCOL_NONE, PROTO_REPORT, DESC_PAD2, sizeof DESC_PAD2); }
static void pad2_send(uint8_t dev, uint8_t id, uint8_t x, uint8_t y, uint8_t btn) {
    uint8_t r[4] = { id, x, y, btn };
    tuh_hid_report_received_cb(dev, 0, r, 4);
    pump();
}
#define PAD_CENTER 0x80
#define PAD_LEFT   0x00
#define PAD_RIGHT  0xFF
#define PAD_UP     0x00
#define PAD_DOWN   0xFF
#define BTN(n)     (1u << (n))   // boton n (0 = el primero)

// Mando XInput
static xinputh_interface_t xi[16];
static void xin_plug(uint8_t dev)   { xi[dev].connected = 1; tuh_xinput_mount_cb(dev, 0, &xi[dev]); pump(); }   // de cable: conectado al configurarse
static void xin_unplug(uint8_t dev) { tuh_xinput_umount_cb(dev, 0); pump(); }
// Receptor inalambrico 360: se configura SIN mando encendido (connected = 0)
static void xin_plug_wireless(uint8_t dev) { xi[dev].connected = 0; tuh_xinput_mount_cb(dev, 0, &xi[dev]); pump(); }
// El driver avisa por el callback de informe, con los datos a cero, al encenderse / apagarse el mando
static void xin_wireless_set(uint8_t dev, uint8_t on) {
    memset(&xi[dev].pad, 0, sizeof xi[dev].pad);
    xi[dev].connected = on;
    xi[dev].new_pad_data = 1;
    tuh_xinput_report_received_cb(dev, 0, &xi[dev], sizeof xi[dev]);
    xi[dev].new_pad_data = 0;
    pump();
}
static void xin_wireless_on(uint8_t dev)  { xin_wireless_set(dev, 1); }
static void xin_wireless_off(uint8_t dev) { xin_wireless_set(dev, 0); }
static void xin_send(uint8_t dev, uint16_t buttons, int16_t lx, int16_t ly) {
    xi[dev].pad.wButtons = buttons;
    xi[dev].pad.sThumbLX = lx;
    xi[dev].pad.sThumbLY = ly;
    xi[dev].connected = 1;
    xi[dev].new_pad_data = 1;
    tuh_xinput_report_received_cb(dev, 0, &xi[dev], sizeof xi[dev]);
    pump();
}

// Raton
static void mouse_plug(uint8_t dev) { plug_hid(dev, HID_ITF_PROTOCOL_MOUSE, PROTO_BOOT, DESC_MOUSE, sizeof DESC_MOUSE); }
static void mouse_send(uint8_t dev, uint8_t btn, int8_t dx, int8_t dy) {
    uint8_t r[3] = { btn, (uint8_t)dx, (uint8_t)dy };
    tuh_hid_report_received_cb(dev, 0, r, 3);
    pump();
}

// Avanza el reloj y hace lo que haria el super-bucle de main.c
static void advance(uint64_t us) {
    g_now += us;
    joy_autofire_tick(g_now);
    mouse_tick(g_now);
    pump();
}
static void resync(void) { kb_send_resync(); joy_send_resync(); mouse_send_resync(); pump(); }   // como el bloque de main.c
// Sin el keepalive del raton (nuevo): el dorado compara lo que el firmware anterior ya mandaba
static void resync_golden(void) { kb_send_resync(); joy_send_resync(); pump(); }

// ---- Decodificador del cable (para las afirmaciones) ----
//   +CC make, -CC break, J<p>=<hex>, D<dx>,<dy>,<btn>, V<ver>, R{fila:valor,..} (solo filas != FF),
//   c<hex> comando suelto. keep_sync = false descarta V... y R...
static char g_dec[4096];
static const char *decode(bool keep_sync) {
    char *o = g_dec;
    *o = 0;
    size_t i = 0;
    #define EMIT(...) do { if(o != g_dec) *o++ = ' '; o += sprintf(o, __VA_ARGS__); } while(0)
    while(i < g_txn) {
        uint8_t b = g_tx[i];
        if((b == 0x90 || b == 0xA0) && i + 1 < g_txn) { EMIT("%c%02X", b == 0x90 ? '+' : '-', g_tx[i + 1]); i += 2; }
        else if(b == 0xB0 && i + 2 < g_txn) { EMIT("J%u=%02X", g_tx[i + 1], g_tx[i + 2]); i += 3; }
        else if(b == 0xD0 && i + 3 < g_txn) { EMIT("D%d,%d,%X", (int8_t)g_tx[i + 1], (int8_t)g_tx[i + 2], g_tx[i + 3]); i += 4; }
        else if(b == 0xC0 && i + 1 < g_txn) { if(keep_sync) EMIT("V%02X", g_tx[i + 1]); i += 2; }
        else if(b == 0xFE && i + 12 < g_txn && g_tx[i + 12] == 0xFF) {
            if(keep_sync) {
                char tmp[256]; char *t = tmp; t += sprintf(t, "R{");
                bool first = true;
                for(int r = 0; r < 11; r++) if(g_tx[i + 1 + r] != 0xFF) {
                    t += sprintf(t, "%s%d:%02X", first ? "" : ",", r, g_tx[i + 1 + r]);
                    first = false;
                }
                sprintf(t, "}");
                EMIT("%s", tmp);
            }
            i += 13;
        }
        else if(b < 0x80) { EMIT("c%02X", b); i++; }
        else { EMIT("?%02X", b); i++; }
    }
    #undef EMIT
    g_txn = 0;
    return g_dec;
}

static int g_checks, g_fail;
static void expect_at(int line, const char *want, bool keep_sync) {
    const char *got = decode(keep_sync);
    g_checks++;
    if(strcmp(got, want) != 0) {
        g_fail++;
        printf("FALLO linea %d:\n   esperado: [%s]\n   obtenido: [%s]\n", line, want, got);
    }
}
#define EXPECT(w)      expect_at(__LINE__, (w), false)
#define EXPECT_SYNC(w) expect_at(__LINE__, (w), true)
#define DRAIN()        do { g_txn = 0; } while(0)
#define CHECK(c)       do { g_checks++; if(!(c)) { g_fail++; printf("FALLO linea %d: %s\n", __LINE__, #c); } } while(0)

// Celda MSX de un uso HID, como "+CC" / "-CC"
static const char *MK(uint8_t u) { static char b[4][8]; static int n; char *s = b[n++ & 3]; sprintf(s, "+%02X", keycode_to_goauld[u]); return s; }
static const char *BK(uint8_t u) { static char b[4][8]; static int n; char *s = b[n++ & 3]; sprintf(s, "-%02X", keycode_to_goauld[u]); return s; }

#define U_A 0x04
#define U_B 0x05
#define U_C 0x06
#define U_D 0x07
#define U_F6 0x3F
#define MOD_LCTRL  0x01
#define MOD_LSHIFT 0x02
#define MOD_LALT   0x04
#define MOD_LGUI   0x08
#define MOD_RCTRL  0x10
#define MOD_RSHIFT 0x20
#define MOD_RALT   0x40
#define CELL_SHIFT "86"
#define CELL_CTRL  "96"
#define CELL_GRAPH "A6"
#define CELL_CODE  "C6"

static void K(uint8_t dev, uint8_t mods, uint8_t a, uint8_t b, uint8_t c, uint8_t d, uint8_t e, uint8_t f) {
    uint8_t k[6] = { a, b, c, d, e, f };
    kbd_send(dev, mods, k);
}

// =========================================================================
// Varios teclados
// =========================================================================
static void test_two_keyboards_interleaved(void) {
    kbd_plug(1, PROTO_REPORT); kbd_plug(2, PROTO_REPORT); DRAIN();
    char want[64];
    K(1, 0, U_A,0,0,0,0,0);       EXPECT(MK(U_A));
    K(2, 0, U_B,0,0,0,0,0);       EXPECT(MK(U_B));                 // sin BREAK falso de A
    K(1, 0, U_A,0,0,0,0,0);       EXPECT("");                      // informe repetido
    K(2, 0, U_B,U_C,0,0,0,0);     EXPECT(MK(U_C));
    K(1, 0, 0,0,0,0,0,0);         EXPECT(BK(U_A));                 // solo se suelta lo suyo
    K(2, 0, U_B,U_C,0,0,0,0);     EXPECT("");
    K(2, 0, 0,0,0,0,0,0);
    sprintf(want, "%s %s", BK(U_B), BK(U_C));
    EXPECT(want);
    unplug_hid(1); unplug_hid(2); DRAIN();
}

static void test_same_key_on_both(void) {
    kbd_plug(1, PROTO_REPORT); kbd_plug(2, PROTO_REPORT); DRAIN();
    K(1, 0, U_A,0,0,0,0,0);       EXPECT(MK(U_A));
    K(2, 0, U_A,0,0,0,0,0);       EXPECT("");                      // ya estaba pulsada
    K(1, 0, 0,0,0,0,0,0);         EXPECT("");                      // el 2.o aun la mantiene
    K(2, 0, 0,0,0,0,0,0);         EXPECT(BK(U_A));
    unplug_hid(1); unplug_hid(2); DRAIN();
}

static void test_unplug_releases_only_its_keys(void) {
    kbd_plug(1, PROTO_REPORT); kbd_plug(2, PROTO_REPORT); DRAIN();
    K(1, MOD_LSHIFT, U_A,0,0,0,0,0);
    char want[64];
    sprintf(want, "+%s %s", CELL_SHIFT, MK(U_A));
    // El Shift sale antes de la tecla (orden del motor): "+86 +E2"
    EXPECT(want);
    K(2, 0, U_B,0,0,0,0,0);       EXPECT(MK(U_B));
    unplug_hid(1);                                                  // se desenchufa el 1.o con A y Shift
    sprintf(want, "%s -%s", BK(U_A), CELL_SHIFT);
    EXPECT(want);                                                   // ...y se sueltan YA, B sigue
    K(2, 0, U_B,0,0,0,0,0);       EXPECT("");
    unplug_hid(2);
    EXPECT(BK(U_B));
    // La matriz que ve el FPGA queda toda suelta
    resync();
    EXPECT_SYNC("V13 R{} J0=00 J1=00");
}

static void test_unplug_sends_resync_frame(void) {
    kbd_plug(1, PROTO_REPORT); DRAIN();
    K(1, 0, U_A,0,0,0,0,0);       DRAIN();
    unplug_hid(1);
    EXPECT_SYNC("-E2 V13 R{}");                                     // BREAK y luego la trama completa, ya suelta
}

static void test_modifiers_or(void) {
    kbd_plug(1, PROTO_REPORT); kbd_plug(2, PROTO_REPORT); DRAIN();
    K(1, MOD_LSHIFT, 0,0,0,0,0,0); EXPECT("+" CELL_SHIFT);
    K(2, MOD_RSHIFT, 0,0,0,0,0,0); EXPECT("");                     // el otro Shift no repite
    K(1, 0, 0,0,0,0,0,0);          EXPECT("");                     // sigue el Shift del 2.o
    K(2, 0, 0,0,0,0,0,0);          EXPECT("-" CELL_SHIFT);
    // Un modificador de cada teclado: CTRL y GRAPH, CODE
    K(1, MOD_LCTRL, 0,0,0,0,0,0);  EXPECT("+" CELL_CTRL);
    K(2, MOD_LALT,  0,0,0,0,0,0);  EXPECT("+" CELL_GRAPH);
    K(2, MOD_LALT | MOD_RALT, 0,0,0,0,0,0); EXPECT("+" CELL_CODE);
    K(2, MOD_LGUI, 0,0,0,0,0,0);   EXPECT("-" CELL_CODE);          // GRAPH sigue (LGUI tambien lo da)
    K(1, 0, 0,0,0,0,0,0);          EXPECT("-" CELL_CTRL);
    K(2, 0, 0,0,0,0,0,0);          EXPECT("-" CELL_GRAPH);
    unplug_hid(1); unplug_hid(2); DRAIN();
}

static void test_modifier_released_by_unplug(void) {
    kbd_plug(1, PROTO_REPORT); kbd_plug(2, PROTO_REPORT); DRAIN();
    K(1, MOD_LSHIFT, 0,0,0,0,0,0); DRAIN();
    K(2, MOD_LCTRL,  0,0,0,0,0,0); EXPECT("+" CELL_CTRL);
    unplug_hid(1);                  EXPECT("-" CELL_SHIFT);
    unplug_hid(2);                  EXPECT("-" CELL_CTRL);
}

static void test_repeated_reports_idempotent(void) {
    kbd_plug(1, PROTO_REPORT); kbd_plug(2, PROTO_REPORT); DRAIN();
    K(1, MOD_LSHIFT, U_A,U_B,0,0,0,0); DRAIN();
    K(2, MOD_RCTRL,  U_C,0,0,0,0,0);   DRAIN();
    for(int i = 0; i < 5; i++) {
        K(1, MOD_LSHIFT, U_A,U_B,0,0,0,0);
        K(2, MOD_RCTRL,  U_C,0,0,0,0,0);
    }
    CHECK(g_txn == 0);                                              // ni un byte al cable
    K(1, 0,0,0,0,0,0,0); K(2, 0,0,0,0,0,0,0); DRAIN();
    unplug_hid(1); unplug_hid(2); DRAIN();
}

static void test_union_overflow(void) {
    // Dos teclados NKRO (a 6 por informe no cabrian 10 teclas): 10 + 10 = 20 > 16
    nkro_plug(1); nkro_plug(2); DRAIN();
    uint8_t a[10], b[10];
    for(int i = 0; i < 10; i++) { a[i] = (uint8_t)(0x04 + i); b[i] = (uint8_t)(0x0E + i); }   // a..j y k..t
    char want[512];
    nkro_send(1, 0, a, 10);
    want[0] = 0;
    for(int i = 0; i < 10; i++) { if(i) strcat(want, " "); strcat(want, MK(a[i])); }
    EXPECT(want);
    nkro_send(2, 0, b, 10);                                         // union = 20: solo caben 16
    want[0] = 0;
    for(int i = 0; i < KBM_UNION_MAX - 10; i++) { if(i) strcat(want, " "); strcat(want, MK(b[i])); }
    EXPECT(want);                                                   // entran las 6 primeras del 2.o; ningun BREAK
    nkro_send(2, 0, b, 10);                                         // repetido: nada
    EXPECT("");
    nkro_send(1, 0, NULL, 0);                                       // el 1.o suelta todo
    // Se rompen sus 10 y entran las 4 del 2.o que antes no cabian
    want[0] = 0;
    for(int i = 0; i < 10; i++) { if(i) strcat(want, " "); strcat(want, BK(a[i])); }
    for(int i = KBM_UNION_MAX - 10; i < 10; i++) { strcat(want, " "); strcat(want, MK(b[i])); }
    EXPECT(want);
    nkro_send(2, 0, NULL, 0);
    want[0] = 0;
    for(int i = 0; i < 10; i++) { if(i) strcat(want, " "); strcat(want, BK(b[i])); }
    EXPECT(want);
    unplug_hid(1); unplug_hid(2); DRAIN();
}

static void test_synthetic_shift_with_two_keyboards(void) {
    kbd_plug(1, PROTO_REPORT); kbd_plug(2, PROTO_REPORT); DRAIN();
    char want[64];
    K(1, 0, U_F6,0,0,0,0,0);                                        // F6 = F1 + SHIFT sintetico
    sprintf(want, "+%s %s", CELL_SHIFT, MK(U_F6));
    EXPECT(want);
    K(2, MOD_LSHIFT, 0,0,0,0,0,0); EXPECT("");                     // Shift fisico del otro: sin cambios
    K(2, 0, 0,0,0,0,0,0);          EXPECT("");                     // ...y al soltarlo F6 sigue pidiendo SHIFT
    K(1, 0, 0,0,0,0,0,0);
    sprintf(want, "%s -%s", BK(U_F6), CELL_SHIFT);
    EXPECT(want);
    unplug_hid(1); unplug_hid(2); DRAIN();
}

static void test_second_keyboard_mount_keeps_state(void) {
    kbd_plug(1, PROTO_REPORT); DRAIN();
    K(1, 0, U_A,0,0,0,0,0);        DRAIN();
    kbd_plug(2, PROTO_REPORT);                                      // se enchufa otro con A pulsada en el 1.o
    EXPECT_SYNC("V13 R{2:BF}");                                     // solo la trama: A sigue pulsada, sin MAKE/BREAK
    K(2, 0, U_B,0,0,0,0,0);        EXPECT(MK(U_B));
    K(1, 0, 0,0,0,0,0,0);          EXPECT(BK(U_A));
    K(2, 0, 0,0,0,0,0,0);          EXPECT(BK(U_B));
    unplug_hid(1); unplug_hid(2); DRAIN();
}

static void test_mixed_protocols_and_nkro(void) {
    kbd_plug(1, PROTO_BOOT); nkro_plug(2); DRAIN();
    K(1, 0, U_A,0,0,0,0,0);        EXPECT(MK(U_A));                 // boot
    uint8_t u[2] = { U_B, U_C };
    nkro_send(2, 0, u, 2);         { char w[32]; sprintf(w, "%s %s", MK(U_B), MK(U_C)); EXPECT(w); }
    K(1, 0, 0,0,0,0,0,0);          EXPECT(BK(U_A));
    nkro_send(2, 0, NULL, 0);      { char w[32]; sprintf(w, "%s %s", BK(U_B), BK(U_C)); EXPECT(w); }
    uint8_t k7[6] = { U_D };
    kbd_plug(3, PROTO_REPORT); DRAIN();
    kbd_send7(3, 0, k7);           EXPECT(MK(U_D));                 // informe de 7 bytes
    kbd_send7(3, 0, NOKEYS);       EXPECT(BK(U_D));
    unplug_hid(1); unplug_hid(2); unplug_hid(3); DRAIN();
}

static void test_non_keyboard_unplug_keeps_keys(void) {
    kbd_plug(1, PROTO_REPORT); DRAIN();
    K(1, 0, U_A,0,0,0,0,0);        DRAIN();
    pad_plug(5); DRAIN();
    unplug_hid(5);                 EXPECT_SYNC("");                 // desenchufar un mando no toca el teclado ni manda nada
    K(1, 0, U_A,0,0,0,0,0);        EXPECT("");
    K(1, 0, 0,0,0,0,0,0);          EXPECT(BK(U_A));
    unplug_hid(1); DRAIN();
}

static void test_led_flags_with_two_keyboards(void) {
    kbd_plug(1, PROTO_REPORT); kbd_plug(2, PROTO_REPORT);
    CHECK(isMounted == 1 && g_kbd_mounted == 1);
    unplug_hid(1);
    CHECK(isMounted == 1 && g_kbd_mounted == 1);                    // queda uno: el LED no se pone en rojo
    unplug_hid(2);
    CHECK(isMounted == 0 && g_kbd_mounted == 0);
    DRAIN();
}

// =========================================================================
// Varios mandos
// =========================================================================
static void test_pad_ports_by_mount_order(void) {
    pad_plug(5); pad_plug(6); pad_plug(7); DRAIN();
    CHECK(g_joy_mounted == 1);
    pad_send(5, PAD_RIGHT, PAD_CENTER, 0);     advance(0);   EXPECT("J0=01");   // el 1.o -> MSX 1
    pad_send(6, PAD_CENTER, PAD_UP, 0);        advance(0);   EXPECT("J1=08");   // el 2.o -> MSX 2
    pad_send(7, PAD_LEFT, PAD_CENTER, 0);      advance(0);   EXPECT("J0=03");   // el 3.o se suma al puerto 0
    pad_send(7, PAD_CENTER, PAD_CENTER, BTN(0)); advance(0); EXPECT("J0=11");   // fuego A del 3.o + derecha del 1.o
    pad_send(7, PAD_CENTER, PAD_CENTER, 0);    advance(0);   EXPECT("J0=01");
    // Se va el del puerto 0: su puerto queda como lo dejen los demas que lo comparten (el 3.o: nada)
    unplug_hid(5);                                           EXPECT("J0=00");
    CHECK(g_joy_mounted == 1);
    pad_send(6, PAD_CENTER, PAD_UP, 0);        advance(0);   EXPECT("");          // el 2.o NO cambia de puerto
    // Un mando nuevo coge el libre mas bajo... el 0 lo ocupa el 3.o, el 1 el 2.o: va al 0
    pad_plug(8);
    pad_send(8, PAD_RIGHT, PAD_CENTER, 0);     advance(0);   EXPECT("J0=01");
    unplug_hid(6);                                           EXPECT("J1=00");   // el 2.o: su puerto vuelve a reposo
    pad_plug(9);                                                                // ahora el libre es el 1
    pad_send(9, PAD_CENTER, PAD_CENTER, BTN(1)); advance(0); EXPECT("J1=20");
    unplug_hid(7);                                           EXPECT("");        // el 8.o sigue en el 0
    unplug_hid(8);                                           EXPECT("J1=00 J0=20");   // el 0 se queda sin mandos: el 9.o (fuego B) pasa al MSX 1
    unplug_hid(9);                                           EXPECT("J0=00");
    CHECK(g_joy_mounted == 0);
}

static void test_lowest_free_port_after_gap(void) {
    pad_plug(5); pad_plug(6); DRAIN();
    pad_send(5, PAD_CENTER, PAD_CENTER, BTN(0)); advance(0); EXPECT("J0=10");
    pad_send(6, PAD_CENTER, PAD_CENTER, BTN(1)); advance(0); EXPECT("J1=20");
    unplug_hid(5);                              EXPECT("J1=00 J0=20");   // el 2.o pasa al MSX 1 sosteniendo su fuego B
    pad_send(6, PAD_CENTER, PAD_CENTER, BTN(1)); advance(0); EXPECT("");        // y ya no se mueve
    pad_plug(7);                                                                // el nuevo coge el libre: el 1
    pad_send(7, PAD_RIGHT, PAD_CENTER, 0);     advance(0);   EXPECT("J1=01");
    unplug_hid(6);                              EXPECT("J1=00 J0=01");           // otra vez el 0 vacio: el 7 pasa al MSX 1
    unplug_hid(7);                              EXPECT("J0=00");
}

static void test_hid_and_xinput_share_registry(void) {
    pad_plug(5); xin_plug(6); DRAIN();
    xin_send(6, XINPUT_GAMEPAD_DPAD_RIGHT, 0, 0);    advance(0); EXPECT("J1=01");   // el XInput es el 2.o: MSX 2
    pad_send(5, PAD_CENTER, PAD_CENTER, BTN(0));     advance(0); EXPECT("J0=10");
    resync();
    EXPECT_SYNC("V13 R{} J0=10 J1=01");                                         // el resync manda los DOS puertos
    unplug_hid(5);                                               EXPECT("J1=00 J0=01");   // el XInput pasa al MSX 1 sosteniendo la derecha
    xin_send(6, XINPUT_GAMEPAD_DPAD_RIGHT, 0, 0);    advance(0); EXPECT("");    // el XInput ya no se mueve
    xin_plug(7);                                                                // nuevo: el libre mas bajo, el 1
    xin_send(7, XINPUT_GAMEPAD_A, 0, 0);             advance(0); EXPECT("J1=10");
    xin_unplug(6);                                               EXPECT("J1=00 J0=10");   // el 0 vacio: el 7 pasa al MSX 1
    xin_unplug(7);                                               EXPECT("J0=00");
    CHECK(g_joy_mounted == 0);
}

static void test_xinput_first_then_hid(void) {
    xin_plug(6); pad_plug(5); DRAIN();
    xin_send(6, XINPUT_GAMEPAD_B, 0, 0);             advance(0); EXPECT("J0=20");   // el XInput montado antes: MSX 1
    pad_send(5, PAD_UP, PAD_UP, 0);                  advance(0); EXPECT("J1=0A");   // X=0 izquierda (02) + Y=0 arriba (08)
    xin_unplug(6); unplug_hid(5); DRAIN();
}

// Con el autofire armado, deja la fase en ALTA y vacia el cable. No depende de
// en que fase estuviera el reloj: el siguiente advance(50000) la baja.
static void af_align_high(void) {
    advance(0);
    if(g_txn == 0) advance(50000);
    DRAIN();
}

static void test_autofire_on_both_ports(void) {
    pad_plug(5); xin_plug(6); DRAIN();
    // Pad HID (puerto 0): boton 3 (indice 2) = autofire A. XInput (puerto 1): X = autofire A, Y = autofire B
    pad_send(5, PAD_CENTER, PAD_CENTER, BTN(2));
    xin_send(6, XINPUT_GAMEPAD_X | XINPUT_GAMEPAD_Y, 0, 0);
    af_align_high();
    advance(50000);  EXPECT("J0=00 J1=00");                                      // fase baja
    advance(50000);  EXPECT("J0=10 J1=30");                                      // fase alta
    // Fuego manual mas autofire en el mismo puerto
    pad_send(5, PAD_RIGHT, PAD_CENTER, BTN(1) | BTN(2));  advance(0);
    EXPECT("J0=31");                                                             // B manual + A (fase alta) + derecha
    advance(50000);  EXPECT("J0=21 J1=00");
    advance(50000);  EXPECT("J0=31 J1=30");                                      // el puerto 1 sigue con su autofire
    // Soltar el boton de autofire lo desarma
    pad_send(5, PAD_CENTER, PAD_CENTER, 0);          advance(0);                 EXPECT("J0=00");
    advance(50000);  EXPECT("J1=00");
    unplug_hid(5); xin_unplug(6); DRAIN();
}

static void test_autofire_pad_unplug_mid_phase(void) {
    pad_plug(5); pad_plug(6); DRAIN();
    pad_send(5, PAD_CENTER, PAD_CENTER, BTN(2));
    pad_send(6, PAD_CENTER, PAD_CENTER, BTN(3));
    af_align_high();                                                             // J0=10 J1=20 ya emitido
    unplug_hid(5);   EXPECT("J1=00 J0=20");                                      // en fase alta: el otro pasa al MSX 1 con su autofire (fase alta)
    advance(50000);  EXPECT("J0=00");
    advance(50000);  EXPECT("J0=20");                                            // y sigue con su autofire en el nuevo puerto
    unplug_hid(6);   EXPECT("J0=00");
    advance(50000);  EXPECT("");
}

static void test_pad_activity_flashes_led(void) {
    pad_plug(5); pad_plug(6); DRAIN();
    g_last_key_us = 0;
    pad_send(6, PAD_RIGHT, PAD_CENTER, 0);
    CHECK(g_last_key_us == g_now);                                             // la actividad del 2.o puerto tambien parpadea
    g_last_key_us = 0;
    pad_send(6, PAD_RIGHT, PAD_CENTER, 0);                                      // mismo informe: sin parpadeo
    CHECK(g_last_key_us == 0);
    unplug_hid(5); unplug_hid(6); DRAIN();
}

static void test_g_joy_out_is_port0(void) {
    pad_plug(5); pad_plug(6); DRAIN();
    pad_send(5, PAD_CENTER, PAD_CENTER, BTN(0)); advance(0);
    CHECK(g_joy_out == 0x10);
    pad_send(6, PAD_RIGHT, PAD_CENTER, 0);       advance(0);
    CHECK(g_joy_out == 0x10);                                                  // el panel de la caja sigue mostrando el puerto 0
    unplug_hid(5); unplug_hid(6); DRAIN();
}

static void test_joy_resync_both_ports_when_idle(void) {
    resync();
    EXPECT_SYNC("V13 R{} J0=00 J1=00");
}

// =========================================================================
// Puertos MSX: el 1 se recompone, el raton se queda el 2, receptor inalambrico, adaptador doble
// =========================================================================
static void test_first_pad_leaving_moves_second_to_port1(void) {
    pad_plug(5); pad_plug(6); DRAIN();
    pad_send(5, PAD_CENTER, PAD_CENTER, BTN(0)); advance(0); EXPECT("J0=10");
    pad_send(6, PAD_RIGHT, PAD_CENTER, 0);       advance(0); EXPECT("J1=01");
    unplug_hid(5);                                           EXPECT("J1=00 J0=01");   // el MSX 2 se libera y el MSX 1 recoge lo que sostenia
    pad_send(6, PAD_RIGHT, PAD_CENTER, 0);       advance(0); EXPECT("");
    resync();
    EXPECT_SYNC("V13 R{} J0=01 J1=00");
    unplug_hid(6);                                           EXPECT("J0=00");
}

static void test_second_pad_leaving_keeps_port1(void) {
    pad_plug(5); pad_plug(6); DRAIN();
    pad_send(5, PAD_RIGHT, PAD_CENTER, 0);       advance(0); EXPECT("J0=01");
    unplug_hid(6);                                           EXPECT("");              // el MSX 2 ya estaba en reposo
    pad_send(5, PAD_RIGHT, PAD_CENTER, 0);       advance(0); EXPECT("");
    unplug_hid(5);                                           EXPECT("J0=00");
}

static void test_mouse_owns_port2(void) {
    mouse_plug(6); pad_plug(5); pad_plug(7); DRAIN();
    pad_send(5, PAD_RIGHT, PAD_CENTER, 0);       advance(0); EXPECT("J0=01");   // con raton, los mandos van todos al MSX 1
    pad_send(7, PAD_CENTER, PAD_UP, 0);          advance(0); EXPECT("J0=09");   // sumados (OR), ninguno al MSX 2
    resync();
    EXPECT_SYNC("V13 R{} J0=09 J1=00 D0,0,0");                                   // el MSX 2 no recibe mandos; el raton repite sus botones
    unplug_hid(5);                                           EXPECT("J0=08");
    unplug_hid(6);                                           EXPECT("D0,0,0");   // el raton se va: el MSX 2 vuelve a estar libre
    CHECK(g_mouse_mounted == 0);
    pad_plug(8);
    pad_send(8, PAD_LEFT, PAD_CENTER, 0);        advance(0); EXPECT("J1=02");   // un mando nuevo ya puede coger el MSX 2
    unplug_hid(7); unplug_hid(8); DRAIN();
}

static void test_mouse_unplug_releases_button(void) {
    mouse_plug(6); DRAIN();
    mouse_send(6, 1, 0, 0);                      advance(10000); EXPECT("D0,0,1");
    CHECK(g_mouse_mounted == 1);
    unplug_hid(6);                                           EXPECT("D0,0,0");   // la FPGA recibe el boton soltado
    CHECK(g_mouse_mounted == 0);
    advance(10000); advance(10000);                          EXPECT("");         // y ni un byte mas
    resync();
    EXPECT_SYNC("V13 R{} J0=00 J1=00");                                          // sin raton no hay keepalive
    // El movimiento que quedaba por entregar tambien se descarta
    mouse_plug(6); DRAIN();
    mouse_send(6, 0, 5, 5);
    unplug_hid(6);                                           EXPECT("D0,0,0");
    advance(20000);                                          EXPECT("");
    // Un raton nuevo empieza limpio
    mouse_plug(6); DRAIN();
    mouse_send(6, 0, 1, 2);                      advance(10000); EXPECT("D1,2,0");
    unplug_hid(6); DRAIN();
}

static void test_two_mice(void) {
    mouse_plug(6); mouse_plug(7); DRAIN();
    unplug_hid(6);                                           EXPECT("");         // queda otro: el puerto 2 sigue siendo del raton
    CHECK(g_mouse_mounted == 1);
    mouse_send(7, 2, 3, 1);                      advance(10000); EXPECT("D3,1,2");
    unplug_hid(7);                                           EXPECT("D0,0,0");
    CHECK(g_mouse_mounted == 0);
}

static void test_mouse_keepalive_in_resync(void) {
    mouse_plug(6); DRAIN();
    resync();
    EXPECT_SYNC("V13 R{} J0=00 J1=00 D0,0,0");
    mouse_send(6, 2, 4, 4);                      advance(10000); EXPECT("D4,4,2");
    resync();
    EXPECT_SYNC("V13 R{} J0=00 J1=00 D0,0,2");                                   // repite los botones, sin movimiento
    mouse_send(6, 0, 0, 0);                      advance(10000); EXPECT("D0,0,0");
    resync();
    EXPECT_SYNC("V13 R{} J0=00 J1=00 D0,0,0");
    unplug_hid(6); DRAIN();
}

static void test_wireless_receiver_registers_when_controller_on(void) {
    xin_plug_wireless(6); DRAIN();                                               // receptor sin ningun mando encendido
    CHECK(g_joy_mounted == 0);
    pad_plug(5); DRAIN();                                                        // un mando de cable llega despues...
    pad_send(5, PAD_CENTER, PAD_CENTER, BTN(0)); advance(0); EXPECT("J0=10");   // ...y se queda con el MSX 1
    xin_wireless_on(6);                                                          // se enciende el inalambrico: entra ahora, por el MSX 2
    CHECK(g_joy_mounted == 1);
    xin_send(6, XINPUT_GAMEPAD_DPAD_RIGHT, 0, 0); advance(0); EXPECT("J1=01");
    xin_wireless_off(6);                                                         // se apaga con la derecha pulsada
    EXPECT("J1=00");                                                             // el MSX 2 se suelta
    xin_wireless_on(6);                                                          // vuelve a encenderse: otra vez limpio
    xin_send(6, XINPUT_GAMEPAD_A, 0, 0);         advance(0); EXPECT("J1=10");
    xin_unplug(6);                                           EXPECT("J1=00");    // se saca el receptor con el mando encendido
    unplug_hid(5);                                           EXPECT("J0=00");
    CHECK(g_joy_mounted == 0);
}

static void test_wireless_empty_receiver_takes_no_port(void) {
    xin_plug_wireless(6); DRAIN();
    pad_plug(5); pad_plug(7); DRAIN();
    pad_send(5, PAD_RIGHT, PAD_CENTER, 0);       advance(0); EXPECT("J0=01");   // el 1.o es el MSX 1
    pad_send(7, PAD_CENTER, PAD_UP, 0);          advance(0); EXPECT("J1=08");   // y el 2.o el MSX 2: el receptor vacio no ocupa ninguno
    xin_unplug(6);                                           EXPECT("");
    unplug_hid(5); unplug_hid(7); DRAIN();
}

static void test_dual_adapter_two_players(void) {
    pad2_plug(5); DRAIN();
    CHECK(g_joy_mounted == 1);
    pad2_send(5, 1, PAD_RIGHT, PAD_CENTER, 0);   advance(0); EXPECT("J0=01");   // jugador 1 -> MSX 1
    pad2_send(5, 2, PAD_CENTER, PAD_CENTER, 0);  advance(0); EXPECT("");        // el informe en reposo del jugador 2 no pisa al 1
    pad2_send(5, 2, PAD_CENTER, PAD_UP, BTN(0)); advance(0); EXPECT("J1=18");   // jugador 2 -> MSX 2 (arriba + A)
    pad2_send(5, 1, PAD_RIGHT, PAD_CENTER, 0);   advance(0); EXPECT("");        // y el 1 sigue como estaba
    pad2_send(5, 2, PAD_CENTER, PAD_UP, BTN(0)); advance(0); EXPECT("");
    resync();
    EXPECT_SYNC("V13 R{} J0=01 J1=18");
    unplug_hid(5);                                           EXPECT("J0=00 J1=00");   // los dos jugadores se sueltan de una vez
    CHECK(g_joy_mounted == 0);
}

static void test_dual_adapter_with_other_pad(void) {
    pad_plug(4); pad2_plug(5); DRAIN();                                          // el suelto es el MSX 1; jugador 1 del adaptador -> MSX 2; jugador 2 -> MSX 1 (OR)
    pad_send(4, PAD_RIGHT, PAD_CENTER, 0);       advance(0); EXPECT("J0=01");
    pad2_send(5, 1, PAD_CENTER, PAD_UP, 0);      advance(0); EXPECT("J1=08");
    pad2_send(5, 2, PAD_LEFT, PAD_CENTER, 0);    advance(0); EXPECT("J0=03");
    unplug_hid(5);                                           EXPECT("J0=01 J1=00");
    CHECK(g_joy_mounted == 1);
    unplug_hid(4);                                           EXPECT("J0=00");
}

// =========================================================================
// Raton y teclado/mandos a la vez
// =========================================================================
static void test_mouse_unaffected(void) {
    kbd_plug(1, PROTO_REPORT); pad_plug(5); mouse_plug(6); DRAIN();
    mouse_send(6, 1, 3, -2);
    advance(10000);   EXPECT("D3,-2,1");
    K(1, 0, U_A,0,0,0,0,0);                                    EXPECT(MK(U_A));
    pad_send(5, PAD_CENTER, PAD_CENTER, BTN(0)); advance(10000); EXPECT("J0=10");
    unplug_hid(5);                                             EXPECT("J0=00");
    mouse_send(6, 0, 1, 1);
    advance(10000);   EXPECT("D1,1,0");
    K(1, 0, 0,0,0,0,0,0);                                      EXPECT(BK(U_A));
    unplug_hid(1); unplug_hid(6); DRAIN();
}

// =========================================================================
// Registro de depuracion: montajes y desmontajes con el puerto MSX de cada mando
// =========================================================================
#if MSXNANO_DEBUG_CDC
static int g_log_checks_done;
static void log_has_at(int line, const char *want) {
    g_checks++;
    g_log_checks_done++;
    if(!strstr(g_log, want)) {
        g_fail++;
        printf("FALLO linea %d: falta en el registro [%s]\n--- registro ---\n%s----------------\n", line, want, g_log);
    }
}
#define LOG_HAS(w) log_has_at(__LINE__, (w))
static void test_debug_log(void) {
    g_log[0] = 0; g_logn = 0;
    kbd_plug(1, PROTO_REPORT);
    pad_plug(2);                       // primero -> puerto MSX 1
    pad_plug(3);                       // segundo -> puerto MSX 2
    xin_plug(4);                       // tercero -> se suma al puerto MSX 1
    mouse_plug(5);
    LOG_HAS("KBD   mount   addr=1 inst=0 1234:5678 (1 teclados)\n");
    LOG_HAS("PAD   HID      addr=2 inst=0 1234:5678\n");
    LOG_HAS("PAD   mount   HID addr=2 inst=0 -> puerto MSX 1 (1 mandos)\n");
    LOG_HAS("PAD   mount   HID addr=3 inst=0 -> puerto MSX 2 (2 mandos)\n");
    LOG_HAS("PAD   mount   XInput addr=4 inst=0 -> puerto MSX 1 (3 mandos)\n");
    LOG_HAS("MOUSE mount   addr=5 inst=0 1234:5678 -> puerto MSX 2 (lo ocupa la FPGA)\n");
    g_log[0] = 0; g_logn = 0;
    unplug_hid(1);
    unplug_hid(3);
    xin_unplug(4);
    unplug_hid(5);
    unplug_hid(2);
    LOG_HAS("HID   umount  addr=1 inst=0 (teclado)\n");
    LOG_HAS("KBD   umount  addr=1 inst=0 (0 teclados)\n");
    LOG_HAS("PAD   umount  HID addr=3 inst=0, suelta el puerto MSX 2 (2 mandos)\n");
    LOG_HAS("PAD   umount  XInput addr=4 inst=0, suelta el puerto MSX 1 (1 mandos)\n");
    LOG_HAS("HID   umount  addr=5 inst=0 (raton)\n");
    LOG_HAS("PAD   umount  HID addr=2 inst=0, suelta el puerto MSX 1 (0 mandos)\n");
    DRAIN();
}

// Adaptador doble (una linea por coleccion) y mandos que pasan del MSX 2 al MSX 1
static void test_debug_log_ports(void) {
    g_log[0] = 0; g_logn = 0;
    pad2_plug(7);
    LOG_HAS("PAD   HID      addr=7 inst=0 1234:5678\n");
    LOG_HAS("PAD   mount   HID addr=7 inst=0 -> puerto MSX 1 (1 mandos)\n");
    LOG_HAS("PAD   mount   HID addr=7 inst=0+c1 -> puerto MSX 2 (2 mandos)\n");
    g_log[0] = 0; g_logn = 0;
    unplug_hid(7);
    LOG_HAS("PAD   umount  HID addr=7 inst=0, suelta el puerto MSX 1 (1 mandos)\n");
    LOG_HAS("PAD   umount  HID addr=7 inst=0+c1, suelta el puerto MSX 2 (0 mandos)\n");
    g_log[0] = 0; g_logn = 0;
    pad_plug(5); pad_plug(6);
    unplug_hid(5);
    LOG_HAS("PAD   los mandos del puerto MSX 2 pasan al puerto MSX 1\n");
    unplug_hid(6);
    DRAIN();
}
#endif

// =========================================================================
// Casos de UN solo dispositivo: volcado y comparacion con el fichero dorado
// =========================================================================
static uint32_t g_rng;
static uint32_t rnd(void) { g_rng = g_rng * 1664525u + 1013904223u; return g_rng >> 8; }

static FILE *g_gold;          // check: fichero dorado abierto; NULL en dump
static int   g_gold_lines, g_gold_bad;

// Una linea por paso: etiqueta y bytes que salieron al cable en ese paso
static void line(const char *label, int step) {
    char buf[8192];
    int n = snprintf(buf, sizeof buf, "%s %d:", label, step);
    for(size_t i = 0; i < g_txn; i++) n += snprintf(buf + n, sizeof buf - n, " %02X", g_tx[i]);
    g_txn = 0;
    g_gold_lines++;
    if(!g_gold) { puts(buf); return; }
    char want[8192];
    if(!fgets(want, sizeof want, g_gold)) {
        if(g_gold_bad++ < 5) printf("FALLO: al fichero dorado le faltan lineas (en '%s')\n", buf);
        return;
    }
    size_t l = strlen(want);
    while(l && (want[l - 1] == '\n' || want[l - 1] == '\r')) want[--l] = 0;
    if(strcmp(buf, want) != 0 && g_gold_bad++ < 5)
        printf("FALLO linea %d del dorado:\n   esperado: %s\n   obtenido: %s\n", g_gold_lines, want, buf);
}

// Teclas que pueden salir al azar (F11 fuera: su comando 0x04 no es de estas pruebas)
static const uint8_t KEYPOOL[] = {
    0x01, 0x04,0x05,0x06,0x07,0x08,0x09,0x0A,0x0B,0x0C,0x0D,0x0E,0x0F,0x10,0x11,0x12,0x13,
    0x1E,0x1F,0x20,0x21,0x22,0x27, 0x28,0x29,0x2A,0x2B,0x2C, 0x2D,0x2E, 0x34,0x36,0x37,0x38,
    0x39, 0x3A,0x3B,0x3C,0x3D,0x3E,0x3F,0x40,0x41,0x42,0x43, 0x45, 0x47, 0x4A,0x4C,0x4D,
    0x4F,0x50,0x51,0x52, 0x56,0x59,0x5E, 0x62, 0x70
};
#define NPOOL ((int)sizeof KEYPOOL)
static const uint8_t MODPOOL[] = { 0x01,0x02,0x04,0x08,0x10,0x20,0x40,0x80,0x22,0x11,0x44,0x03 };

static void random_report(uint8_t *mods, uint8_t slots[6]) {
    *mods = (rnd() % 4 == 0) ? MODPOOL[rnd() % sizeof MODPOOL] : 0;
    memset(slots, 0, 6);
    int n = (int)(rnd() % 7);
    for(int i = 0; i < n; i++) {
        uint8_t u = KEYPOOL[rnd() % NPOOL];
        bool dup = false;
        for(int j = 0; j < 6; j++) if(slots[j] == u) dup = true;
        if(dup) continue;
        int p = (int)(rnd() % 6);
        while(slots[p]) p = (p + 1) % 6;
        slots[p] = u;
    }
}

static void golden_keyboard(const char *label, uint8_t cur, bool seven) {
    uint8_t mods = 0, slots[6] = {0};
    kbd_plug(1, cur);
    line(label, 0);
    for(int s = 1; s <= 300; s++) {
        if(rnd() % 5 != 0) random_report(&mods, slots);       // 1 de cada 5: informe repetido
        if(seven) kbd_send7(1, mods, slots); else kbd_send(1, mods, slots);
        if(s % 25 == 0) resync();
        line(label, s);
    }
    kbd_send(1, 0, NOKEYS);
    line(label, 301);
    unplug_hid(1);
    line(label, 302);
}

static void golden_nkro(void) {
    uint8_t mods = 0, u[24];
    nkro_plug(1);
    line("nkro", 0);
    for(int s = 1; s <= 250; s++) {
        mods = (rnd() % 4 == 0) ? MODPOOL[rnd() % sizeof MODPOOL] : 0;
        int n = (int)(rnd() % 22);                              // hasta 21 a la vez: desborda los 16 del motor
        int c = 0;
        for(int i = 0; i < n; i++) {
            uint8_t k = (uint8_t)(0x04 + rnd() % 0x60);         // 0x04..0x63 (sin el bit del uso 0)
            bool dup = false;
            for(int j = 0; j < c; j++) if(u[j] == k) dup = true;
            if(!dup) u[c++] = k;
        }
        nkro_send(1, mods, u, c);
        if(s % 40 == 0) resync();
        line("nkro", s);
    }
    nkro_send(1, 0, NULL, 0);
    line("nkro", 251);
    unplug_hid(1);
    line("nkro", 252);
}

static void golden_hid_pad(void) {
    static const uint8_t axis[3] = { PAD_LEFT, PAD_CENTER, PAD_RIGHT };
    pad_plug(5);
    line("hidpad", 0);
    for(int s = 1; s <= 300; s++) {
        uint8_t x = axis[rnd() % 3], y = axis[rnd() % 3], b = (uint8_t)(rnd() % 3 == 0 ? rnd() : 0);
        pad_send(5, x, y, b);
        advance(1000 + rnd() % 40000);
        if(s % 20 == 0) resync();
        line("hidpad", s);
    }
    pad_send(5, PAD_CENTER, PAD_CENTER, 0);
    advance(60000);
    line("hidpad", 301);
    // Se retira para que el siguiente caso vuelva a tener UN solo mando. Lo que sale al
    // desenchufar no se compara: el firmware anterior mandaba ahi una trama de resincronizacion
    // del teclado que ya no hace falta.
    unplug_hid(5);
    g_txn = 0;
}

static void golden_xinput(void) {
    static const int16_t th[3] = { -30000, 0, 30000 };
    xin_plug(6);
    line("xinput", 0);
    for(int s = 1; s <= 300; s++) {
        uint16_t b = 0;
        if(rnd() % 2) b = (uint16_t)(rnd() & (XINPUT_GAMEPAD_DPAD_UP | XINPUT_GAMEPAD_DPAD_DOWN | XINPUT_GAMEPAD_DPAD_LEFT |
                                              XINPUT_GAMEPAD_DPAD_RIGHT | XINPUT_GAMEPAD_A | XINPUT_GAMEPAD_B |
                                              XINPUT_GAMEPAD_X | XINPUT_GAMEPAD_Y));
        xin_send(6, b, th[rnd() % 3], th[rnd() % 3]);
        advance(1000 + rnd() % 40000);
        if(s % 20 == 0) resync();
        line("xinput", s);
    }
    xin_send(6, 0, 0, 0);
    advance(60000);
    line("xinput", 301);
    xin_unplug(6);                // ver golden_hid_pad: lo que sale al desenchufar no se compara
    g_txn = 0;
}

static void golden_mouse(void) {
    mouse_plug(6);
    line("mouse", 0);
    for(int s = 1; s <= 200; s++) {
        mouse_send(6, (uint8_t)(rnd() % 4), (int8_t)(rnd() % 61 - 30), (int8_t)(rnd() % 61 - 30));
        advance(2000 + rnd() % 12000);
        line("mouse", s);
    }
    advance(20000);
    line("mouse", 201);
}

static void golden_all_together(void) {
    static const uint8_t axis[3] = { PAD_LEFT, PAD_CENTER, PAD_RIGHT };
    uint8_t mods, slots[6];
    kbd_plug(1, PROTO_REPORT); pad_plug(5); mouse_plug(6);
    line("together", 0);
    for(int s = 1; s <= 400; s++) {
        switch(rnd() % 3) {
        case 0: random_report(&mods, slots); kbd_send(1, mods, slots); break;
        case 1: pad_send(5, axis[rnd() % 3], axis[rnd() % 3], (uint8_t)(rnd() % 2 ? rnd() : 0)); break;
        default: mouse_send(6, (uint8_t)(rnd() % 4), (int8_t)(rnd() % 41 - 20), (int8_t)(rnd() % 41 - 20)); break;
        }
        advance(1000 + rnd() % 30000);
        if(s % 30 == 0) resync_golden();
        line("together", s);
    }
}

static void run_golden(void) {
    g_rng = 12345;
    g_gold_lines = 0;
    golden_keyboard("kbd-report", PROTO_REPORT, false);
    golden_keyboard("kbd-boot", PROTO_BOOT, false);
    golden_keyboard("kbd-7bytes", PROTO_REPORT, true);
    golden_nkro();
    golden_hid_pad();
    golden_xinput();
    golden_mouse();
    golden_all_together();
}

int main(int argc, char **argv) {
    kb_uart_init();

    if(argc >= 2 && !strcmp(argv[1], "dump")) {
        run_golden();
        return 0;
    }
    if(argc >= 3 && !strcmp(argv[1], "check")) {
        g_gold = fopen(argv[2], "r");
        if(!g_gold) { printf("No puedo abrir el fichero dorado %s\n", argv[2]); return 2; }
        run_golden();
        char extra[8192];
        if(fgets(extra, sizeof extra, g_gold)) { g_gold_bad++; printf("FALLO: sobran lineas en el fichero dorado\n"); }
        fclose(g_gold);
        printf("test_usbin check: %d lineas comparadas con el dorado, %d diferencias\n", g_gold_lines, g_gold_bad);
        return g_gold_bad ? 1 : 0;
    }

    test_two_keyboards_interleaved();
    test_same_key_on_both();
    test_unplug_releases_only_its_keys();
    test_unplug_sends_resync_frame();
    test_modifiers_or();
    test_modifier_released_by_unplug();
    test_repeated_reports_idempotent();
    test_union_overflow();
    test_synthetic_shift_with_two_keyboards();
    test_second_keyboard_mount_keeps_state();
    test_mixed_protocols_and_nkro();
    test_non_keyboard_unplug_keeps_keys();
    test_led_flags_with_two_keyboards();
    test_pad_ports_by_mount_order();
    test_lowest_free_port_after_gap();
    test_hid_and_xinput_share_registry();
    test_xinput_first_then_hid();
    test_autofire_on_both_ports();
    test_autofire_pad_unplug_mid_phase();
    test_pad_activity_flashes_led();
    test_g_joy_out_is_port0();
    test_joy_resync_both_ports_when_idle();
    test_first_pad_leaving_moves_second_to_port1();
    test_second_pad_leaving_keeps_port1();
    test_mouse_owns_port2();
    test_mouse_unplug_releases_button();
    test_two_mice();
    test_mouse_keepalive_in_resync();
    test_wireless_receiver_registers_when_controller_on();
    test_wireless_empty_receiver_takes_no_port();
    test_dual_adapter_two_players();
    test_dual_adapter_with_other_pad();
    test_mouse_unaffected();
#if MSXNANO_DEBUG_CDC
    test_debug_log();
    test_debug_log_ports();
    CHECK(g_log_checks_done == 18);
#endif
    printf("test_usbin%s: %d comprobaciones, %d fallos\n", MSXNANO_DEBUG_CDC ? " (con registro)" : "", g_checks, g_fail);
    return g_fail ? 1 : 0;
}
