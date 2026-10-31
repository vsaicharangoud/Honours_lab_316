#include "regs.h"
#include "uart.h"

int main(void) {
    // Timer basic operation test (TP-015)
    // Configure timer compare value to 0x00001000, enable timer, wait for match.
    REG32(TIMER_COMPARE) = 0x00001000UL;
    REG32(TIMER_CTRL) = 0x1; // enable
    /* BUG FIX: Using != risks missing the exact match value as the counter
     * increments every clock.  Using < guarantees we exit when the counter
     * reaches or surpasses the compare value.
     */
    while (REG32(TIMER_COUNT) < REG32(TIMER_COMPARE)) {
        // spin
    }
    uart_puts("PASS: Timer match reached\n");
    return 0;
}
