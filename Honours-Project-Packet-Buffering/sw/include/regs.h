#ifndef REGISTERS_H
#define REGISTERS_H

/* Base addresses as defined in the memory map */
#define M00_INSTR_RAM_BASE   0x00000000UL   /* Instruction RAM */
#define M01_DATA_RAM_BASE    0x00010000UL   /* Data RAM */
#define M02_UART_BASE        0x00020000UL   /* UART 16550 */
#define M03_TIMER_BASE       0x00021000UL   /* Timer / PWM */
#define M04_GPIO_BASE        0x00022000UL   /* GPIO */
#define M05_FIFO_BASE        0x00023000UL   /* Packet FIFO */
#define M06_CRC_BASE         0x00024000UL   /* CRC‑32 Engine */
#define M07_PKT_CNT_BASE     0x00025000UL   /* Packet Statistics Counter */

/* UART registers (offsets from M02_UART_BASE) */
#define UART_THR   (M02_UART_BASE + 0x00)   /* Transmit Holding Register */
#define UART_RHR   (M02_UART_BASE + 0x00)   /* Receive Holding Register (same offset) */
#define UART_IER   (M02_UART_BASE + 0x04)   /* Interrupt Enable Register */
#define UART_LCR   (M02_UART_BASE + 0x0C)   /* Line Control Register */
#define UART_LSR   (M02_UART_BASE + 0x14)   /* Line Status Register */

/* Timer registers  (offsets match timer_defines.vh)
 *   0x00 = CTRL      (RW)
 *   0x04 = STATUS    (RO/W1C)
 *   0x08 = VALUE     -- current counter value (RW)
 *   0x0C = COMPARE   -- compare threshold     (RW)
 *   0x10 = PRESCALER (RW)
 */
#define TIMER_CTRL    (M03_TIMER_BASE + 0x00)
#define TIMER_STATUS  (M03_TIMER_BASE + 0x04)
#define TIMER_COUNT   (M03_TIMER_BASE + 0x08)   /* was 0x04 - BUG FIX */
#define TIMER_COMPARE (M03_TIMER_BASE + 0x0C)   /* was 0x08 - BUG FIX */

/* GPIO registers */
#define GPIO_DATA   (M04_GPIO_BASE + 0x00)
#define GPIO_DIR    (M04_GPIO_BASE + 0x04)

/* FIFO registers */
#define FIFO_CTRL   (M05_FIFO_BASE + 0x00)
#define FIFO_STATUS (M05_FIFO_BASE + 0x04)
#define FIFO_DATA   (M05_FIFO_BASE + 0x08)

/* CRC registers */
#define CRC_CTRL    (M06_CRC_BASE + 0x00)
#define CRC_STATUS  (M06_CRC_BASE + 0x04)
#define CRC_DATA_IN (M06_CRC_BASE + 0x08)
#define CRC_RESULT  (M06_CRC_BASE + 0x0C)

/* Packet Counter registers */
#define PKT_CNT_RECV   (M07_PKT_CNT_BASE + 0x00)
#define PKT_CNT_PROC   (M07_PKT_CNT_BASE + 0x04)
#define PKT_CNT_ERR    (M07_PKT_CNT_BASE + 0x08)

/* Helper macros for memory‑mapped I/O */
#define REG32(addr) (*(volatile unsigned int *)(addr))

#endif /* REGISTERS_H */