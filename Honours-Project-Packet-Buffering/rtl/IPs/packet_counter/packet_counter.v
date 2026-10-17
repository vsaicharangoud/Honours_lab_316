`timescale 1ns / 1ps
`default_nettype none

// Standard, bus-independent Packet Counter IP.
//
// Required project statistics:
//   - received packets
//   - processed packets
//   - CRC errors
//   - FIFO overflow events
//
// Integration strategy:
//   Connect this module to FIFO/CRC event pulses.
//   Use a separate AXI4-Lite/AHB-Lite wrapper to expose the registers to the CPU.
//   Keep all event inputs synchronous to clk. Events from another clock domain
//   must be synchronized safely in that domain before they reach this module.
//
// Event semantics:
//   Each input is an EVENT PULSE. One asserted cycle increments the corresponding
//   counter once. A level held high for N cycles increments N times.
//   packet_received should mean a complete packet was accepted, not merely one
//   FIFO word was written, unless the project defines each word as a packet.
//
// Control semantics:
//   rst: active-high synchronous reset.
//   enable: when 0, event counters do not increment.
//   clear: synchronous clear pulse; clears counters even when enable=0.
//   clear has priority over event increments.
//   Counters wrap modulo 2**COUNTER_WIDTH.

module packet_counter #(
    parameter integer COUNTER_WIDTH = 32
) (
    input  wire                     clk,
    input  wire                     rst,

    input  wire                     enable,
    input  wire                     clear,

    input  wire                     packet_received,
    input  wire                     packet_processed,
    input  wire                     crc_error,
    input  wire                     fifo_overflow,

    output reg  [COUNTER_WIDTH-1:0] received_count,
    output reg  [COUNTER_WIDTH-1:0] processed_count,
    output reg  [COUNTER_WIDTH-1:0] crc_error_count,
    output reg  [COUNTER_WIDTH-1:0] fifo_overflow_count
);

    localparam [COUNTER_WIDTH-1:0] COUNT_ONE =
        {{(COUNTER_WIDTH-1){1'b0}}, 1'b1};

    always @(posedge clk) begin
        if (rst) begin
            received_count      <= {COUNTER_WIDTH{1'b0}};
            processed_count     <= {COUNTER_WIDTH{1'b0}};
            crc_error_count     <= {COUNTER_WIDTH{1'b0}};
            fifo_overflow_count <= {COUNTER_WIDTH{1'b0}};
        end else if (clear) begin
            received_count      <= {COUNTER_WIDTH{1'b0}};
            processed_count     <= {COUNTER_WIDTH{1'b0}};
            crc_error_count     <= {COUNTER_WIDTH{1'b0}};
            fifo_overflow_count <= {COUNTER_WIDTH{1'b0}};
        end else if (enable) begin
            if (packet_received)
                received_count <= received_count + COUNT_ONE;

            if (packet_processed)
                processed_count <= processed_count + COUNT_ONE;

            if (crc_error)
                crc_error_count <= crc_error_count + COUNT_ONE;

            if (fifo_overflow)
                fifo_overflow_count <= fifo_overflow_count + COUNT_ONE;
        end
    end

endmodule

`default_nettype wire
