/*
 * ============================================================================
 * File: timer_core.v
 * Project: Reliable Data Transport System SoC
 * Description: Bus-Independent General Purpose Timer / Counter Core
 * ============================================================================
 */

`timescale 1ns / 1ps
`default_nettype none

`include "timer_defines.vh"

module timer_core (
    input  wire        clk,
    input  wire        rst_n,          // Active-low synchronous reset

    // Register Control Inputs
    input  wire        ctrl_en,        // Timer enable
    input  wire        ctrl_reload,    // 1: Periodic auto-reload, 0: One-shot
    input  wire        ctrl_rst,       // Pulse: Reset counter to 0
    input  wire        ctrl_ie,        // Interrupt enable
    input  wire        ctrl_pwm_en,    // PWM enable

    // Counter / Compare Preload
    input  wire [31:0] timer_load_val, // Preload value for counter
    input  wire        timer_load_we,  // Strobe to load timer_load_val
    input  wire [31:0] compare_val,    // Compare threshold
    input  wire [15:0] prescaler_div,  // Prescaler divisor (0 = div by 1)

    // W1C Status Clear Inputs
    input  wire        clear_match,    // Clear match flag (write 1 to clear)
    input  wire        clear_ovf,      // Clear overflow flag (write 1 to clear)

    // Status Outputs
    output wire [31:0] counter_val_o,  // Current counter value
    output wire        running_o,      // Running status
    output wire        match_flag_o,   // Latched match status
    output wire        ovf_flag_o,     // Latched overflow status

    // Hardware Peripheral Signals
    output wire        match_pulse_o,  // Single-cycle match pulse
    output wire        timer_irq_o,    // Interrupt request to PIC
    output wire        pwm_out_o       // PWM output waveform
);

    reg [31:0] count_reg;
    reg [15:0] presc_cnt;
    reg        match_flag_reg;
    reg        ovf_flag_reg;
    reg        match_pulse_reg;
    reg        running_reg;
    reg        one_shot_done;
    reg        ctrl_en_prev;

    always @(posedge clk) begin
        if (!rst_n) begin
            count_reg       <= 32'd0;
            presc_cnt       <= 16'd0;
            match_flag_reg  <= 1'b0;
            ovf_flag_reg    <= 1'b0;
            match_pulse_reg <= 1'b0;
            running_reg     <= 1'b0;
            one_shot_done   <= 1'b0;
            ctrl_en_prev    <= 1'b0;
        end else begin
            match_pulse_reg <= 1'b0;
            ctrl_en_prev    <= ctrl_en;

            // Handle W1C status clears
            if (clear_match)
                match_flag_reg <= 1'b0;
            if (clear_ovf)
                ovf_flag_reg   <= 1'b0;

            // When enable goes from 0 -> 1, clear one_shot_done
            if (ctrl_en && !ctrl_en_prev) begin
                one_shot_done <= 1'b0;
            end

            // Manual counter load or reset
            if (ctrl_rst) begin
                count_reg     <= 32'd0;
                presc_cnt     <= prescaler_div;
                one_shot_done <= 1'b0;
            end else if (timer_load_we) begin
                count_reg     <= timer_load_val;
                one_shot_done <= 1'b0;
            end

            // Running logic
            if (!ctrl_en || one_shot_done) begin
                running_reg <= 1'b0;
                if (!ctrl_en)
                    presc_cnt <= prescaler_div;
            end else begin
                running_reg <= 1'b1;

                // Prescaler countdown
                if (presc_cnt == 16'd0) begin
                    presc_cnt <= prescaler_div;

                    // Counter match check (>= compare_val)
                    if (count_reg >= compare_val) begin
                        match_flag_reg  <= 1'b1;
                        match_pulse_reg <= 1'b1;

                        if (ctrl_reload) begin
                            count_reg <= 32'd0;
                        end else begin
                            // One-shot mode: halt
                            one_shot_done <= 1'b1;
                            running_reg   <= 1'b0;
                        end
                    end else if (count_reg == 32'hFFFF_FFFF) begin
                        ovf_flag_reg <= 1'b1;
                        count_reg    <= 32'd0;
                    end else begin
                        count_reg <= count_reg + 32'd1;
                    end
                end else begin
                    presc_cnt <= presc_cnt - 16'd1;
                end
            end
        end
    end

    assign counter_val_o = count_reg;
    assign running_o     = running_reg;
    assign match_flag_o  = match_flag_reg;
    assign ovf_flag_o    = ovf_flag_reg;
    assign match_pulse_o = match_pulse_reg;

    // Interrupt is active-high when match flag is set and interrupt is enabled
    assign timer_irq_o   = ctrl_ie && match_flag_reg;

    // PWM output: high when counter < compare_val and PWM is enabled
    assign pwm_out_o     = ctrl_pwm_en ? (count_reg < compare_val) : 1'b0;

endmodule

`default_nettype wire
