/*
 * Pruebas de la logica pura de inc/kbd_merge.h (union de teclados y asignacion
 * de mandos a puertos MSX). Sin SDK ni TinyUSB; se ejecuta en el PC con run.ps1.
 */
#include <stdio.h>
#include <string.h>
#include "kbd_merge.h"

static int g_checks, g_fail;

#define CHECK(cond) do { g_checks++; if(!(cond)) { g_fail++; \
    printf("FALLO %s:%d: %s\n", __FILE__, __LINE__, #cond); } } while(0)

static bool has(const uint8_t *l, uint8_t n, uint8_t u) { return kbm_has(l, n, u); }

// ---------------------------------------------------------------- teclados

static void test_kbm_set_basic(void) {
    kbm_t m; memset(&m, 0, sizeof m);
    uint8_t k[6] = {0, 0x05, 0, 0x04, 0x05, 0};   // huecos, y 0x05 repetida
    CHECK(kbm_set(&m, 1, 0, 0x22, k, 6));
    int i = kbm_find(&m, 1, 0);
    CHECK(i == 0);
    CHECK(m.kb[0].modifiers == 0x22);
    CHECK(m.kb[0].nkeys == 2);                    // sin ceros ni repetidas
    CHECK(m.kb[0].keys[0] == 0x05 && m.kb[0].keys[1] == 0x04);   // orden de informe
    // Reemplaza, no acumula
    uint8_t k2[6] = {0x06};
    CHECK(kbm_set(&m, 1, 0, 0, k2, 6));
    CHECK(m.kb[0].nkeys == 1 && m.kb[0].keys[0] == 0x06 && m.kb[0].modifiers == 0);
    // dev_addr 0 no vale
    CHECK(!kbm_set(&m, 0, 0, 0, k2, 6));
    CHECK(kbm_find(&m, 0, 0) == -1);
}

static void test_kbm_distinguishes_instances(void) {
    kbm_t m; memset(&m, 0, sizeof m);
    uint8_t a[1] = {0x04}, b[1] = {0x05};
    kbm_set(&m, 3, 0, 0, a, 1);
    kbm_set(&m, 3, 1, 0, b, 1);                   // mismo dispositivo, otra interfaz
    CHECK(kbm_find(&m, 3, 0) != kbm_find(&m, 3, 1));
    uint8_t out[KBM_UNION_MAX], mods;
    CHECK(kbm_merge(&m, &mods, out) == 2);
    CHECK(kbm_remove(&m, 3, 0));
    CHECK(!kbm_remove(&m, 3, 0));                 // ya no estaba
    CHECK(kbm_merge(&m, &mods, out) == 1 && out[0] == 0x05);
}

static void test_kbm_count(void) {
    kbm_t m; memset(&m, 0, sizeof m);
    CHECK(kbm_count(&m) == 0);
    kbm_add(&m, 1, 0);
    kbm_add(&m, 1, 0);                            // repetido: sigue siendo uno
    kbm_add(&m, 2, 0);
    CHECK(kbm_count(&m) == 2);
    kbm_remove(&m, 1, 0);
    CHECK(kbm_count(&m) == 1);
    kbm_remove(&m, 1, 0);                         // ya no estaba
    CHECK(kbm_count(&m) == 1);
    for(uint8_t d = 3; d < 3 + KBM_MAX_KB; d++) kbm_add(&m, d, 0);
    CHECK(kbm_count(&m) == KBM_MAX_KB);           // tabla llena: no pasa del maximo
}

static void test_kbm_per_kb_cap(void) {
    kbm_t m; memset(&m, 0, sizeof m);
    uint8_t k[120];
    for(int i = 0; i < 120; i++) k[i] = (uint8_t)(0x04 + i);   // 120 teclas distintas
    CHECK(kbm_set(&m, 1, 0, 0, k, 120));
    CHECK(m.kb[0].nkeys == KBM_KEYS_PER_KB);
    for(int i = 0; i < KBM_KEYS_PER_KB; i++) CHECK(m.kb[0].keys[i] == 0x04 + i);   // las primeras
}

static void test_kbm_merge_union(void) {
    kbm_t m; memset(&m, 0, sizeof m);
    uint8_t a[3] = {0x04, 0x05, 0x06}, b[3] = {0x05, 0x07, 0x04};
    kbm_set(&m, 1, 0, 0x02, a, 3);                // LShift
    kbm_set(&m, 2, 0, 0x20, b, 3);                // RShift
    uint8_t out[KBM_UNION_MAX], mods = 0;
    uint8_t n = kbm_merge(&m, &mods, out);
    CHECK(mods == 0x22);                          // OR de modificadores
    CHECK(n == 4);                                // 04 05 06 07: sin repetidas
    CHECK(out[0] == 0x04 && out[1] == 0x05 && out[2] == 0x06 && out[3] == 0x07);   // orden de hueco
    // Idempotente: misma entrada, misma salida
    uint8_t out2[KBM_UNION_MAX], mods2 = 0;
    kbm_set(&m, 1, 0, 0x02, a, 3);
    CHECK(kbm_merge(&m, &mods2, out2) == n && mods2 == mods && !memcmp(out, out2, n));
}

static void test_kbm_merge_empty(void) {
    kbm_t m; memset(&m, 0, sizeof m);
    uint8_t out[KBM_UNION_MAX], mods = 0xFF;
    CHECK(kbm_merge(&m, &mods, out) == 0 && mods == 0);
    kbm_add(&m, 1, 0);                            // alta sin pulsar nada
    CHECK(kbm_merge(&m, &mods, out) == 0 && mods == 0);
}

static void test_kbm_merge_overflow_deterministic(void) {
    kbm_t m; memset(&m, 0, sizeof m);
    uint8_t a[10], b[10];
    for(int i = 0; i < 10; i++) { a[i] = (uint8_t)(0x04 + i); b[i] = (uint8_t)(0x20 + i); }
    kbm_set(&m, 1, 0, 0x01, a, 10);
    kbm_set(&m, 2, 0, 0x10, b, 10);               // 20 teclas distintas: desborda
    uint8_t out[KBM_UNION_MAX + 4], mods = 0;
    memset(out, 0xEE, sizeof out);
    uint8_t n = kbm_merge(&m, &mods, out);
    CHECK(n == KBM_UNION_MAX);
    CHECK(out[KBM_UNION_MAX] == 0xEE);            // no escribe de mas
    for(int i = 0; i < 10; i++) CHECK(out[i] == a[i]);               // primero el hueco 0 entero
    for(int i = 0; i < KBM_UNION_MAX - 10; i++) CHECK(out[10 + i] == b[i]);   // y el principio del 1
    CHECK(mods == 0x11);                          // los modificadores no se recortan
    // Se repite igual
    uint8_t out2[KBM_UNION_MAX], mods2 = 0;
    CHECK(kbm_merge(&m, &mods2, out2) == n && !memcmp(out, out2, n) && mods2 == mods);
    // Una tecla repetida entre teclados no gasta hueco
    uint8_t c[10];
    for(int i = 0; i < 10; i++) c[i] = a[i];      // el teclado 2 pulsa lo mismo que el 1
    kbm_set(&m, 2, 0, 0, c, 10);
    CHECK(kbm_merge(&m, &mods, out) == 10);
}

static void test_kbm_overflow_keeps_mods_of_late_keyboards(void) {
    kbm_t m; memset(&m, 0, sizeof m);
    uint8_t a[16], z[1] = {0x70};
    for(int i = 0; i < 16; i++) a[i] = (uint8_t)(0x04 + i);
    kbm_set(&m, 1, 0, 0, a, 16);                  // llena la union
    kbm_set(&m, 2, 0, 0x40, z, 1);                // RAlt (CODE) en el 2.o teclado
    uint8_t out[KBM_UNION_MAX], mods = 0;
    CHECK(kbm_merge(&m, &mods, out) == 16);
    CHECK(!has(out, 16, 0x70));                   // la tecla se recorta...
    CHECK(mods == 0x40);                          // ...pero el modificador no
}

static void test_kbm_table_full_and_reuse(void) {
    kbm_t m; memset(&m, 0, sizeof m);
    uint8_t k[1] = {0x04};
    for(uint8_t d = 1; d <= KBM_MAX_KB; d++) CHECK(kbm_set(&m, d, 0, 0, k, 1));
    CHECK(!kbm_set(&m, 9, 0, 0, k, 1));           // llena: se ignora el 9.o
    CHECK(kbm_find(&m, 9, 0) == -1);
    CHECK(kbm_remove(&m, 4, 0));
    CHECK(kbm_set(&m, 9, 0, 0, k, 1));            // el hueco liberado se reutiliza
    CHECK(kbm_find(&m, 9, 0) == 3);
}

// ----------------------------------------------------------------- mandos

#define R 0x01
#define L 0x02
#define U 0x08
#define A 0x10
#define B 0x20

static void test_jpm_ports_by_mount_order(void) {
    jpm_t m; memset(&m, 0, sizeof m);
    int p1 = jpm_add(&m, JPM_HID, 5, 0, false);
    int p2 = jpm_add(&m, JPM_XINPUT, 6, 0, false);
    int p3 = jpm_add(&m, JPM_HID, 7, 0, false);
    int p4 = jpm_add(&m, JPM_HID, 8, 0, false);
    CHECK(m.pad[p1].port == 0);                   // el primero al MSX 1
    CHECK(m.pad[p2].port == 1);                   // el segundo al MSX 2
    CHECK(m.pad[p3].port == 0);                   // del tercero en adelante, al 0
    CHECK(m.pad[p4].port == 0);
    CHECK(jpm_count(&m) == 4);
}

static void test_jpm_same_key_is_idempotent(void) {
    jpm_t m; memset(&m, 0, sizeof m);
    int p1 = jpm_add(&m, JPM_HID, 5, 0, false);
    int p2 = jpm_add(&m, JPM_HID, 6, 0, false);
    jpm_set(&m, p2, R, A);
    int again = jpm_add(&m, JPM_HID, 6, 0, false);       // vuelve a montarse sin desmontar
    CHECK(again == p2 && m.pad[p2].port == 1);    // conserva el puerto
    CHECK(m.pad[p2].base == 0 && m.pad[p2].af == 0);   // y arranca limpio
    CHECK(jpm_count(&m) == 2 && p1 == 0);
    // HID y XInput con el mismo (dev, inst) son mandos distintos
    int x = jpm_add(&m, JPM_XINPUT, 6, 0, false);
    CHECK(x != p2 && jpm_count(&m) == 3);
    CHECK(jpm_find(&m, JPM_XINPUT, 6, 0) == x && jpm_find(&m, JPM_HID, 6, 0) == p2);
}

static void test_jpm_remove_keeps_other_port(void) {
    jpm_t m; memset(&m, 0, sizeof m);
    int p1 = jpm_add(&m, JPM_HID, 5, 0, false);
    int p2 = jpm_add(&m, JPM_HID, 6, 0, false);
    CHECK(jpm_remove(&m, JPM_HID, 5, 0) == 0);    // devuelve el puerto liberado
    CHECK(jpm_remove(&m, JPM_HID, 5, 0) == -1);   // ya no estaba
    CHECK(m.pad[p2].port == 1);                   // el otro NO se mueve
    (void)p1;
    int p3 = jpm_add(&m, JPM_HID, 7, 0, false);          // el nuevo coge el libre mas bajo
    CHECK(m.pad[p3].port == 0);
    // Y al reves: se va el del puerto 1, el siguiente lo recupera
    CHECK(jpm_remove(&m, JPM_HID, 6, 0) == 1);
    int p4 = jpm_add(&m, JPM_XINPUT, 9, 0, false);
    CHECK(m.pad[p4].port == 1);
}

static void test_jpm_overflow_pad_stays_on_port0(void) {
    jpm_t m; memset(&m, 0, sizeof m);
    jpm_add(&m, JPM_HID, 1, 0, false);                   // puerto 0
    jpm_add(&m, JPM_HID, 2, 0, false);                   // puerto 1
    int p3 = jpm_add(&m, JPM_HID, 3, 0, false);          // desborda -> 0
    CHECK(m.pad[p3].port == 0);
    CHECK(jpm_remove(&m, JPM_HID, 1, 0) == 0);    // se va el primero
    CHECK(m.pad[p3].port == 0);                   // el 3.o NO migra
    int p4 = jpm_add(&m, JPM_HID, 4, 0, false);          // el puerto 0 sigue ocupado (por el 3.o): desborda otra vez
    CHECK(m.pad[p4].port == 0);
}

static void test_jpm_port_out_or_and_autofire(void) {
    jpm_t m; memset(&m, 0, sizeof m);
    int p1 = jpm_add(&m, JPM_HID, 1, 0, false);          // puerto 0
    int p2 = jpm_add(&m, JPM_HID, 2, 0, false);          // puerto 1
    int p3 = jpm_add(&m, JPM_XINPUT, 3, 0, false);       // puerto 0 (desborda)
    CHECK(jpm_port_out(&m, 0, false) == 0 && jpm_port_out(&m, 1, false) == 0);
    jpm_set(&m, p1, R, 0);
    jpm_set(&m, p2, U | B, A);                    // B manual + A en autofire
    jpm_set(&m, p3, L, B);                        // izquierda + B en autofire
    CHECK(jpm_port_out(&m, 0, false) == (R | L));            // OR de los dos del puerto 0
    CHECK(jpm_port_out(&m, 0, true)  == (R | L | B));        // la fase alta suma el autofire
    CHECK(jpm_port_out(&m, 1, false) == (U | B));
    CHECK(jpm_port_out(&m, 1, true)  == (U | B | A));        // los dos puertos tienen su autofire
    // Quitar uno vuelve su puerto a reposo, sin tocar el otro
    jpm_remove(&m, JPM_HID, 2, 0);
    CHECK(jpm_port_out(&m, 1, true) == 0);
    CHECK(jpm_port_out(&m, 0, true) == (R | L | B));
}

static void test_jpm_table_full(void) {
    jpm_t m; memset(&m, 0, sizeof m);
    for(uint8_t d = 1; d <= JPM_MAX_PADS; d++) CHECK(jpm_add(&m, JPM_HID, d, 0, false) >= 0);
    CHECK(jpm_add(&m, JPM_HID, 99, 0, false) == -1);
    CHECK(jpm_count(&m) == JPM_MAX_PADS);
}

// Con raton montado el puerto 2 (indice 1) es suyo: ningun mando nuevo lo coge
static void test_jpm_mouse_keeps_port2_free(void) {
    jpm_t m; memset(&m, 0, sizeof m);
    int p1 = jpm_add(&m, JPM_HID, 1, 0, true);    // con raton desde el primero
    int p2 = jpm_add(&m, JPM_HID, 2, 0, true);
    int p3 = jpm_add(&m, JPM_XINPUT, 3, 0, true);
    CHECK(m.pad[p1].port == 0 && m.pad[p2].port == 0 && m.pad[p3].port == 0);
    jpm_set(&m, p1, R, 0);
    jpm_set(&m, p2, A, 0);
    CHECK(jpm_port_out(&m, 0, false) == (R | A));             // se suman (OR)
    CHECK(jpm_port_out(&m, 1, true) == 0);                    // el puerto 2 queda libre para el raton
    // Sin raton otra vez, el libre mas bajo con el 0 ocupado es el 1
    int p4 = jpm_add(&m, JPM_HID, 4, 0, false);
    CHECK(m.pad[p4].port == 1);
    // Un mando que ya estaba en el puerto 2 no se mueve al llegar un raton (la FPGA se lo come: se documenta)
    CHECK(jpm_add(&m, JPM_HID, 4, 0, true) == p4 && m.pad[p4].port == 1);
}

// Si el puerto 0 se queda sin mandos, los del 1 pasan al 0
static void test_jpm_compact(void) {
    jpm_t m; memset(&m, 0, sizeof m);
    CHECK(!jpm_compact(&m));                                   // vacio
    int p1 = jpm_add(&m, JPM_HID, 1, 0, false);                // puerto 0
    int p2 = jpm_add(&m, JPM_HID, 2, 0, false);                // puerto 1
    int p3 = jpm_add(&m, JPM_HID, 3, 0, false);                // puerto 0 (desborda)
    jpm_set(&m, p2, U, A);
    CHECK(!jpm_compact(&m));                                   // el 0 tiene mandos
    jpm_remove(&m, JPM_HID, 1, 0);
    CHECK(!jpm_compact(&m));                                   // el 3.o sigue en el 0
    jpm_remove(&m, JPM_HID, 3, 0);
    CHECK(jpm_compact(&m));                                    // el 0 vacio y el 2.o en el 1: pasa al 0
    CHECK(m.pad[p2].port == 0);
    CHECK(m.pad[p2].base == U && m.pad[p2].af == A);           // conserva lo que sostenia
    CHECK(jpm_port_out(&m, 0, true) == (U | A) && jpm_port_out(&m, 1, true) == 0);
    CHECK(!jpm_compact(&m));                                   // idempotente
    (void)p1; (void)p3;
    // Todos los del 1 pasan juntos (no hay forma de que sean varios sin el 0, pero que no se pierdan)
    jpm_t k; memset(&k, 0, sizeof k);
    k.pad[0].used = 1; k.pad[0].dev_addr = 1; k.pad[0].port = 1;
    k.pad[1].used = 1; k.pad[1].dev_addr = 2; k.pad[1].port = 1;
    CHECK(jpm_compact(&k) && k.pad[0].port == 0 && k.pad[1].port == 0);
}

// ----------------------------------------------------------------- ratones

static void test_mim(void) {
    mim_t m; memset(&m, 0, sizeof m);
    CHECK(mim_count(&m) == 0);
    CHECK(!mim_remove(&m, 4, 0));                              // no estaba
    CHECK(mim_add(&m, 4, 0));
    CHECK(mim_add(&m, 4, 0));                                  // repetido: sigue siendo uno
    CHECK(mim_count(&m) == 1);
    CHECK(mim_add(&m, 4, 1));                                  // otra interfaz del mismo dispositivo
    CHECK(mim_add(&m, 5, 0));
    CHECK(mim_count(&m) == 3);
    CHECK(mim_remove(&m, 4, 0));
    CHECK(mim_count(&m) == 2);                                 // quedan otros: el puerto 2 sigue siendo del raton
    CHECK(!mim_add(&m, 0, 0));                                 // dev_addr 0 no vale
    CHECK(mim_add(&m, 6, 0) && mim_add(&m, 7, 0));
    CHECK(!mim_add(&m, 8, 0));                                 // tabla llena (MIM_MAX)
    CHECK(mim_count(&m) == MIM_MAX);
    CHECK(mim_remove(&m, 6, 0) && mim_add(&m, 8, 0));          // el hueco liberado se reutiliza
}

int main(void) {
    test_kbm_set_basic();
    test_kbm_distinguishes_instances();
    test_kbm_count();
    test_kbm_per_kb_cap();
    test_kbm_merge_union();
    test_kbm_merge_empty();
    test_kbm_merge_overflow_deterministic();
    test_kbm_overflow_keeps_mods_of_late_keyboards();
    test_kbm_table_full_and_reuse();
    test_jpm_ports_by_mount_order();
    test_jpm_same_key_is_idempotent();
    test_jpm_remove_keeps_other_port();
    test_jpm_overflow_pad_stays_on_port0();
    test_jpm_port_out_or_and_autofire();
    test_jpm_table_full();
    test_jpm_mouse_keeps_port2_free();
    test_jpm_compact();
    test_mim();
    printf("test_kbd_merge: %d comprobaciones, %d fallos\n", g_checks, g_fail);
    return g_fail ? 1 : 0;
}
