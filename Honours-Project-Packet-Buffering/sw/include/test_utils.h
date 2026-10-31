#ifndef TEST_UTILS_H
#define TEST_UTILS_H

#include "regs.h"
#include "uart.h"

static inline void test_pass(const char *msg) {
    uart_puts("PASS: ");
    uart_puts(msg);
    uart_puts("\n");
}

static inline void test_fail(const char *msg) {
    uart_puts("FAIL: ");
    uart_puts(msg);
    uart_puts("\n");
}

#endif // TEST_UTILS_H