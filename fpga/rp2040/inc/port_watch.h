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

#endif
