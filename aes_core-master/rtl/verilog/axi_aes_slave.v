`timescale 1ns / 1ps
`default_nettype none

module axi_aes_slave #(
    parameter DATA_WIDTH   = 32,
    parameter ADDR_WIDTH   = 32,
    parameter STRB_WIDTH   = DATA_WIDTH/8,
    parameter ID_WIDTH     = 8,
    parameter AWUSER_WIDTH = 1,
    parameter WUSER_WIDTH  = 1,
    parameter BUSER_WIDTH  = 1,
    parameter ARUSER_WIDTH = 1,
    parameter RUSER_WIDTH  = 1
)(
    input  wire                     clk,
    input  wire                     rst,

    // AXI4 write address channel
    input  wire [ID_WIDTH-1:0]      s_axi_awid,
    input  wire [ADDR_WIDTH-1:0]    s_axi_awaddr,
    input  wire [7:0]               s_axi_awlen,
    input  wire [2:0]               s_axi_awsize,
    input  wire [1:0]               s_axi_awburst,
    input  wire                     s_axi_awlock,
    input  wire [3:0]               s_axi_awcache,
    input  wire [2:0]               s_axi_awprot,
    input  wire [3:0]               s_axi_awqos,
    input  wire [3:0]               s_axi_awregion,
    input  wire [AWUSER_WIDTH-1:0]  s_axi_awuser,
    input  wire                     s_axi_awvalid,
    output wire                     s_axi_awready,

    // AXI4 write data channel
    input  wire [DATA_WIDTH-1:0]    s_axi_wdata,
    input  wire [STRB_WIDTH-1:0]    s_axi_wstrb,
    input  wire                     s_axi_wlast,
    input  wire [WUSER_WIDTH-1:0]   s_axi_wuser,
    input  wire                     s_axi_wvalid,
    output wire                     s_axi_wready,

    // AXI4 write response channel
    output reg  [ID_WIDTH-1:0]      s_axi_bid,
    output reg  [1:0]               s_axi_bresp,
    output wire [BUSER_WIDTH-1:0]   s_axi_buser,
    output reg                      s_axi_bvalid,
    input  wire                     s_axi_bready,

    // AXI4 read address channel
    input  wire [ID_WIDTH-1:0]      s_axi_arid,
    input  wire [ADDR_WIDTH-1:0]    s_axi_araddr,
    input  wire [7:0]               s_axi_arlen,
    input  wire [2:0]               s_axi_arsize,
    input  wire [1:0]               s_axi_arburst,
    input  wire                     s_axi_arlock,
    input  wire [3:0]               s_axi_arcache,
    input  wire [2:0]               s_axi_arprot,
    input  wire [3:0]               s_axi_arqos,
    input  wire [3:0]               s_axi_arregion,
    input  wire [ARUSER_WIDTH-1:0]  s_axi_aruser,
    input  wire                     s_axi_arvalid,
    output wire                     s_axi_arready,

    // AXI4 read data channel
    output reg  [ID_WIDTH-1:0]      s_axi_rid,
    output reg  [DATA_WIDTH-1:0]    s_axi_rdata,
    output reg  [1:0]               s_axi_rresp,
    output reg                      s_axi_rlast,
    output wire [RUSER_WIDTH-1:0]   s_axi_ruser,
    output reg                      s_axi_rvalid,
    input  wire                     s_axi_rready,

    // Register-set write interface
    output reg                      reg_wr_en,
    output reg  [ADDR_WIDTH-1:0]    reg_wr_addr,
    output reg  [DATA_WIDTH-1:0]    reg_wr_data,
    output reg  [STRB_WIDTH-1:0]    reg_wr_strb,

    // Register-set read interface
    output wire                     reg_rd_en,
    output wire [ADDR_WIDTH-1:0]    reg_rd_addr,
    input  wire [DATA_WIDTH-1:0]    reg_rd_data
);

    // AXI response encodings
    localparam [1:0] RESP_OKAY   = 2'b00;
    localparam [1:0] RESP_SLVERR = 2'b10;

    // AXI burst encodings
    localparam [1:0] BURST_FIXED = 2'b00;
    localparam [1:0] BURST_INCR  = 2'b01;
    localparam [1:0] BURST_WRAP  = 2'b10;

    localparam integer DATA_BYTES = DATA_WIDTH/8;
    localparam integer MAX_SIZE   = $clog2(DATA_BYTES);

    // -----------------------------
    // Write transaction state
    // -----------------------------
    reg                     wr_active;
    reg [ID_WIDTH-1:0]      wr_id;
    reg [ADDR_WIDTH-1:0]    wr_addr;
    reg [ADDR_WIDTH-1:0]    wr_start_addr;
    reg [7:0]               wr_len;
    reg [2:0]               wr_size;
    reg [1:0]               wr_burst;
    reg [7:0]               wr_beat;
    reg                     wr_error;

    // -----------------------------
    // Read transaction state
    // -----------------------------
    reg                     rd_active;
    reg [ID_WIDTH-1:0]      rd_id;
    reg [ADDR_WIDTH-1:0]    rd_addr;
    reg [ADDR_WIDTH-1:0]    rd_start_addr;
    reg [7:0]               rd_len;
    reg [2:0]               rd_size;
    reg [1:0]               rd_burst;
    reg [7:0]               rd_beat;
    reg                     rd_error;

    // Unused AXI USER response fields are driven to zero.
    assign s_axi_buser = {BUSER_WIDTH{1'b0}};
    assign s_axi_ruser = {RUSER_WIDTH{1'b0}};

    // One outstanding write burst and one outstanding read burst are supported.
    // AW and AR may be accepted independently, so read and write can run concurrently.
    assign s_axi_awready = !rst && !wr_active && !s_axi_bvalid;
    assign s_axi_wready  = !rst &&  wr_active && !s_axi_bvalid;
    assign s_axi_arready = !rst && !rd_active;

    // Combinational register-set read request/address.
    // This makes reg_rd_data valid for the current AXI read beat before the clock edge.
    assign reg_rd_en   = !rst && rd_active && !s_axi_rvalid;
    assign reg_rd_addr = rd_addr;

    // Return the byte address of the next beat.
    function [ADDR_WIDTH-1:0] next_burst_addr;
        input [ADDR_WIDTH-1:0] current_addr;
        input [ADDR_WIDTH-1:0] start_addr;
        input [7:0]            len;
        input [2:0]            size;
        input [1:0]            burst;

        reg [ADDR_WIDTH-1:0] beat_bytes;
        reg [ADDR_WIDTH-1:0] wrap_bytes;
        reg [ADDR_WIDTH-1:0] wrap_base;
        reg [ADDR_WIDTH-1:0] incr_addr;
        begin
            beat_bytes = {{(ADDR_WIDTH-1){1'b0}}, 1'b1} << size;
            incr_addr  = current_addr + beat_bytes;

            case (burst)
                BURST_FIXED: begin
                    next_burst_addr = current_addr;
                end

                BURST_INCR: begin
                    next_burst_addr = incr_addr;
                end

                BURST_WRAP: begin
                    // AXI wrap size = number of beats * bytes per beat.
                    // This implementation assumes legal AXI WRAP lengths/alignment.
                    wrap_bytes = ({ {(ADDR_WIDTH-8){1'b0}}, len } + 1'b1) << size;
                    wrap_base  = start_addr & ~(wrap_bytes - 1'b1);

                    if (incr_addr >= wrap_base + wrap_bytes)
                        next_burst_addr = wrap_base;
                    else
                        next_burst_addr = incr_addr;
                end

                default: begin
                    next_burst_addr = current_addr;
                end
            endcase
        end
    endfunction

    // Main sequential logic.  rst is active high, matching axi_interconnect.v.
    always @(posedge clk) begin
        if (rst) begin
            // Write path reset
            wr_active   <= 1'b0;
            wr_id       <= {ID_WIDTH{1'b0}};
            wr_addr     <= {ADDR_WIDTH{1'b0}};
            wr_start_addr <= {ADDR_WIDTH{1'b0}};
            wr_len      <= 8'd0;
            wr_size     <= 3'd0;
            wr_burst    <= BURST_INCR;
            wr_beat     <= 8'd0;
            wr_error    <= 1'b0;

            s_axi_bid   <= {ID_WIDTH{1'b0}};
            s_axi_bresp <= RESP_OKAY;
            s_axi_bvalid<= 1'b0;

            reg_wr_en   <= 1'b0;
            reg_wr_addr <= {ADDR_WIDTH{1'b0}};
            reg_wr_data <= {DATA_WIDTH{1'b0}};
            reg_wr_strb <= {STRB_WIDTH{1'b0}};

            // Read path reset
            rd_active   <= 1'b0;
            rd_id       <= {ID_WIDTH{1'b0}};
            rd_addr     <= {ADDR_WIDTH{1'b0}};
            rd_start_addr <= {ADDR_WIDTH{1'b0}};
            rd_len      <= 8'd0;
            rd_size     <= 3'd0;
            rd_burst    <= BURST_INCR;
            rd_beat     <= 8'd0;
            rd_error    <= 1'b0;

            s_axi_rid   <= {ID_WIDTH{1'b0}};
            s_axi_rdata <= {DATA_WIDTH{1'b0}};
            s_axi_rresp <= RESP_OKAY;
            s_axi_rlast <= 1'b0;
            s_axi_rvalid<= 1'b0;

        end else begin
            // Register write strobe is a one-cycle pulse.
            reg_wr_en <= 1'b0;

            // ================================================================
            // WRITE ADDRESS CHANNEL (AW)
            // ================================================================
            if (s_axi_awvalid && s_axi_awready) begin
                wr_active     <= 1'b1;
                wr_id         <= s_axi_awid;
                wr_addr       <= s_axi_awaddr;
                wr_start_addr <= s_axi_awaddr;
                wr_len        <= s_axi_awlen;
                wr_size       <= s_axi_awsize;
                wr_burst      <= s_axi_awburst;
                wr_beat       <= 8'd0;

                // Register set is DATA_WIDTH wide. Flag illegal/unsupported transfer sizes
                // and reserved burst type. Legal smaller transfers are controlled by WSTRB.
                wr_error <= (s_axi_awsize > MAX_SIZE) ||
                            (s_axi_awburst == 2'b11);
            end

            // ================================================================
            // WRITE DATA CHANNEL (W)
            // ================================================================
            if (s_axi_wvalid && s_axi_wready) begin
                // Always expose the accepted beat to the register set if the
                // transfer itself is a supported size/burst.
                if (!wr_error) begin
                    reg_wr_en   <= 1'b1;
                    reg_wr_addr <= wr_addr;
                    reg_wr_data <= s_axi_wdata;
                    reg_wr_strb <= s_axi_wstrb;
                end

                // Check WLAST against AWLEN.  AWLEN=N means N+1 beats.
                if ((wr_beat == wr_len) != s_axi_wlast)
                    wr_error <= 1'b1;

                if ((wr_beat == wr_len) || s_axi_wlast) begin
                    // End the write burst and create one B response.
                    wr_active   <= 1'b0;
                    s_axi_bid   <= wr_id;
                    s_axi_bvalid<= 1'b1;

                    if (wr_error || ((wr_beat == wr_len) != s_axi_wlast))
                        s_axi_bresp <= RESP_SLVERR;
                    else
                        s_axi_bresp <= RESP_OKAY;
                end else begin
                    wr_beat <= wr_beat + 1'b1;
                    wr_addr <= next_burst_addr(
                        wr_addr,
                        wr_start_addr,
                        wr_len,
                        wr_size,
                        wr_burst
                    );
                end
            end

            // ================================================================
            // WRITE RESPONSE CHANNEL (B)
            // ================================================================
            if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end

            // ================================================================
            // READ ADDRESS CHANNEL (AR)
            // ================================================================
            if (s_axi_arvalid && s_axi_arready) begin
                rd_active     <= 1'b1;
                rd_id         <= s_axi_arid;
                rd_addr       <= s_axi_araddr;
                rd_start_addr <= s_axi_araddr;
                rd_len        <= s_axi_arlen;
                rd_size       <= s_axi_arsize;
                rd_burst      <= s_axi_arburst;
                rd_beat       <= 8'd0;
                rd_error      <= (s_axi_arsize > MAX_SIZE) ||
                                 (s_axi_arburst == 2'b11);
            end

            // ================================================================
            // READ DATA CHANNEL (R)
            // ================================================================
            // Generate a new R beat only when the previous one is not pending.
            // reg_rd_addr continuously reflects rd_addr, so reg_rd_data must be
            // a combinational read from the register set.
            if (rd_active && !s_axi_rvalid) begin
                s_axi_rid   <= rd_id;
                s_axi_rdata <= reg_rd_data;
                s_axi_rresp <= rd_error ? RESP_SLVERR : RESP_OKAY;
                s_axi_rlast <= (rd_beat == rd_len);
                s_axi_rvalid<= 1'b1;
            end

            // Advance only after the master accepts the current read beat.
            if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;

                if (s_axi_rlast) begin
                    rd_active <= 1'b0;
                    s_axi_rlast <= 1'b0;
                end else begin
                    rd_beat <= rd_beat + 1'b1;
                    rd_addr <= next_burst_addr(
                        rd_addr,
                        rd_start_addr,
                        rd_len,
                        rd_size,
                        rd_burst
                    );
                end
            end
        end
    end

    // The following AXI sideband inputs are accepted but are not used by this
    // memory-mapped AES register slave: AWLOCK/AWCACHE/AWPROT/AWQOS/AWREGION/
    // AWUSER, WUSER, ARLOCK/ARCACHE/ARPROT/ARQOS/ARREGION/ARUSER.

endmodule

`default_nettype wire
