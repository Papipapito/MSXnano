#ifndef PIO_STUB_H
#define PIO_STUB_H
#include <stdint.h>
#include <stdbool.h>

typedef unsigned int uint;
typedef int PIO;
#define pio0 0
#define pio1 1
typedef struct { int unused; } pio_program_t;

uint pio_add_program(PIO pio, const pio_program_t *program);
bool pio_sm_is_tx_fifo_full(PIO pio, uint sm);
void pio_sm_put(PIO pio, uint sm, uint32_t data);

#endif
