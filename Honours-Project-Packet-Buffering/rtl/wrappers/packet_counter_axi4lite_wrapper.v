`timescale 1ns / 1ps
`default_nettype none

// AXI4-Lite register wrapper for the bus-independent packet_counter module.
//
// Connect this module to the SoC AXI4-Lite subordinate port assigned to the
// Packet Counter (the interconnect decodes the peripheral base address).
// AXI addresses are treated as local offsets within that decoded address window.
//
// Register map (32-bit accesses):
//   0x00 CONTROL: bit 0 = enable (RW); write bit 1 = 1 to clear all counters
//   0x04 STATUS : bit 0 = enabled; bit 1 = any counter is nonzero
//   0x08 RX_COUNT       (RO)
//   0x0C PROCESSED_COUNT (RO)
//   0x10 CRC_ERROR_COUNT (RO)
//   0x14 FIFO_OVERFLOW_COUNT (RO)
//
// Only single-beat AXI4-Lite accesses are supported (AXI4-Lite has no bursts).
// Unaligned and unmapped accesses return SLVERR.
// Event inputs must be one-cycle pulses synchronous to aclk. Synchronize any
// FIFO/CRC events crossing clock domains before connecting them here.

module packet_counter_axi4lite_wrapper #(
    parameter integer ADDR_WIDTH = 32,
    parameter integer COUNTER_WIDTH = 32
) (
    input  wire                  aclk,
    input  wire                  aresetn, // AXI active-low reset

    // Packet event pulses
    input  wire                  packet_received,
    input  wire                  packet_processed,
    input  wire                  crc_error,
    input  wire                  fifo_overflow,

    // AXI4-Lite Write Address
    input  wire [ADDR_WIDTH-1:0] s_axi_awaddr,
    input  wire                  s_axi_awvalid,
    output wire                  s_axi_awready,

    // AXI4-Lite Write Data
    input  wire [31:0]           s_axi_wdata,
    input  wire [3:0]            s_axi_wstrb,
    input  wire                  s_axi_wvalid,
    output wire                  s_axi_wready,

    // AXI4-Lite Write Response
    output reg  [1:0]            s_axi_bresp,
    output reg                   s_axi_bvalid,
    input  wire                  s_axi_bready,

    // AXI4-Lite Read Address
    input  wire [ADDR_WIDTH-1:0] s_axi_araddr,
    input  wire                  s_axi_arvalid,
    output wire                  s_axi_arready,

    // AXI4-Lite Read Data/Response
    output reg  [31:0]            s_axi_rdata,
    output reg  [1:0]             s_axi_rresp,
    output reg                    s_axi_rvalid,
    input  wire                   s_axi_rready
);

    localparam [7:0] REG_CONTROL       = 8'h00;
    localparam [7:0] REG_STATUS        = 8'h04;
    localparam [7:0] REG_RX_COUNT      = 8'h08;
    localparam [7:0] REG_PROCESSED     = 8'h0C;
    localparam [7:0] REG_CRC_ERRORS    = 8'h10;
    localparam [7:0] REG_FIFO_OVERFLOW = 8'h14;

    localparam [1:0] RESP_OKAY   = 2'b00;
    localparam [1:0] RESP_SLVERR = 2'b10;

    reg aw_pending;
    reg w_pending;
    reg [ADDR_WIDTH-1:0] awaddr_hold;
    reg [31:0] wdata_hold;
    reg [3:0] wstrb_hold;

    reg enable_reg;
    reg clear_pulse;

    wire core_enable;
    wire [COUNTER_WIDTH-1:0] received_count;
    wire [COUNTER_WIDTH-1:0] processed_count;
    wire [COUNTER_WIDTH-1:0] crc_error_count;
    wire [COUNTER_WIDTH-1:0] fifo_overflow_count;

    wire aw_handshake = s_axi_awvalid && s_axi_awready;
    wire w_handshake  = s_axi_wvalid  && s_axi_wready;
    wire write_complete = (aw_pending || aw_handshake) &&
                          (w_pending || w_handshake) &&
                          !s_axi_bvalid;

    wire [ADDR_WIDTH-1:0] write_addr = aw_pending ? awaddr_hold : s_axi_awaddr;
    wire [31:0] write_data = w_pending ? wdata_hold : s_axi_wdata;
    wire [3:0] write_strb = w_pending ? wstrb_hold : s_axi_wstrb;
    wire [7:0] write_offset = write_addr[7:0];

    assign s_axi_awready = !aw_pending && !s_axi_bvalid;
    assign s_axi_wready  = !w_pending  && !s_axi_bvalid;
    assign s_axi_arready = !s_axi_rvalid;

    // Underlying standard counter core.
    packet_counter #(
        .COUNTER_WIDTH(COUNTER_WIDTH)
    ) u_packet_counter (
        .clk(aclk),
        .rst(!aresetn),
        .enable(enable_reg),
        .clear(clear_pulse),
        .packet_received(packet_received),
        .packet_processed(packet_processed),
        .crc_error(crc_error),
        .fifo_overflow(fifo_overflow),
        .received_count(received_count),
        .processed_count(processed_count),
        .crc_error_count(crc_error_count),
        .fifo_overflow_count(fifo_overflow_count)
    );

    // AXI4-Lite write channel handling. AW and W may arrive in either order.
    always @(posedge aclk) begin
        if (!aresetn) begin
            aw_pending <= 1'b0;
            w_pending <= 1'b0;
            awaddr_hold <= {ADDR_WIDTH{1'b0}};
            wdata_hold <= 32'b0;
            wstrb_hold <= 4'b0;
            enable_reg <= 1'b0;
            clear_pulse <= 1'b0;
            s_axi_bresp <= RESP_OKAY;
            s_axi_bvalid <= 1'b0;
        end else begin
            clear_pulse <= 1'b0;

            if (aw_handshake) begin
                aw_pending <= 1'b1;
                awaddr_hold <= s_axi_awaddr;
            end

            if (w_handshake) begin
                w_pending <= 1'b1;
                wdata_hold <= s_axi_wdata;
                wstrb_hold <= s_axi_wstrb;
            end

            if (write_complete) begin
                // Address and data are captured independently. When a channel
                // handshakes this cycle, use its live input; otherwise use hold.
                if (write_addr[1:0] != 2'b00) begin
                    s_axi_bresp <= RESP_SLVERR;
                end else begin
                    case (write_offset)
                        REG_CONTROL: begin
                            if (write_strb[0]) begin
                                enable_reg <= write_data[0];
                                if (write_data[1])
                                    clear_pulse <= 1'b1;
                            end
                            s_axi_bresp <= RESP_OKAY;
                        end
                        default: begin
                            // STATUS and counters are read-only; unknown offsets
                            // are unmapped.
                            s_axi_bresp <= RESP_SLVERR;
                        end
                    endcase
                end
                s_axi_bvalid <= 1'b1;
                aw_pending <= 1'b0;
                w_pending <= 1'b0;
            end

            if (s_axi_bvalid && s_axi_bready)
                s_axi_bvalid <= 1'b0;
        end
    end

    // AXI4-Lite read channel: one outstanding read response.
    always @(posedge aclk) begin
        if (!aresetn) begin
            s_axi_rdata <= 32'b0;
            s_axi_rresp <= RESP_OKAY;
            s_axi_rvalid <= 1'b0;
        end else begin
            if (s_axi_arvalid && s_axi_arready) begin
                s_axi_rvalid <= 1'b1;
                if (s_axi_araddr[1:0] != 2'b00) begin
                    s_axi_rdata <= 32'b0;
                    s_axi_rresp <= RESP_SLVERR;
                end else begin
                    case (s_axi_araddr[7:0])
                        REG_CONTROL: begin
                            s_axi_rdata <= {31'b0, enable_reg};
                            s_axi_rresp <= RESP_OKAY;
                        end
                        REG_STATUS: begin
                            s_axi_rdata <= {
                                30'b0,
                                ((received_count != 0) ||
                                 (processed_count != 0) ||
                                 (crc_error_count != 0) ||
                                 (fifo_overflow_count != 0)),
                                enable_reg
                            };
                            s_axi_rresp <= RESP_OKAY;
                        end
                        REG_RX_COUNT: begin
                            s_axi_rdata <= received_count;
                            s_axi_rresp <= RESP_OKAY;
                        end
                        REG_PROCESSED: begin
                            s_axi_rdata <= processed_count;
                            s_axi_rresp <= RESP_OKAY;
                        end
                        REG_CRC_ERRORS: begin
                            s_axi_rdata <= crc_error_count;
                            s_axi_rresp <= RESP_OKAY;
                        end
                        REG_FIFO_OVERFLOW: begin
                            s_axi_rdata <= fifo_overflow_count;
                            s_axi_rresp <= RESP_OKAY;
                        end
                        default: begin
                            s_axi_rdata <= 32'b0;
                            s_axi_rresp <= RESP_SLVERR;
                        end
                    endcase
                end
            end

            if (s_axi_rvalid && s_axi_rready)
                s_axi_rvalid <= 1'b0;
        end
    end

endmodule

`default_nettype wire
