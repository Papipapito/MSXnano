/*
 * Pruebas de la decision pura de inc/port_watch.h (vigilante de los puertos raiz de
 * Pico-PIO-USB). Sin SDK ni TinyUSB; se ejecuta en el PC con run.ps1.
 */
#include <stdio.h>
#include <string.h>
#include "port_watch.h"

static int g_checks, g_fail;

#define CHECK(cond) do { g_checks++; if(!(cond)) { g_fail++; \
    printf("FALLO %s:%d: %s\n", __FILE__, __LINE__, #cond); } } while(0)

// Estado de un puerto colgado: connected + suspended, sin reset en curso, linea en SE0
#define STUCK(p) pw_step((p), true, true, false, true)

static void test_releases_after_passes(void) {
    uint8_t c = 0;
    for(int i = 1; i < PW_PASSES; i++) CHECK(!STUCK(&c));      // las primeras pasadas no sueltan
    CHECK(STUCK(&c));                                          // la PW_PASSES-esima si
    CHECK(c == 0);                                             // y el contador vuelve a empezar
    for(int i = 1; i < PW_PASSES; i++) CHECK(!STUCK(&c));      // si sigue asi, vuelve a hacer falta la serie entera
    CHECK(STUCK(&c));
}

static void test_any_good_condition_resets(void) {
    uint8_t c = 0;
    // Cada condicion sana (por separado) cuenta de nuevo desde cero
    struct { bool connected, suspended, in_reset, se0; } good[] = {
        { false, true,  false, true  },   // no hay conexion registrada
        { true,  false, false, true  },   // el puerto opera (la desconexion ya la vigila Pico-PIO-USB)
        { true,  true,  true,  true  },   // reset de bus en curso: SE0 a proposito
        { true,  true,  false, false },   // la linea tiene un dispositivo (J o K)
    };
    for(unsigned g = 0; g < sizeof good / sizeof good[0]; g++) {
        c = 0;
        for(int i = 1; i < PW_PASSES; i++) CHECK(!STUCK(&c));
        CHECK(c == PW_PASSES - 1);
        CHECK(!pw_step(&c, good[g].connected, good[g].suspended, good[g].in_reset, good[g].se0));
        CHECK(c == 0);
        for(int i = 1; i < PW_PASSES; i++) CHECK(!STUCK(&c));  // hay que volver a juntar la serie entera
        CHECK(STUCK(&c));
    }
}

static void test_ports_are_independent(void) {
    uint8_t c[3] = {0, 0, 0};
    for(int i = 1; i < PW_PASSES; i++) { CHECK(!STUCK(&c[0])); CHECK(!STUCK(&c[1])); }
    CHECK(!pw_step(&c[1], true, true, true, true));            // el puerto 1 entra en reset
    CHECK(STUCK(&c[0]));                                       // el 0 completa su serie
    CHECK(c[1] == 0 && c[2] == 0);
    CHECK(!STUCK(&c[1]));                                      // el 1 empieza de nuevo
}

// Un puerto sano (dispositivo enumerado: operando, linea con J) nunca se suelta
static void test_healthy_port_never_released(void) {
    uint8_t c = 0;
    for(int i = 0; i < 1000; i++) CHECK(!pw_step(&c, true, false, false, false));
    // ni uno que espera su turno de enumeracion con el dispositivo enchufado (linea con J)
    for(int i = 0; i < 1000; i++) CHECK(!pw_step(&c, true, true, false, false));
}

int main(void) {
    test_releases_after_passes();
    test_any_good_condition_resets();
    test_ports_are_independent();
    test_healthy_port_never_released();
    printf("test_port_watch: %d comprobaciones, %d fallos\n", g_checks, g_fail);
    return g_fail ? 1 : 0;
}
