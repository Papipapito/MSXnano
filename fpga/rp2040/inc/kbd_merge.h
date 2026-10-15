#ifndef KBD_MERGE_H
#define KBD_MERGE_H

/*
 * Logica pura de entrada del firmware del RP2040: sin SDK ni TinyUSB, para poder
 * probarla en el PC (ver test/). Tres puertos USB-A admiten DOS teclados y DOS
 * mandos a la vez; el FPGA solo ve UN teclado y DOS puertos de joystick.
 *
 *  - Teclados (kbm_*): cada teclado (dev_addr, instance) guarda SU modificador y
 *    SUS teclas. La UNION de todos es lo que se le pasa al motor de diferencias de
 *    usbin.c (kb_report_receive), que sigue siendo el unico que emite MAKE/BREAK.
 *    Sin esto dos teclados que alternan informes se pisan el estado y salen BREAKs
 *    falsos.
 *  - Mandos (jpm_*): HID y XInput comparten un registro. Por orden de montaje el
 *    primero va al puerto MSX 1 (0), el segundo al MSX 2 (1); del tercero en
 *    adelante se suman (OR) al puerto 0. Con un raton montado el puerto 2 es del
 *    raton (la FPGA se lo da al primer informe): los mandos nuevos van al 0. Si el
 *    puerto 0 se queda sin mandos, los del 1 pasan al 0. Cada mando guarda su capa
 *    "mantenida" y su capa de autofire; el byte de un puerto es el OR de los de sus
 *    mandos.
 *  - Ratones (mim_*): interfaces de raton montadas; el puerto 2 es del raton
 *    mientras quede alguna.
 */

#include <stdint.h>
#include <stdbool.h>
#include <string.h>

// ---------------------------------------------------------------------------
// Teclados
// ---------------------------------------------------------------------------
#define KBM_MAX_KB      8    // teclados (interfaces) a la vez; = keyboards[] de usbin.c
#define KBM_KEYS_PER_KB 16   // teclas que se guardan de cada teclado
#define KBM_UNION_MAX   16   // = sizeof(prev_keys) de usbin.c: lo que el motor admite

typedef struct {
    uint8_t dev_addr;                 // 0 = hueco libre (las direcciones USB reales son >= 1)
    uint8_t instance;
    uint8_t modifiers;                // byte de modificadores HID de ESTE teclado
    uint8_t nkeys;
    uint8_t keys[KBM_KEYS_PER_KB];    // usos HID pulsados: sin 0 ni repetidos, en orden de informe
} kbm_kb_t;

typedef struct {
    kbm_kb_t kb[KBM_MAX_KB];
} kbm_t;

static inline bool kbm_has(const uint8_t *list, uint8_t n, uint8_t usage) {
    for(uint8_t i = 0; i < n; i++) if(list[i] == usage) return true;
    return false;
}

// Hueco del teclado (dev_addr, instance), o -1.
static inline int kbm_find(const kbm_t *m, uint8_t dev_addr, uint8_t instance) {
    if(dev_addr == 0) return -1;
    for(int i = 0; i < KBM_MAX_KB; i++)
        if(m->kb[i].dev_addr == dev_addr && m->kb[i].instance == instance) return i;
    return -1;
}

// Teclados dados de alta.
static inline int kbm_count(const kbm_t *m) {
    int n = 0;
    for(int i = 0; i < KBM_MAX_KB; i++) if(m->kb[i].dev_addr != 0) n++;
    return n;
}

// Da de alta un teclado sin nada pulsado. Si ya estaba, devuelve su hueco sin
// tocarlo. -1 = tabla llena.
static inline int kbm_add(kbm_t *m, uint8_t dev_addr, uint8_t instance) {
    int i = kbm_find(m, dev_addr, instance);
    if(i >= 0 || dev_addr == 0) return i;
    for(i = 0; i < KBM_MAX_KB; i++) {
        if(m->kb[i].dev_addr == 0) {
            memset(&m->kb[i], 0, sizeof(m->kb[i]));
            m->kb[i].dev_addr = dev_addr;
            m->kb[i].instance = instance;
            return i;
        }
    }
    return -1;
}

// Da de baja un teclado: true si estaba dado de alta.
static inline bool kbm_remove(kbm_t *m, uint8_t dev_addr, uint8_t instance) {
    int i = kbm_find(m, dev_addr, instance);
    if(i < 0) return false;
    memset(&m->kb[i], 0, sizeof(m->kb[i]));
    return true;
}

