#include "regs.h"
#include "uart.h"

int main(void) {
    // Simple reset verification: after reset the processor starts here.
    // Read a known register that should be at its reset value.
    unsigned int timer_ctrl = REG32(TIMER_CTRL);
    if (timer_ctrl != 0x0) {
        uart_puts("FAIL: TIMER_CTRL not reset\n");
        return 1;
    }
    uart_puts("PASS: Reset verification\n");
    return 0;
}
