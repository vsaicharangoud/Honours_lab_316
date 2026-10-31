#ifndef UART_H
#define UART_H

#include "regs.h"

/* Simple polling UART transmit implementation */
static inline void uart_putc(char c) {
    // Wait for Transmit Holding Register empty (THRE) indicated by LSR bit 5 (0x20)
    while ((REG32(UART_LSR) & 0x20) == 0) {
        // spin
    }
    REG32(UART_THR) = (unsigned int)c;
}

static inline void uart_puts(const char *s) {
    while (*s) {
        uart_putc(*s++);
    }
}

static inline char uart_getc(void) {
    // Wait for Data Ready (DR) indicated by LSR bit 0 (0x01)
    while ((REG32(UART_LSR) & 0x01) == 0) {
        // spin
    }
    return (char)(REG32(UART_RHR) & 0xFF);
}

#endif // UART_H
