/*
 * ============================================================================
 * File: gpio_core.v
 * Project: Reliable Data Transport System SoC
 * Description: Bus-Independent 32-bit General Purpose I/O Core with Interrupts
 * ============================================================================
 */

`timescale 1ns / 1ps
`default_nettype none

`include "gpio_defines.vh"

module gpio_core #(
    parameter integer GPIO_WIDTH = 32
)(
    input  wire                  clk,
    input  wire                  rst_n,          // Active-low synchronous reset

    // Register Interface Inputs
    input  wire [GPIO_WIDTH-1:0] data_out_write, // Write data for DATA_OUT
    input  wire                  data_out_we,    // Write enable for DATA_OUT
    input  wire [GPIO_WIDTH-1:0] dir_write,      // Write data for DIR
    input  wire                  dir_we,         // Write enable for DIR
    input  wire [GPIO_WIDTH-1:0] set_pulse,      // Atomic set strobe bits
    input  wire [GPIO_WIDTH-1:0] clear_pulse,    // Atomic clear strobe bits

    input  wire [GPIO_WIDTH-1:0] int_en_write,   // Interrupt enable per pin
    input  wire                  int_en_we,
    input  wire [GPIO_WIDTH-1:0] int_type_write, // 0=edge, 1=level
    input  wire                  int_type_we,
    input  wire [GPIO_WIDTH-1:0] int_pol_write,  // 0=rising/high, 1=falling/low
    input  wire                  int_pol_we,
    input  wire [GPIO_WIDTH-1:0] int_stat_clear, // W1C clear strobes

    // Register Read Outputs
    output wire [GPIO_WIDTH-1:0] data_in_o,      // Synchronized input pins
    output wire [GPIO_WIDTH-1:0] data_out_o,     // Current output register
    output wire [GPIO_WIDTH-1:0] dir_o,          // Direction register
    output wire [GPIO_WIDTH-1:0] int_en_o,
    output wire [GPIO_WIDTH-1:0] int_type_o,
    output wire [GPIO_WIDTH-1:0] int_pol_o,
    output wire [GPIO_WIDTH-1:0] int_stat_o,     // Pending interrupt status

    // Hardware Peripheral Pins
    input  wire [GPIO_WIDTH-1:0] gpio_i,         // External physical inputs
    output wire [GPIO_WIDTH-1:0] gpio_o,         // External physical outputs
    output wire [GPIO_WIDTH-1:0] gpio_oe,        // Tristate direction (1=out, 0=in)
    output wire                  gpio_irq_o      // Aggregated interrupt to PIC
);

    // 2-stage input synchronizer to avoid CDC metastability
    reg [GPIO_WIDTH-1:0] sync_ff1;
    reg [GPIO_WIDTH-1:0] sync_ff2;
    reg [GPIO_WIDTH-1:0] sync_ff2_prev;

    reg [GPIO_WIDTH-1:0] reg_data_out;
    reg [GPIO_WIDTH-1:0] reg_dir;
    reg [GPIO_WIDTH-1:0] reg_int_en;
    reg [GPIO_WIDTH-1:0] reg_int_type;
    reg [GPIO_WIDTH-1:0] reg_int_pol;
    reg [GPIO_WIDTH-1:0] reg_int_stat;

    integer i;

    // Synchronizer & Edge Detection
    always @(posedge clk) begin
        if (!rst_n) begin
            sync_ff1      <= {GPIO_WIDTH{1'b0}};
            sync_ff2      <= {GPIO_WIDTH{1'b0}};
            sync_ff2_prev <= {GPIO_WIDTH{1'b0}};
        end else begin
            sync_ff1      <= gpio_i;
            sync_ff2      <= sync_ff1;
            sync_ff2_prev <= sync_ff2;
        end
    end

    // Core Register Update and Interrupt Logic
    always @(posedge clk) begin
        if (!rst_n) begin
            reg_data_out <= {GPIO_WIDTH{1'b0}};
            reg_dir      <= {GPIO_WIDTH{1'b0}}; // Default all inputs
            reg_int_en   <= {GPIO_WIDTH{1'b0}};
            reg_int_type <= {GPIO_WIDTH{1'b0}};
            reg_int_pol  <= {GPIO_WIDTH{1'b0}};
            reg_int_stat <= {GPIO_WIDTH{1'b0}};
        end else begin
            // Data Out register update
            if (data_out_we) begin
                reg_data_out <= data_out_write;
            end else begin
                // Atomic bit set / clear
                reg_data_out <= (reg_data_out | set_pulse) & (~clear_pulse);
            end

            // Direction register update
            if (dir_we)
                reg_dir <= dir_write;

            // Interrupt configuration updates
            if (int_en_we)
                reg_int_en <= int_en_write;
            if (int_type_we)
                reg_int_type <= int_type_write;
            if (int_pol_we)
                reg_int_pol <= int_pol_write;

            // Handle W1C interrupt status clear
            reg_int_stat <= reg_int_stat & (~int_stat_clear);

            // Interrupt generation per pin
            for (i = 0; i < GPIO_WIDTH; i = i + 1) begin
                if (reg_int_en[i]) begin
                    if (reg_int_type[i] == 1'b0) begin
                        // Edge-triggered: 0 = rising edge, 1 = falling edge
                        if (reg_int_pol[i] == 1'b0) begin
                            if (sync_ff2[i] && !sync_ff2_prev[i])
                                reg_int_stat[i] <= 1'b1;
                        end else begin
                            if (!sync_ff2[i] && sync_ff2_prev[i])
                                reg_int_stat[i] <= 1'b1;
                        end
                    end else begin
                        // Level-triggered: 0 = active high, 1 = active low
                        if (reg_int_pol[i] == 1'b0) begin
                            if (sync_ff2[i])
                                reg_int_stat[i] <= 1'b1;
                        end else begin
                            if (!sync_ff2[i])
                                reg_int_stat[i] <= 1'b1;
                        end
                    end
                end
            end
        end
    end

    assign data_in_o   = sync_ff2;
    assign data_out_o  = reg_data_out;
    assign dir_o       = reg_dir;
    assign int_en_o    = reg_int_en;
    assign int_type_o  = reg_int_type;
    assign int_pol_o   = reg_int_pol;
    assign int_stat_o  = reg_int_stat;

    // Physical pin drives
    assign gpio_o      = reg_data_out;
    assign gpio_oe     = reg_dir;

    // Aggregated interrupt output
    assign gpio_irq_o  = |(reg_int_stat & reg_int_en);

endmodule

`default_nettype wire
