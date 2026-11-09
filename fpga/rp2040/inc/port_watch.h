#ifndef PORT_WATCH_H
#define PORT_WATCH_H

/*
 * Vigilante de los puertos raiz de Pico-PIO-USB (portadora): decision pura, sin SDK, para
 * probarla en el PC (ver test/). La lectura de los registros va en main.c.
 *
 * Pico-PIO-USB marca un puerto connected+suspended al detectar la conexion y a partir de ahi
 * solo vigila la desconexion en los puertos NO suspendidos (y solo busca una conexion nueva
 * en los NO connected). TinyUSB, si al acabar el antirrebote (150 ms) la linea esta en SE0,
 * aborta la enumeracion sin reiniciar el puerto. Un dispositivo que se saca en esa ventana
 * deja el puerto connected+suspended con la linea en SE0 para siempre: no vuelve a generar
 * attach hasta apagar y encender. Con tres puertos la ventana se alarga (un attach diferido
 * espera a las enumeraciones que lleva delante).
 *
 * Un puerto en ese estado de verdad sigue connected+suspended+SE0 mientras no haya un
 * reset de bus en curso (que fuerza SE0 a proposito y se reconoce porque el pin D+ lleva el
 * habilitador de salida forzado), y lo sigue estando en cuanto TinyUSB abandona. Se pide que
 * se repita PW_PASSES pasadas seguidas para no pisar el antirrebote ni un reset que acaba de
 * empezar: pw_step() dice cuando hay que soltar el puerto (connected = false).
 */

#include <stdint.h>
#include <stdbool.h>

#define PW_INTERVAL_US 100000ull   // cada cuanto se mira (100 ms)
#define PW_PASSES      3           // pasadas seguidas en SE0 antes de soltar el puerto (~300 ms)

// Una pasada para un puerto. `passes` es su contador (empieza en 0). true = soltar el puerto.
static inline bool pw_step(uint8_t *passes, bool connected, bool suspended, bool in_reset, bool se0) {
    if(!(connected && suspended && !in_reset && se0)) {
        *passes = 0;
        return false;
    }
    if(++*passes < PW_PASSES) return false;
    *passes = 0;
    return true;
}

// Segunda regla: un puerto connected, NO suspendido, con la linea fuera de SE0 y sin ningun
// dispositivo montado en el durante PW_STUCK_PASSES pasadas = la enumeracion fallo (TinyUSB 0.21
// no la reintenta y Pico-PIO-USB no genera otro attach). Pasa en frio con teclados que tardan en
// arrancar (AJAZZ AK33). Se suelta el puerto para que vuelva a detectarse, como mucho
// PW_STUCK_MAX veces por conexion (el contador se reinicia al montar o al quedar en SE0).
#define PW_STUCK_PASSES 30         // ~3 s
#define PW_STUCK_MAX    5

typedef struct { uint8_t passes; uint8_t tries; } pw_stuck_t;

static inline bool pw_stuck_step(pw_stuck_t *st, bool connected, bool suspended, bool in_reset, bool se0, bool mounted) {
    if(mounted || se0) { st->passes = 0; st->tries = 0; return false; }   // montado o desenchufado: nueva conexion
    if(!connected) { st->passes = 0; return false; }                    // (los intentos se conservan)
    if(suspended || in_reset || st->tries >= PW_STUCK_MAX) { st->passes = 0; return false; }
    if(++st->passes < PW_STUCK_PASSES) return false;
    st->passes = 0;
    st->tries++;
    return true;
}

#endif
