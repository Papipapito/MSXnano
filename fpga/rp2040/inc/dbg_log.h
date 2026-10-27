#ifndef DBG_LOG_H
#define DBG_LOG_H

// Registro de depuracion por el USB-C de la Zero (portadora MSXnano v2, solo con
// MSXNANO_DEBUG_CDC). El puerto USB-C es un dispositivo CDC (TinyUSB device en el rhport 0)
// mientras el host va por PIO-USB; se abre con cualquier terminal serie (la velocidad da igual).
//
//   dbg_printf(fmt, ...)  escribe en un anillo propio y NUNCA bloquea; si el anillo se llena
//                         pierde lo mas antiguo. Lo vuelca dbg_task() cuando hay terminal.
//   dbg_task()            tud_task() + vuelco del anillo al CDC. Llamar en cada vuelta del bucle.
//
// Sin MSXNANO_DEBUG_CDC los dos compilan a nada (los argumentos no se evaluan).
// Solo desde el nucleo que ejecuta tuh_task (no desde IRQ).

#ifndef MSXNANO_DEBUG_CDC
#define MSXNANO_DEBUG_CDC 0
#endif

#if MSXNANO_DEBUG_CDC

#ifdef __cplusplus
extern "C" {
#endif

void dbg_printf(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
void dbg_task(void);

#ifdef __cplusplus
}
#endif

#else

#define dbg_printf(...)   ((void)0)
#define dbg_task()        ((void)0)

#endif

#endif
