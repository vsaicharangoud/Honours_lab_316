/*
 * ============================================================================
 * File: crc_checker.v
 * Project: Reliable Data Transport System SoC
 * Description: Packet datapath and data integrity verification logic.
 *              Receives packet stream from Packet FIFO (AXI-Stream),
 *              computes CRC-32 on-the-fly, verifies against expected CRC,
 *              maintains packet statistics, and drives PASS/ERROR flags.
 * ============================================================================
 */

`resetall
`timescale 1ns / 1ps
`default_nettype none

`include "crc_defines.vh"

module crc_checker (
    input  wire        clk,
    input  wire        rst_n,

    // Control & Configuration (from AXI-Lite registers)
    input  wire        enable,             // Module enable
    input  wire        soft_reset,         // Soft reset pulse
    input  wire [1:0]  mode_config,        // Check mode (0: trailing, 1: register, 2: compute-only)
    input  wire        auto_clear,         // Auto-clear on start of new packet
    input  wire [31:0] poly_rev,           // Reflected polynomial
    input  wire [31:0] init_val,           // Initial seed
    input  wire [31:0] exp_crc_reg,        // Expected CRC from CPU register
    input  wire        exp_crc_we,         // Write enable for exp_crc_reg
    input  wire        clear_counters,     // Clear pass/error counters

    // CPU Manual Data Write Port
    input  wire        manual_data_valid,  // CPU manual word write
    input  wire [3:0]  manual_data_be,     // Byte enables for manual write
    input  wire [31:0] manual_data_in,     // Data word from CPU
    input  wire        manual_data_last,   // Finish manual packet

    // Streaming Packet Interface (Path A: From Packet FIFO)
    input  wire [31:0] s_axis_tdata,
    input  wire [3:0]  s_axis_tkeep,
    input  wire        s_axis_tlast,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,

    // Hardware Status Signals to SoC / CPU
    output reg         crc_pass_o,         // 1 = Packet verified successfully
    output reg         crc_error_o,        // 1 = Packet corrupted (mismatch)
    output reg         crc_done_o,         // 1 = Packet check complete
    output wire        crc_busy_o,         // 1 = Packet check in progress

    // Status & Result Registers to AXI-Lite
    output reg  [31:0] calc_crc_result_o,
    output reg  [31:0] exp_crc_result_o,
    output reg  [31:0] byte_count_o,
    output reg  [31:0] pass_count_o,
    output reg  [31:0] error_count_o,
    output wire        status_busy_o,
    output reg         status_done_o,
    output reg         status_pass_o,
    output reg         status_error_o
);

    // ------------------------------------------------------------------------
    // Count active bytes in tkeep
    // ------------------------------------------------------------------------
    function [2:0] count_bytes;
        input [3:0] be;
        begin
            count_bytes = (be[0] ? 3'd1 : 3'd0) +
                          (be[1] ? 3'd1 : 3'd0) +
                          (be[2] ? 3'd1 : 3'd0) +
                          (be[3] ? 3'd1 : 3'd0);
        end
    endfunction

    // ------------------------------------------------------------------------
    // Internal States
    // ------------------------------------------------------------------------
    localparam STATE_IDLE    = 2'd0;
    localparam STATE_STREAM  = 2'd1;
    localparam STATE_VERIFY  = 2'd2;

    reg [1:0] state;
    reg       packet_active;

    // Ready handshake: ready to accept whenever enabled
    assign s_axis_tready = enable && (state != STATE_VERIFY);
    wire stream_fire = s_axis_tvalid && s_axis_tready;

    // CRC Engine multiplexing
    wire        engine_init;
    wire        engine_data_valid;
    wire [3:0]  engine_byte_en;
    wire [31:0] engine_data_in;
    wire [31:0] engine_crc_out;
    wire [31:0] engine_crc_state;

    // Auto-init at packet start or soft reset
    wire start_of_new_packet = (state == STATE_IDLE) && stream_fire && auto_clear;
    assign engine_init = soft_reset || start_of_new_packet;

    // Select input source (Stream vs CPU manual port)
    assign engine_data_valid = stream_fire ? 1'b1 :
                               manual_data_valid ? 1'b1 : 1'b0;

    assign engine_byte_en    = stream_fire ? s_axis_tkeep :
                               manual_data_valid ? manual_data_be : 4'b0000;

    assign engine_data_in    = stream_fire ? s_axis_tdata :
                               manual_data_valid ? manual_data_in : 32'b0;

    // ------------------------------------------------------------------------
    // Instantiate Core CRC-32 Engine
    // ------------------------------------------------------------------------
    crc32_engine u_crc32_engine (
        .clk          (clk),
        .rst_n        (rst_n),
        .init         (engine_init),
        .data_valid   (engine_data_valid),
        .byte_en      (engine_byte_en),
        .data_in      (engine_data_in),
        .poly_rev_in  (poly_rev),
        .init_val_in  (init_val),
        .crc_out      (engine_crc_out),
        .crc_state    (engine_crc_state)
    );

    // ------------------------------------------------------------------------
    // Expected CRC Management
    // ------------------------------------------------------------------------
    reg [31:0] exp_crc_hold;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            exp_crc_hold <= 32'd0;
        end else if (exp_crc_we) begin
            exp_crc_hold <= exp_crc_reg;
        end
    end

    // ------------------------------------------------------------------------
    // Datapath Control & State Machine
    // ------------------------------------------------------------------------
    assign crc_busy_o   = (state == STATE_STREAM) || (state == STATE_VERIFY);
    assign status_busy_o = crc_busy_o;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state              <= STATE_IDLE;
            packet_active      <= 1'b0;
            crc_pass_o         <= 1'b0;
            crc_error_o        <= 1'b0;
            crc_done_o         <= 1'b0;
            status_done_o      <= 1'b0;
            status_pass_o      <= 1'b0;
            status_error_o     <= 1'b0;
            calc_crc_result_o  <= 32'd0;
            exp_crc_result_o   <= 32'd0;
            byte_count_o       <= 32'd0;
            pass_count_o       <= 32'd0;
            error_count_o      <= 32'd0;
        end else if (soft_reset) begin
            state              <= STATE_IDLE;
            packet_active      <= 1'b0;
            crc_pass_o         <= 1'b0;
            crc_error_o        <= 1'b0;
            crc_done_o         <= 1'b0;
            status_done_o      <= 1'b0;
            status_pass_o      <= 1'b0;
            status_error_o     <= 1'b0;
            byte_count_o       <= 32'd0;
        end else begin
            // Default single-cycle pulse outputs
            crc_pass_o  <= 1'b0;
            crc_error_o <= 1'b0;
            crc_done_o  <= 1'b0;

            // Clear statistics counters on demand
            if (clear_counters) begin
                pass_count_o  <= 32'd0;
                error_count_o <= 32'd0;
            end

            case (state)
                STATE_IDLE: begin
                    if (enable && stream_fire) begin
                        state         <= STATE_STREAM;
                        packet_active <= 1'b1;
                        status_done_o <= 1'b0;
                        byte_count_o  <= count_bytes(s_axis_tkeep);

                        if (s_axis_tlast) begin
                            state <= STATE_VERIFY;
                        end
                    end else if (enable && manual_data_valid) begin
                        byte_count_o <= byte_count_o + count_bytes(manual_data_be);
                        if (manual_data_last) begin
                            state <= STATE_VERIFY;
                        end
                    end
                end

                STATE_STREAM: begin
                    if (stream_fire) begin
                        byte_count_o <= byte_count_o + count_bytes(s_axis_tkeep);
                        if (s_axis_tlast) begin
                            state <= STATE_VERIFY;
                        end
                    end
                end

                STATE_VERIFY: begin
                    // Verification cycle: latch calculated and expected CRC
                    calc_crc_result_o <= engine_crc_out;
                    exp_crc_result_o  <= exp_crc_hold;

                    crc_done_o    <= 1'b1;
                    status_done_o <= 1'b1;

                    if (mode_config == `CRC_MODE_COMPUTE_ONLY) begin
                        // Compute-only: do not evaluate pass/error
                        status_pass_o  <= 1'b0;
                        status_error_o <= 1'b0;
                    end else begin
                        if (engine_crc_out == exp_crc_hold) begin
                            crc_pass_o    <= 1'b1;
                            status_pass_o  <= 1'b1;
                            status_error_o <= 1'b0;
                            pass_count_o   <= pass_count_o + 32'd1;
                        end else begin
                            crc_error_o    <= 1'b1;
                            status_pass_o  <= 1'b0;
                            status_error_o <= 1'b1;
                            error_count_o  <= error_count_o + 32'd1;
                        end
                    end

                    packet_active <= 1'b0;
                    state         <= STATE_IDLE;
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule

`resetall
