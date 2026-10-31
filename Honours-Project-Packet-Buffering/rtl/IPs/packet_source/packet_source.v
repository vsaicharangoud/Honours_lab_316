/*
 * ============================================================================
 * File: packet_source.v
 * Project: Reliable Data Transport System SoC
 * Description: External Packet Source Streaming IP (AXI-Stream Master)
 *              Feeds the Packet FIFO (s_axis_*) with verified or corrupt packets.
 *
 * Architecture Reference: Section 2.11
 *   Packet Source -> Packet FIFO -> CRC Checker
 *
 * Features:
 *   - 32-bit AXI-Stream Master interface (tdata, tkeep, tlast, tvalid, tready)
 *   - Programmable packet length and inter-packet gap
 *   - Error injection control (injects bad data/CRC to test CRC checker)
 *   - Hardware packet sent pulse (packet_sent_o) to monitor transactions
 * ============================================================================
 */

`resetall
`timescale 1ns / 1ps
`default_nettype none

module packet_source #(
    parameter integer DATA_WIDTH = 32,
    parameter integer DEFAULT_PKT_WORDS = 4
)(
    input  wire                  clk,
    input  wire                  rst_n,

    // Control & Configuration
    input  wire                  enable,         // Continuous or single generator enable
    input  wire                  trigger_pulse,  // Manual trigger for single packet transmission
    input  wire [15:0]           pkt_words,      // Packet length in 32-bit words (>= 1)
    input  wire [7:0]            inter_pkt_gap,  // Idle cycles between packets
    input  wire                  inject_error,   // 1: Invert payload to trigger CRC failure

    // AXI-Stream Master Interface (Connects to Packet FIFO s_axis_*)
    output reg  [DATA_WIDTH-1:0] m_axis_tdata,
    output reg  [3:0]            m_axis_tkeep,
    output reg                   m_axis_tlast,
    output reg                   m_axis_tvalid,
    input  wire                  m_axis_tready,

    // Event Outputs
    output reg                   packet_sent_o,  // Single-cycle pulse upon packet completion
    output wire                  busy_o          // High while packet stream is active
);

    localparam [1:0]
        ST_IDLE = 2'd0,
        ST_SEND = 2'd1,
        ST_GAP  = 2'd2;

    reg [1:0]  state;
    reg [15:0] word_idx;
    reg [15:0] target_words;
    reg [7:0]  gap_cnt;
    reg [15:0] pkt_seq;

    assign busy_o = (state != ST_IDLE);

    always @(posedge clk) begin
        if (!rst_n) begin
            state         <= ST_IDLE;
            word_idx      <= 16'd0;
            target_words  <= 16'd0;
            gap_cnt       <= 8'd0;
            pkt_seq       <= 16'd0;
            m_axis_tdata  <= {DATA_WIDTH{1'b0}};
            m_axis_tkeep  <= 4'hF;
            m_axis_tlast  <= 1'b0;
            m_axis_tvalid <= 1'b0;
            packet_sent_o <= 1'b0;
        end else begin
            packet_sent_o <= 1'b0;

            case (state)
                ST_IDLE: begin
                    m_axis_tvalid <= 1'b0;
                    m_axis_tlast  <= 1'b0;
                    word_idx      <= 16'd0;

                    if (enable || trigger_pulse) begin
                        target_words  <= (pkt_words > 16'd0) ? pkt_words : DEFAULT_PKT_WORDS[15:0];
                        state         <= ST_SEND;
                        pkt_seq       <= pkt_seq + 16'd1;

                        // Prepare Word 0
                        m_axis_tvalid <= 1'b1;
                        m_axis_tkeep  <= 4'hF;
                        m_axis_tlast  <= ((pkt_words == 16'd1) || (pkt_words == 16'd0 && DEFAULT_PKT_WORDS == 1));
                        m_axis_tdata  <= inject_error ? {16'hDEAD, pkt_seq} : {16'hA5A5, pkt_seq};
                    end
                end

                ST_SEND: begin
                    m_axis_tvalid <= 1'b1;

                    // Transaction handshake
                    if (m_axis_tvalid && m_axis_tready) begin
                        if (m_axis_tlast) begin
                            // Finished this packet
                            m_axis_tvalid <= 1'b0;
                            m_axis_tlast  <= 1'b0;
                            packet_sent_o <= 1'b1;

                            if (inter_pkt_gap > 8'd0) begin
                                gap_cnt <= inter_pkt_gap;
                                state   <= ST_GAP;
                            end else if (enable) begin
                                // Immediately start next packet
                                word_idx     <= 16'd0;
                                pkt_seq      <= pkt_seq + 16'd1;
                                m_axis_tvalid<= 1'b1;
                                m_axis_tkeep <= 4'hF;
                                m_axis_tlast <= (target_words == 16'd1);
                                m_axis_tdata <= inject_error ? {16'hDEAD, pkt_seq + 16'd1} : {16'hA5A5, pkt_seq + 16'd1};
                                state        <= ST_SEND;
                            end else begin
                                state <= ST_IDLE;
                            end
                        end else begin
                            // Next word in packet
                            word_idx <= word_idx + 16'd1;
                            m_axis_tdata <= {pkt_seq, (word_idx + 16'd1)};
                            m_axis_tkeep <= 4'hF;
                            m_axis_tlast <= (word_idx + 16'd2 == target_words);
                        end
                    end
                end

                ST_GAP: begin
                    m_axis_tvalid <= 1'b0;
                    m_axis_tlast  <= 1'b0;

                    if (gap_cnt > 8'd1) begin
                        gap_cnt <= gap_cnt - 8'd1;
                    end else begin
                        if (enable) begin
                            word_idx      <= 16'd0;
                            pkt_seq       <= pkt_seq + 16'd1;
                            m_axis_tvalid <= 1'b1;
                            m_axis_tkeep  <= 4'hF;
                            m_axis_tlast  <= (target_words == 16'd1);
                            m_axis_tdata  <= inject_error ? {16'hDEAD, pkt_seq + 16'd1} : {16'hA5A5, pkt_seq + 16'd1};
                            state         <= ST_SEND;
                        end else begin
                            state <= ST_IDLE;
                        end
                    end
                end
            endcase
        end
    end

endmodule

`default_nettype wire