// Guarda el informe de ESE teclado (ya con NKRO expandido a la lista plana de
// usos; 0 = hueco vacio). Lo da de alta si aun no lo estaba. Se quedan las
// KBM_KEYS_PER_KB primeras teclas del informe, sin repetidas. false = tabla llena.
static inline bool kbm_set(kbm_t *m, uint8_t dev_addr, uint8_t instance,
                           uint8_t modifiers, const uint8_t *keys, uint16_t len) {
    int i = kbm_add(m, dev_addr, instance);
    if(i < 0) return false;
    kbm_kb_t *k = &m->kb[i];
    k->modifiers = modifiers;
    k->nkeys = 0;
    for(uint16_t j = 0; j < len && k->nkeys < KBM_KEYS_PER_KB; j++) {
        uint8_t u = keys[j];
        if(u == 0 || kbm_has(k->keys, k->nkeys, u)) continue;
        k->keys[k->nkeys++] = u;
    }
    return true;
}

// Union de todos los teclados: OR de modificadores y teclas sin repetir, por
// orden de hueco y dentro de cada teclado por orden de informe. Si pasa de
// KBM_UNION_MAX se recorta por el final (determinista: los primeros se quedan).
// Devuelve el numero de teclas escritas en out_keys (>= KBM_UNION_MAX de sitio).
static inline uint8_t kbm_merge(const kbm_t *m, uint8_t *out_mods, uint8_t *out_keys) {
    uint8_t mods = 0, n = 0;
    for(int i = 0; i < KBM_MAX_KB; i++) {
        const kbm_kb_t *k = &m->kb[i];
        if(k->dev_addr == 0) continue;
        mods |= k->modifiers;
        for(uint8_t j = 0; j < k->nkeys && n < KBM_UNION_MAX; j++) {
            if(!kbm_has(out_keys, n, k->keys[j])) out_keys[n++] = k->keys[j];
        }
    }
    *out_mods = mods;
    return n;
}

// ---------------------------------------------------------------------------
// Mandos -> puertos MSX
// ---------------------------------------------------------------------------
#define JPM_MAX_PADS 8
#define JPM_PORTS    2   // 0 = puerto MSX 1, 1 = puerto MSX 2

#define JPM_HID      0   // gamepad/joystick HID generico
#define JPM_XINPUT   1   // mando XInput (driver vendorizado)

typedef struct {
    uint8_t used;
    uint8_t kind;        // JPM_HID | JPM_XINPUT
    uint8_t dev_addr;
    uint8_t instance;
    uint8_t port;        // puerto MSX asignado al montarlo; no cambia mientras siga montado
    uint8_t base;        // byte activo-alto mantenido: direcciones + fuego manual
    uint8_t af;          // bits de fuego (JOY_A/JOY_B) armados para autofire
} jpm_pad_t;

typedef struct {
    jpm_pad_t pad[JPM_MAX_PADS];
} jpm_t;

static inline int jpm_find(const jpm_t *m, uint8_t kind, uint8_t dev_addr, uint8_t instance) {
    for(int i = 0; i < JPM_MAX_PADS; i++)
        if(m->pad[i].used && m->pad[i].kind == kind &&
           m->pad[i].dev_addr == dev_addr && m->pad[i].instance == instance) return i;
    return -1;
}

static inline int jpm_count(const jpm_t *m) {
    int n = 0;
    for(int i = 0; i < JPM_MAX_PADS; i++) if(m->pad[i].used) n++;
    return n;
}

// Puerto para un mando nuevo: el libre mas bajo (sin ningun mando asignado); si
// estan todos ocupados, el 0. Con raton el puerto 1 (MSX 2) no esta disponible:
// el nuevo va al 0 y se suma (OR) a los que ya esten.
static inline uint8_t jpm_pick_port(const jpm_t *m, bool mouse) {
    for(uint8_t p = 0; p < (mouse ? 1 : JPM_PORTS); p++) {
        bool busy = false;
        for(int i = 0; i < JPM_MAX_PADS; i++)
            if(m->pad[i].used && m->pad[i].port == p) { busy = true; break; }
        if(!busy) return p;
    }
    return 0;
}

