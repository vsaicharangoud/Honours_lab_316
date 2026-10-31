/*
 * ============================================================================
 * File: axi_ram.v
 * Project: Reliable Data Transport System SoC
 * Description: AXI4 High-Performance Memory IP (Instruction / Data RAM)
 *              Interconnect Slots: M00 (Instruction Memory) & M01 (Data Memory)
 *
 * Features:
 *   - 32-bit data bus with independent 4-byte strobe write enables
 *   - Configurable memory depth (Default: 64KB = 16384 words)
 *   - Supports single-beat and INCR burst transactions (essential for IFU)
 *   - Optional HEX file preloading via $readmemh
 *   - Full AXI4 protocol compliance (OKAY response, ARLEN/AWLEN burst counters)
 * ============================================================================
 */

`resetall
`timescale 1ns / 1ps
`default_nettype none

module axi_ram #(
    parameter integer DATA_WIDTH     = 32,
    parameter integer ADDR_WIDTH     = 32,
    parameter integer ID_WIDTH       = 8,
    parameter integer STRB_WIDTH     = DATA_WIDTH / 8,
    parameter integer USER_WIDTH     = 1,
    parameter integer MEM_ADDR_BITS = 16, // 2^16 = 64KB
    parameter         INIT_HEX_FILE = ""  // Optional firmware/data file
)(
    input  wire                  clk,
    input  wire                  rst,      // Active-high synchronous reset

    // ------------------------------------------------------------------------
    // AXI4 Subordinate Write Address Channel
    // ------------------------------------------------------------------------
    input  wire [ID_WIDTH-1:0]   s_axi_awid,
    input  wire [ADDR_WIDTH-1:0] s_axi_awaddr,
    input  wire [7:0]            s_axi_awlen,
    input  wire [2:0]            s_axi_awsize,
    input  wire [1:0]            s_axi_awburst,
    input  wire                  s_axi_awlock,
    input  wire [3:0]            s_axi_awcache,
    input  wire [2:0]            s_axi_awprot,
    input  wire [3:0]            s_axi_awqos,
    input  wire [3:0]            s_axi_awregion,
    input  wire [USER_WIDTH-1:0] s_axi_awuser,
    input  wire                  s_axi_awvalid,
    output reg                   s_axi_awready,

    // ------------------------------------------------------------------------
    // AXI4 Subordinate Write Data Channel
    // ------------------------------------------------------------------------
    input  wire [DATA_WIDTH-1:0] s_axi_wdata,
    input  wire [STRB_WIDTH-1:0] s_axi_wstrb,
    input  wire                  s_axi_wlast,
    input  wire [USER_WIDTH-1:0] s_axi_wuser,
    input  wire                  s_axi_wvalid,
    output reg                   s_axi_wready,

    // ------------------------------------------------------------------------
    // AXI4 Subordinate Write Response Channel
    // ------------------------------------------------------------------------
    output reg  [ID_WIDTH-1:0]   s_axi_bid,
    output reg  [1:0]            s_axi_bresp,
    output reg  [USER_WIDTH-1:0] s_axi_buser,
    output reg                   s_axi_bvalid,
    input  wire                  s_axi_bready,

    // ------------------------------------------------------------------------
    // AXI4 Subordinate Read Address Channel
    // ------------------------------------------------------------------------
    input  wire [ID_WIDTH-1:0]   s_axi_arid,
    input  wire [ADDR_WIDTH-1:0] s_axi_araddr,
    input  wire [7:0]            s_axi_arlen,
    input  wire [2:0]            s_axi_arsize,
    input  wire [1:0]            s_axi_arburst,
    input  wire                  s_axi_arlock,
    input  wire [3:0]            s_axi_arcache,
    input  wire [2:0]            s_axi_arprot,
    input  wire [3:0]            s_axi_arqos,
    input  wire [3:0]            s_axi_arregion,
    input  wire [USER_WIDTH-1:0] s_axi_aruser,
    input  wire                  s_axi_arvalid,
    output reg                   s_axi_arready,

    // ------------------------------------------------------------------------
    // AXI4 Subordinate Read Data Channel
    // ------------------------------------------------------------------------
    output reg  [ID_WIDTH-1:0]   s_axi_rid,
    output reg  [DATA_WIDTH-1:0] s_axi_rdata,
    output reg  [1:0]            s_axi_rresp,
    output reg                   s_axi_rlast,
    output reg  [USER_WIDTH-1:0] s_axi_ruser,
    output reg                   s_axi_rvalid,
    input  wire                  s_axi_rready
);

    localparam integer WORDS = 1 << (MEM_ADDR_BITS - 2); // 16384 x 32-bit words for 64KB
    localparam [1:0]   AXI_RESP_OKAY = 2'b00;

    // Byte-wide RAM arrays for proper byte write strobing
    reg [7:0] mem_b0 [0:WORDS-1];
    reg [7:0] mem_b1 [0:WORDS-1];
    reg [7:0] mem_b2 [0:WORDS-1];
    reg [7:0] mem_b3 [0:WORDS-1];

    // Temporary word-array for $readmemh preloading (declared at module scope
    // so it is valid in both Verilog-2005 and SystemVerilog)
    reg [31:0] tmp_mem [0:WORDS-1];
    integer    i;

    // Optional hex file initialization
    initial begin
        if (INIT_HEX_FILE != "") begin
            $display("[AXI_RAM] Pre-loading memory from %s", INIT_HEX_FILE);
            $readmemh(INIT_HEX_FILE, tmp_mem);
            for (i = 0; i < WORDS; i = i + 1) begin
                mem_b0[i] = tmp_mem[i][7:0];
                mem_b1[i] = tmp_mem[i][15:8];
                mem_b2[i] = tmp_mem[i][23:16];
                mem_b3[i] = tmp_mem[i][31:24];
            end
        end
    end

    // ------------------------------------------------------------------------
    // Write State Machine
    // ------------------------------------------------------------------------
    localparam [1:0]
        WR_IDLE = 2'd0,
        WR_DATA = 2'd1,
        WR_RESP = 2'd2;

    reg [1:0]                wr_state;
    reg [ID_WIDTH-1:0]       wr_id_reg;
    reg [MEM_ADDR_BITS-1:2]  wr_word_addr;
    reg [7:0]                wr_len_cnt;

    always @(posedge clk) begin
        if (rst) begin
            wr_state      <= WR_IDLE;
            s_axi_awready <= 1'b1;
            s_axi_wready  <= 1'b0;
            s_axi_bvalid  <= 1'b0;
            s_axi_bid     <= {ID_WIDTH{1'b0}};
            s_axi_bresp   <= AXI_RESP_OKAY;
            s_axi_buser   <= {USER_WIDTH{1'b0}};
            wr_id_reg     <= {ID_WIDTH{1'b0}};
            wr_word_addr  <= {(MEM_ADDR_BITS-2){1'b0}};
            wr_len_cnt    <= 8'd0;
        end else begin
            case (wr_state)
                WR_IDLE: begin
                    s_axi_awready <= 1'b1;
                    s_axi_wready  <= 1'b0;

                    if (s_axi_awvalid && s_axi_awready) begin
                        wr_id_reg     <= s_axi_awid;
                        wr_word_addr  <= s_axi_awaddr[MEM_ADDR_BITS-1:2];
                        wr_len_cnt    <= s_axi_awlen;
                        s_axi_awready <= 1'b0;
                        s_axi_wready  <= 1'b1;
                        wr_state      <= WR_DATA;
                    end
                end

                WR_DATA: begin
                    s_axi_awready <= 1'b0;
                    s_axi_wready  <= 1'b1;

                    if (s_axi_wvalid && s_axi_wready) begin
                        // Byte-level writes
                        if (s_axi_wstrb[0]) mem_b0[wr_word_addr] <= s_axi_wdata[7:0];
                        if (s_axi_wstrb[1]) mem_b1[wr_word_addr] <= s_axi_wdata[15:8];
                        if (s_axi_wstrb[2]) mem_b2[wr_word_addr] <= s_axi_wdata[23:16];
                        if (s_axi_wstrb[3]) mem_b3[wr_word_addr] <= s_axi_wdata[31:24];

                        wr_word_addr <= wr_word_addr + 1'b1;

                        if (s_axi_wlast || wr_len_cnt == 8'd0) begin
                            s_axi_wready <= 1'b0;
                            s_axi_bvalid <= 1'b1;
                            s_axi_bid    <= wr_id_reg;
                            s_axi_bresp  <= AXI_RESP_OKAY;
                            wr_state     <= WR_RESP;
                        end else begin
                            wr_len_cnt <= wr_len_cnt - 8'd1;
                        end
                    end
                end

                WR_RESP: begin
                    if (s_axi_bvalid && s_axi_bready) begin
                        s_axi_bvalid  <= 1'b0;
                        s_axi_awready <= 1'b1;
                        wr_state      <= WR_IDLE;
                    end
                end
            endcase
        end
    end

    // ------------------------------------------------------------------------
    // Read State Machine
    // ------------------------------------------------------------------------
    localparam [1:0]
        RD_IDLE = 2'd0,
        RD_DATA = 2'd1;

    reg [1:0]                rd_state;
    reg [ID_WIDTH-1:0]       rd_id_reg;
    reg [MEM_ADDR_BITS-1:2]  rd_word_addr;
    reg [7:0]                rd_len_cnt;

    always @(posedge clk) begin
        if (rst) begin
            rd_state      <= RD_IDLE;
            s_axi_arready <= 1'b1;
            s_axi_rvalid  <= 1'b0;
            s_axi_rid     <= {ID_WIDTH{1'b0}};
            s_axi_rdata   <= {DATA_WIDTH{1'b0}};
            s_axi_rresp   <= AXI_RESP_OKAY;
            s_axi_rlast   <= 1'b0;
            s_axi_ruser   <= {USER_WIDTH{1'b0}};
            rd_id_reg     <= {ID_WIDTH{1'b0}};
            rd_word_addr  <= {(MEM_ADDR_BITS-2){1'b0}};
            rd_len_cnt    <= 8'd0;
        end else begin
            case (rd_state)
                RD_IDLE: begin
                    s_axi_arready <= 1'b1;

                    if (s_axi_arvalid && s_axi_arready) begin
                        s_axi_arready <= 1'b0;
                        rd_id_reg     <= s_axi_arid;
                        rd_word_addr  <= s_axi_araddr[MEM_ADDR_BITS-1:2] + 1'b1;
                        rd_len_cnt    <= s_axi_arlen;

                        s_axi_rvalid  <= 1'b1;
                        s_axi_rid     <= s_axi_arid;
                        s_axi_rresp   <= AXI_RESP_OKAY;
                        s_axi_rdata   <= {mem_b3[s_axi_araddr[MEM_ADDR_BITS-1:2]],
                                          mem_b2[s_axi_araddr[MEM_ADDR_BITS-1:2]],
                                          mem_b1[s_axi_araddr[MEM_ADDR_BITS-1:2]],
                                          mem_b0[s_axi_araddr[MEM_ADDR_BITS-1:2]]};
                        s_axi_rlast   <= (s_axi_arlen == 8'd0);

                        rd_state      <= RD_DATA;
                    end
                end

                RD_DATA: begin
                    if (s_axi_rvalid && s_axi_rready) begin
                        if (s_axi_rlast) begin
                            s_axi_rvalid  <= 1'b0;
                            s_axi_rlast   <= 1'b0;
                            s_axi_arready <= 1'b1;
                            rd_state      <= RD_IDLE;
                        end else begin
                            // Next beat of burst
                            rd_word_addr <= rd_word_addr + 1'b1;
                            rd_len_cnt   <= rd_len_cnt - 8'd1;

                            s_axi_rvalid <= 1'b1;
                            s_axi_rdata  <= {mem_b3[rd_word_addr],
                                             mem_b2[rd_word_addr],
                                             mem_b1[rd_word_addr],
                                             mem_b0[rd_word_addr]};
                            s_axi_rlast  <= (rd_len_cnt == 8'd1);
                        end
                    end
                end
            endcase
        end
    end

endmodule

`default_nettype wire
