/*
 * ============================================================================
 * File: crc32_engine.v
 * Project: Reliable Data Transport System SoC
 * Description: High-speed, parameterized, parallel CRC-32 computation engine.
 *              Implements standard IEEE 802.3 Ethernet / ISO-HDLC CRC-32.
 *              Supports variable byte-lane enables (1 to 4 bytes per cycle).
 * ============================================================================
 */

`resetall
`timescale 1ns / 1ps
`default_nettype none

`include "crc_defines.vh"

module crc32_engine #(
    parameter [31:0] DEFAULT_POLY_REV = `CRC32_DEFAULT_POLY_REV,
    parameter [31:0] DEFAULT_INIT     = `CRC32_DEFAULT_INIT,
    parameter [31:0] DEFAULT_XOROUT   = `CRC32_DEFAULT_XOROUT
)(
    input  wire        clk,
    input  wire        rst_n,

    // Control signals
    input  wire        init,           // Re-initialize CRC accumulator
    input  wire        data_valid,     // Valid input data cycle
    input  wire [3:0]  byte_en,        // Byte lane enables [3:0]
    input  wire [31:0] data_in,        // Input data word (up to 4 bytes)

    // Configuration overrides (from registers)
    input  wire [31:0] poly_rev_in,    // Reflected polynomial (default 0xEDB88320)
    input  wire [31:0] init_val_in,    // Initial seed value (default 0xFFFFFFFF)

    // Outputs
    output wire [31:0] crc_out,        // Computed CRC with final XOR applied
    output wire [31:0] crc_state       // Raw accumulator state
);

    // ------------------------------------------------------------------------
    // Internal Registers
    // ------------------------------------------------------------------------
    reg [31:0] crc_reg;

    // ------------------------------------------------------------------------
    // Combinational Functions for CRC-32 Byte and Word Update
    // ------------------------------------------------------------------------
    function [31:0] update_byte;
        input [31:0] c_in;
        input [7:0]  d;
        input [31:0] poly;
        reg   [31:0] c;
        integer      i;
        begin
            c = c_in;
            for (i = 0; i < 8; i = i + 1) begin
                if ((c[0] ^ d[i]) == 1'b1)
                    c = (c >> 1) ^ poly;
                else
                    c = (c >> 1);
            end
            update_byte = c;
        end
    endfunction

    function [31:0] update_word;
        input [31:0] c_in;
        input [31:0] d;
        input [3:0]  be;
        input [31:0] poly;
        reg   [31:0] c;
        begin
            c = c_in;
            if (be[0]) c = update_byte(c, d[7:0],   poly);
            if (be[1]) c = update_byte(c, d[15:8],  poly);
            if (be[2]) c = update_byte(c, d[23:16], poly);
            if (be[3]) c = update_byte(c, d[31:24], poly);
            update_word = c;
        end
    endfunction

    // ------------------------------------------------------------------------
    // Next CRC Calculation
    // ------------------------------------------------------------------------
    wire [31:0] effective_poly = (poly_rev_in != 32'd0) ? poly_rev_in : DEFAULT_POLY_REV;
    wire [31:0] effective_init = (init_val_in != 32'd0) ? init_val_in : DEFAULT_INIT;

    wire [31:0] crc_current = init ? effective_init : crc_reg;
    wire [31:0] crc_next    = data_valid ? update_word(crc_current, data_in, byte_en, effective_poly)
                                         : crc_current;

    // ------------------------------------------------------------------------
    // Sequential State Update
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            crc_reg <= DEFAULT_INIT;
        end else begin
            if (init && !data_valid) begin
                crc_reg <= effective_init;
            end else if (data_valid) begin
                crc_reg <= crc_next;
            end
        end
    end

    // ------------------------------------------------------------------------
    // Output Assignment
    // ------------------------------------------------------------------------
    assign crc_state = crc_reg;
    assign crc_out   = crc_reg ^ DEFAULT_XOROUT;

endmodule

`resetall
