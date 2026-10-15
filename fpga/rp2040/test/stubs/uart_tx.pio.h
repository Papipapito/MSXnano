#include "hardware/pio.h"
static const pio_program_t uart_tx_program = {0};
static inline void uart_tx_program_init(PIO pio, uint sm, uint offset, uint pin_tx, uint baud) {
    (void)pio; (void)sm; (void)offset; (void)pin_tx; (void)baud;
}
