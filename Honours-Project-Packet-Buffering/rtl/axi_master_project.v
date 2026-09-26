`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * ============================================================================
 * AXI4 PROJECT MASTER
 * ============================================================================
 *
 * File    : axi_master_project.v
 * Purpose : Generic AXI4 master for the RISC-V packet-buffering /
 *           data-integrity SoC.
 *
 * Intended connection:
 *
 *   +----------------------+       AXI4       +----------------------------+
 *   | AXI Master           |----------------->| axi_interconnect_wrap_1x8 |
 *   | axi_master_project   |                  |                            |
 *   +----------------------+                  +----------------------------+
 *                                                     | | | | | | | |
 *                                                     v v v v v v v v
 *                                                    M0..M7 peripherals
 *
 * The master-side AXI signals in this module are intentionally named
 * m_axi_* because they connect to the s00_axi_* side of the 1x8
 * interconnect wrapper.
 *
 * ============================================================================
 * IMPORTANT
 * ============================================================================
 *
 * This module is a CONTROL/TEST AXI master. It is not the RISC-V CPU itself.
 *
 * It provides a simple local command interface so that a testbench or a
 * future control block can issue AXI memory-mapped reads and writes.
 *
 * The final SoC can use:
 *
 *   VeeR EL2 AXI master -> axi_interconnect_wrap_1x8
 *
 * while this module can first be used to verify:
 *
 *   AXI master -> interconnect -> each AXI slave
 *
 * ============================================================================
 * FEATURES
 * ============================================================================
 *
 * - AXI4 AW channel
 * - AXI4 W channel
 * - AXI4 B channel
 * - AXI4 AR channel
 * - AXI4 R channel
 * - Single outstanding transaction
 * - Single-beat AXI4 accesses
 * - Read operations
 * - Write operations
 * - Byte write strobes
 * - AXI OKAY / EXOKAY / SLVERR / DECERR response propagation
 * - AXI ID checking
 * - RLAST checking
 * - Configurable DATA_WIDTH / ADDR_WIDTH / ID_WIDTH
 * - Configurable AXI USER widths
 * - VALID remains asserted until READY
 * - AW and W are handled as independent AXI channels
 * - Suitable for memory-mapped UART, GPIO, Timer, FIFO, CRC and counter
 *   register accesses
 *
 * ============================================================================
 * LOCAL COMMAND INTERFACE
 * ============================================================================
 *
 * Write:
 *
 *   cmd_valid = 1
 *   cmd_write = 1
 *   cmd_addr  = target AXI address
 *   cmd_wdata = data to write
 *   cmd_wstrb = byte enables
 *
 * Read:
 *
 *   cmd_valid = 1
 *   cmd_write = 0
 *   cmd_addr  = target AXI address
 *
 * A command is accepted only when cmd_ready = 1.
 *
 * On completion:
 *
 *   done      = 1 for one clock
 *   error     = 1 for one clock if the AXI response is not successful
 *   resp      = AXI response code
 *   read_data = returned RDATA for a read
 *
 * ============================================================================
 * AXI RESPONSE ENCODING
 * ============================================================================
 *
 *   2'b00 = OKAY
 *   2'b01 = EXOKAY
 *   2'b10 = SLVERR
 *   2'b11 = DECERR
 *
 * This master treats OKAY and EXOKAY as successful responses.
 *
 * ============================================================================
 */

module axi_master_project #
(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter STRB_WIDTH = (DATA_WIDTH/8),
    parameter ID_WIDTH   = 8,

    parameter AWUSER_ENABLE = 0,
    parameter AWUSER_WIDTH  = 1,
    parameter WUSER_ENABLE  = 0,
    parameter WUSER_WIDTH   = 1,
    parameter BUSER_ENABLE  = 0,
    parameter BUSER_WIDTH   = 1,
    parameter ARUSER_ENABLE = 0,
    parameter ARUSER_WIDTH  = 1,
    parameter RUSER_ENABLE  = 0,
    parameter RUSER_WIDTH   = 1,

    parameter ID_VALUE = {ID_WIDTH{1'b0}}
)
(
    input  wire                     clk,
    input  wire                     rst,

    /*
     * ------------------------------------------------------------------------
     * LOCAL COMMAND INTERFACE
     * ------------------------------------------------------------------------
     */
    input  wire                     cmd_valid,
    output wire                     cmd_ready,
    output wire                     busy,

    input  wire                     cmd_write,
    input  wire [ADDR_WIDTH-1:0]    cmd_addr,
    input  wire [DATA_WIDTH-1:0]    cmd_wdata,
    input  wire [STRB_WIDTH-1:0]    cmd_wstrb,

    /*
     * AXI protection/cache attributes.
     *
     * Typical normal-access values:
     *   cmd_prot  = 3'b000
     *   cmd_cache = 4'b0000
     *   cmd_qos   = 4'b0000
     */
    input  wire [2:0]               cmd_prot,
    input  wire [3:0]               cmd_cache,
    input  wire [3:0]               cmd_qos,

    /*
     * ------------------------------------------------------------------------
     * LOCAL RESULT INTERFACE
     * ------------------------------------------------------------------------
     */
    output reg                      done,
    output reg                      error,
    output reg  [1:0]               resp,
    output reg  [DATA_WIDTH-1:0]    read_data,

    /*
     * ------------------------------------------------------------------------
     * AXI4 WRITE ADDRESS CHANNEL
     * Connect this group to:
     *
     *   axi_interconnect_wrap_1x8.s00_axi_aw*
     * ------------------------------------------------------------------------
     */
    output wire [ID_WIDTH-1:0]       m_axi_awid,
    output wire [ADDR_WIDTH-1:0]     m_axi_awaddr,
    output wire [7:0]                m_axi_awlen,
    output wire [2:0]                m_axi_awsize,
    output wire [1:0]                m_axi_awburst,
    output wire                     m_axi_awlock,
    output wire [3:0]                m_axi_awcache,
    output wire [2:0]                m_axi_awprot,
    output wire [3:0]                m_axi_awqos,
    output wire [3:0]                m_axi_awregion,
    output wire [AWUSER_WIDTH-1:0]   m_axi_awuser,
    output wire                     m_axi_awvalid,
    input  wire                     m_axi_awready,

    /*
     * ------------------------------------------------------------------------
     * AXI4 WRITE DATA CHANNEL
     * ------------------------------------------------------------------------
     */
    output wire [DATA_WIDTH-1:0]     m_axi_wdata,
    output wire [STRB_WIDTH-1:0]     m_axi_wstrb,
    output wire                     m_axi_wlast,
    output wire [WUSER_WIDTH-1:0]    m_axi_wuser,
    output wire                     m_axi_wvalid,
    input  wire                     m_axi_wready,

    /*
     * ------------------------------------------------------------------------
     * AXI4 WRITE RESPONSE CHANNEL
     * ------------------------------------------------------------------------
     */
    input  wire [ID_WIDTH-1:0]       m_axi_bid,
    input  wire [1:0]                m_axi_bresp,
    input  wire [BUSER_WIDTH-1:0]    m_axi_buser,
    input  wire                     m_axi_bvalid,
    output wire                     m_axi_bready,

    /*
     * ------------------------------------------------------------------------
     * AXI4 READ ADDRESS CHANNEL
     * ------------------------------------------------------------------------
     */
    output wire [ID_WIDTH-1:0]       m_axi_arid,
    output wire [ADDR_WIDTH-1:0]     m_axi_araddr,
    output wire [7:0]                m_axi_arlen,
    output wire [2:0]                m_axi_arsize,
    output wire [1:0]                m_axi_arburst,
    output wire                     m_axi_arlock,
    output wire [3:0]                m_axi_arcache,
    output wire [2:0]                m_axi_arprot,
    output wire [3:0]                m_axi_arqos,
    output wire [3:0]                m_axi_arregion,
    output wire [ARUSER_WIDTH-1:0]   m_axi_aruser,
    output wire                     m_axi_arvalid,
    input  wire                     m_axi_arready,

    /*
     * ------------------------------------------------------------------------
     * AXI4 READ DATA CHANNEL
     * ------------------------------------------------------------------------
     */
    input  wire [ID_WIDTH-1:0]       m_axi_rid,
    input  wire [DATA_WIDTH-1:0]     m_axi_rdata,
    input  wire [1:0]                m_axi_rresp,
    input  wire                     m_axi_rlast,
    input  wire [RUSER_WIDTH-1:0]    m_axi_ruser,
    input  wire                     m_axi_rvalid,
    output wire                     m_axi_rready
);

    /*
     * AXI transfer size.
     *
     * For a 32-bit data bus:
     *   STRB_WIDTH = 4
     *   AXI_SIZE   = 2 -> 4 bytes/beat
     *
     * For a 64-bit data bus:
     *   STRB_WIDTH = 8
     *   AXI_SIZE   = 3 -> 8 bytes/beat
     */
    localparam [2:0] AXI_SIZE = $clog2(STRB_WIDTH);

    /*
     * State machine.
     *
     * There is only one outstanding transaction. This is deliberate:
     * it makes the master deterministic and ideal for validating the
     * interconnect and memory-mapped project peripherals.
     */
    localparam [3:0]
        ST_IDLE = 4'd0,
        ST_W_AW = 4'd1,
        ST_W_W  = 4'd2,
        ST_W_B  = 4'd3,
        ST_R_AR = 4'd4,
        ST_R_R  = 4'd5;

    reg [3:0] state;

    /*
     * Latched command information.
     */
    reg [ID_WIDTH-1:0]   id_reg;
    reg [ADDR_WIDTH-1:0] addr_reg;
    reg [DATA_WIDTH-1:0] wdata_reg;
    reg [STRB_WIDTH-1:0] wstrb_reg;
    reg [2:0]            prot_reg;
    reg [3:0]            cache_reg;
    reg [3:0]            qos_reg;
    reg                  write_reg;

    /*
     * ------------------------------------------------------------------------
     * LOCAL STATUS
     * ------------------------------------------------------------------------
     */
    assign busy      = (state != ST_IDLE);
    assign cmd_ready = (state == ST_IDLE);

    /*
     * ------------------------------------------------------------------------
     * AXI WRITE ADDRESS CHANNEL
     * ------------------------------------------------------------------------
     *
     * Single-beat transfer:
     *   AWLEN   = 0
     *   AWSIZE  = bytes per beat
     *   AWBURST = INCR
     */
    assign m_axi_awid     = id_reg;
    assign m_axi_awaddr   = addr_reg;
    assign m_axi_awlen    = 8'd0;
    assign m_axi_awsize   = AXI_SIZE;
    assign m_axi_awburst  = 2'b01;       // INCR
    assign m_axi_awlock   = 1'b0;
    assign m_axi_awcache  = cache_reg;
    assign m_axi_awprot   = prot_reg;
    assign m_axi_awqos    = qos_reg;
    assign m_axi_awregion = 4'd0;
    assign m_axi_awuser   = {AWUSER_WIDTH{1'b0}};
    assign m_axi_awvalid  = (state == ST_W_AW);

    /*
     * ------------------------------------------------------------------------
     * AXI WRITE DATA CHANNEL
     * ------------------------------------------------------------------------
     */
    assign m_axi_wdata  = wdata_reg;
    assign m_axi_wstrb  = wstrb_reg;
    assign m_axi_wlast  = 1'b1;
    assign m_axi_wuser  = {WUSER_WIDTH{1'b0}};
    assign m_axi_wvalid = (state == ST_W_W);

    /*
     * ------------------------------------------------------------------------
     * AXI WRITE RESPONSE CHANNEL
     * ------------------------------------------------------------------------
     *
     * BREADY is asserted only while waiting for the response.
     */
    assign m_axi_bready = (state == ST_W_B);

    /*
     * ------------------------------------------------------------------------
     * AXI READ ADDRESS CHANNEL
     * ------------------------------------------------------------------------
     */
    assign m_axi_arid     = id_reg;
    assign m_axi_araddr   = addr_reg;
    assign m_axi_arlen    = 8'd0;
    assign m_axi_arsize   = AXI_SIZE;
    assign m_axi_arburst  = 2'b01;        // INCR
    assign m_axi_arlock   = 1'b0;
    assign m_axi_arcache  = cache_reg;
    assign m_axi_arprot   = prot_reg;
    assign m_axi_arqos    = qos_reg;
    assign m_axi_arregion = 4'd0;
    assign m_axi_aruser   = {ARUSER_WIDTH{1'b0}};
    assign m_axi_arvalid  = (state == ST_R_AR);

    /*
     * ------------------------------------------------------------------------
     * AXI READ DATA CHANNEL
     * ------------------------------------------------------------------------
     */
    assign m_axi_rready = (state == ST_R_R);

    /*
     * ------------------------------------------------------------------------
     * MAIN STATE MACHINE
     * ------------------------------------------------------------------------
     */
    always @(posedge clk) begin
        if (rst) begin
            state      <= ST_IDLE;

            id_reg     <= ID_VALUE;
            addr_reg   <= {ADDR_WIDTH{1'b0}};
            wdata_reg  <= {DATA_WIDTH{1'b0}};
            wstrb_reg  <= {STRB_WIDTH{1'b0}};
            prot_reg   <= 3'b000;
            cache_reg  <= 4'b0000;
            qos_reg    <= 4'b0000;
            write_reg  <= 1'b0;

            done       <= 1'b0;
            error      <= 1'b0;
            resp       <= 2'b00;
            read_data  <= {DATA_WIDTH{1'b0}};
        end
        else begin

            /*
             * done/error are event pulses.
             */
            done  <= 1'b0;
            error <= 1'b0;

            case (state)

                /*
                 * ============================================================
                 * IDLE
                 * ============================================================
                 */
                ST_IDLE: begin

                    if (cmd_valid) begin

                        /*
                         * Latch the entire command before asserting AXI VALID.
                         */
                        id_reg    <= ID_VALUE;
                        addr_reg  <= cmd_addr;
                        wdata_reg <= cmd_wdata;
                        wstrb_reg <= cmd_wstrb;
                        prot_reg  <= cmd_prot;
                        cache_reg <= cmd_cache;
                        qos_reg   <= cmd_qos;
                        write_reg <= cmd_write;

                        if (cmd_write) begin
                            state <= ST_W_AW;
                        end
                        else begin
                            state <= ST_R_AR;
                        end
                    end
                end

                /*
                 * ============================================================
                 * WRITE ADDRESS
                 * ============================================================
                 *
                 * AXI rule:
                 *   VALID is not withdrawn until READY completes the transfer.
                 */
                ST_W_AW: begin

                    if (m_axi_awvalid && m_axi_awready) begin
                        state <= ST_W_W;
                    end
                end

                /*
                 * ============================================================
                 * WRITE DATA
                 * ============================================================
                 *
                 * Single beat, therefore WLAST is always 1.
                 */
                ST_W_W: begin

                    if (m_axi_wvalid && m_axi_wready) begin
                        state <= ST_W_B;
                    end
                end

                /*
                 * ============================================================
                 * WRITE RESPONSE
                 * ============================================================
                 */
                ST_W_B: begin

                    if (m_axi_bvalid && m_axi_bready) begin

                        resp <= m_axi_bresp;

                        /*
                         * Check both response and transaction ID.
                         *
                         * ID mismatch is treated as an error because this
                         * master has only one outstanding transaction.
                         */
                        if ((m_axi_bresp == 2'b00 ||
                             m_axi_bresp == 2'b01) &&
                            (m_axi_bid == id_reg)) begin

                            error <= 1'b0;
                        end
                        else begin

                            error <= 1'b1;
                        end

                        done  <= 1'b1;
                        state <= ST_IDLE;
                    end
                end

                /*
                 * ============================================================
                 * READ ADDRESS
                 * ============================================================
                 */
                ST_R_AR: begin

                    if (m_axi_arvalid && m_axi_arready) begin
                        state <= ST_R_R;
                    end
                end

                /*
                 * ============================================================
                 * READ DATA
                 * ============================================================
                 */
                ST_R_R: begin

                    if (m_axi_rvalid && m_axi_rready) begin

                        read_data <= m_axi_rdata;
                        resp      <= m_axi_rresp;

                        /*
                         * A single-beat read must terminate with RLAST.
                         * ID must also match the outstanding transaction.
                         */
                        if ((m_axi_rresp == 2'b00 ||
                             m_axi_rresp == 2'b01) &&
                            (m_axi_rid == id_reg) &&
                            (m_axi_rlast == 1'b1)) begin

                            error <= 1'b0;
                        end
                        else begin

                            error <= 1'b1;
                        end

                        done  <= 1'b1;
                        state <= ST_IDLE;
                    end
                end

                /*
                 * ============================================================
                 * SAFETY DEFAULT
                 * ============================================================
                 */
                default: begin
                    state <= ST_IDLE;
                end

            endcase
        end
    end

endmodule

`default_nettype wire
`resetall