// Da de alta un mando (sin nada pulsado) y le asigna puerto (`mouse`: hay un raton
// montado). Si ya estaba, conserva su puerto y solo borra su estado. Devuelve su
// hueco, o -1 si la tabla esta llena.
static inline int jpm_add(jpm_t *m, uint8_t kind, uint8_t dev_addr, uint8_t instance, bool mouse) {
    int i = jpm_find(m, kind, dev_addr, instance);
    if(i < 0) {
        for(i = 0; i < JPM_MAX_PADS; i++) if(!m->pad[i].used) break;
        if(i == JPM_MAX_PADS) return -1;
        m->pad[i].port = jpm_pick_port(m, mouse);
    }
    m->pad[i].used = 1;
    m->pad[i].kind = kind;
    m->pad[i].dev_addr = dev_addr;
    m->pad[i].instance = instance;
    m->pad[i].base = 0;
    m->pad[i].af = 0;
    return i;
}

// Da de baja un mando. Devuelve el puerto que tenia, o -1 si no estaba dado de alta.
static inline int jpm_remove(jpm_t *m, uint8_t kind, uint8_t dev_addr, uint8_t instance) {
    int i = jpm_find(m, kind, dev_addr, instance);
    if(i < 0) return -1;
    int port = m->pad[i].port;
    memset(&m->pad[i], 0, sizeof(m->pad[i]));
    return port;
}

// Si el puerto 0 se ha quedado sin mandos y el 1 tiene alguno, pasa los del 1 al 0
// (el MSX 1 es el que leen los juegos de un jugador). true = ha movido alguno: el
// que llama debe volver a emitir los dos puertos, primero el 1 y luego el 0.
static inline bool jpm_compact(jpm_t *m) {
    bool p0 = false, p1 = false;
    for(int i = 0; i < JPM_MAX_PADS; i++) {
        if(!m->pad[i].used) continue;
        if(m->pad[i].port == 0) p0 = true; else p1 = true;
    }
    if(p0 || !p1) return false;
    for(int i = 0; i < JPM_MAX_PADS; i++)
        if(m->pad[i].used) m->pad[i].port = 0;
    return true;
}

// Guarda lo ultimo que informo el mando de su hueco `idx` (de jpm_add/jpm_find).
static inline void jpm_set(jpm_t *m, int idx, uint8_t base, uint8_t af) {
    m->pad[idx].base = base;
    m->pad[idx].af = af;
}

// Byte activo-alto de un puerto: OR de lo de sus mandos; la capa de autofire solo
// cuenta mientras la fase cuadrada esta alta.
static inline uint8_t jpm_port_out(const jpm_t *m, uint8_t port, bool af_phase) {
    uint8_t out = 0;
    for(int i = 0; i < JPM_MAX_PADS; i++) {
        if(!m->pad[i].used || m->pad[i].port != port) continue;
        out |= m->pad[i].base;
        if(af_phase) out |= m->pad[i].af;
    }
    return out;
}

// ---------------------------------------------------------------------------
// Ratones
// ---------------------------------------------------------------------------
#define MIM_MAX 4   // interfaces de raton a la vez

typedef struct {
    uint8_t dev_addr;                 // 0 = hueco libre
    uint8_t instance;
} mim_itf_t;

typedef struct {
    mim_itf_t itf[MIM_MAX];
} mim_t;

static inline int mim_count(const mim_t *m) {
    int n = 0;
    for(int i = 0; i < MIM_MAX; i++) if(m->itf[i].dev_addr != 0) n++;
    return n;
}

// Da de alta una interfaz de raton. false = tabla llena (o dev_addr 0); si ya estaba, true.
static inline bool mim_add(mim_t *m, uint8_t dev_addr, uint8_t instance) {
    if(dev_addr == 0) return false;
    for(int i = 0; i < MIM_MAX; i++)
        if(m->itf[i].dev_addr == dev_addr && m->itf[i].instance == instance) return true;
    for(int i = 0; i < MIM_MAX; i++) {
        if(m->itf[i].dev_addr == 0) {
            m->itf[i].dev_addr = dev_addr;
            m->itf[i].instance = instance;
            return true;
        }
    }
    return false;
}

// Da de baja una interfaz: true si estaba dada de alta.
static inline bool mim_remove(mim_t *m, uint8_t dev_addr, uint8_t instance) {
    if(dev_addr == 0) return false;
    for(int i = 0; i < MIM_MAX; i++) {
        if(m->itf[i].dev_addr == dev_addr && m->itf[i].instance == instance) {
            memset(&m->itf[i], 0, sizeof(m->itf[i]));
            return true;
        }
    }
    return false;
}

#endif
