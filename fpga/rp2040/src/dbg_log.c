// Registro de depuracion por CDC (portadora MSXnano v2). Ver inc/dbg_log.h.
#include "dbg_log.h"

#if MSXNANO_DEBUG_CDC

#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include "tusb.h"

// Anillo de 2 KB (potencia de 2): conserva el arranque mientras nadie abre el terminal.
#define DBG_RING_SIZE 2048u
#define DBG_RING_MASK (DBG_RING_SIZE - 1u)

static uint8_t  s_ring[DBG_RING_SIZE];
static uint32_t s_head = 0;    // proximo byte a escribir (contador sin envolver)
static uint32_t s_tail = 0;    // proximo byte a volcar

static inline void ring_put(uint8_t c) {
    s_ring[s_head++ & DBG_RING_MASK] = c;
    if (s_head - s_tail > DBG_RING_SIZE) s_tail = s_head - DBG_RING_SIZE;   // pierde lo mas antiguo
}

void dbg_printf(const char *fmt, ...) {
    static char line[128];   // estatica: un solo nucleo, sin reentrada
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(line, sizeof(line), fmt, ap);
    va_end(ap);
    if (n <= 0) return;
    if (n > (int)sizeof(line) - 1) n = (int)sizeof(line) - 1;
    for (int i = 0; i < n; i++) {
        if (line[i] == '\n' && (i == 0 || line[i - 1] != '\r')) ring_put('\r');
        ring_put((uint8_t)line[i]);
    }
}

void dbg_task(void) {
    tud_task();
    if (!tud_cdc_connected()) return;      // sin terminal (DTR) el texto se queda en el anillo
    bool wrote = false;
    while (s_tail != s_head) {
        uint32_t avail = tud_cdc_write_available();
        if (avail == 0) break;
        uint32_t pos   = s_tail & DBG_RING_MASK;
        uint32_t chunk = s_head - s_tail;
        if (chunk > DBG_RING_SIZE - pos) chunk = DBG_RING_SIZE - pos;   // hasta el final del anillo
        if (chunk > avail) chunk = avail;
        uint32_t done = tud_cdc_write(&s_ring[pos], chunk);
        if (done == 0) break;
        s_tail += done;
        wrote = true;
    }
    if (wrote) tud_cdc_write_flush();
}

#endif
