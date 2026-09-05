`timescale 1ns/1ps
`default_nettype none

//======================================================================
// TESTBENCH : AXI MASTER
//
// Purpose:
//   Basic verification of axi_master.v using:
//     1) Two AXI write transactions
//     2) Two AXI read transactions
//
// The testbench contains a simple behavioral AXI slave model so that
// the AXI master's AW/W/B and AR/R channels can be exercised.
//
// Test sequence:
//   WRITE 0x0000_0010 = 0x1234_5678
//   WRITE 0x0000_0020 = 0xA5A5_5A5A
//   READ  0x0000_0010
//   READ  0x0000_0020
//
// Console messages are intentionally verbose for easy identification.
//======================================================================

module tb_axi_master;

    localparam DATA_WIDTH = 32;
    localparam ADDR_WIDTH = 32;
    localparam STRB_WIDTH = 4;
    localparam ID_WIDTH   = 8;

    reg clk;
    reg rst;

    //==================================================================
    // High-level master WRITE interface
    //==================================================================

    reg                     wr_cmd_valid;
    wire                    wr_cmd_ready;
    reg  [ID_WIDTH-1:0]     wr_cmd_id;
    reg  [ADDR_WIDTH-1:0]   wr_cmd_addr;
    reg  [7:0]              wr_cmd_len;
    reg  [2:0]              wr_cmd_size;
    reg  [1:0]              wr_cmd_burst;

    reg                     wr_data_valid;
    wire                    wr_data_ready;
    reg  [DATA_WIDTH-1:0]   wr_data;
    reg  [STRB_WIDTH-1:0]   wr_strb;
    reg                     wr_data_last;

    wire                    wr_done;
    wire [1:0]              wr_resp;

    //==================================================================
    // High-level master READ interface
    //==================================================================

    reg                     rd_cmd_valid;
    wire                    rd_cmd_ready;
    reg  [ID_WIDTH-1:0]     rd_cmd_id;
    reg  [ADDR_WIDTH-1:0]   rd_cmd_addr;
    reg  [7:0]              rd_cmd_len;
    reg  [2:0]              rd_cmd_size;
    reg  [1:0]              rd_cmd_burst;

    wire                    rd_data_valid;
    reg                     rd_data_ready;
    wire [DATA_WIDTH-1:0]   rd_data;
    wire [ID_WIDTH-1:0]     rd_data_id;
    wire [1:0]              rd_data_resp;
    wire                    rd_data_last;

    wire                    rd_done;
    wire [1:0]              rd_resp;

    //==================================================================
    // AXI WRITE ADDRESS CHANNEL
    //==================================================================

    wire [ID_WIDTH-1:0]     m_axi_awid;
    wire [ADDR_WIDTH-1:0]   m_axi_awaddr;
    wire [7:0]              m_axi_awlen;
    wire [2:0]              m_axi_awsize;
    wire [1:0]              m_axi_awburst;
    wire                    m_axi_awlock;
    wire [3:0]              m_axi_awcache;
    wire [2:0]              m_axi_awprot;
    wire [3:0]              m_axi_awqos;
    wire [3:0]              m_axi_awregion;
    wire                    m_axi_awvalid;
    reg                     m_axi_awready;

    //==================================================================
    // AXI WRITE DATA CHANNEL
    //==================================================================

    wire [DATA_WIDTH-1:0]   m_axi_wdata;
    wire [STRB_WIDTH-1:0]   m_axi_wstrb;
    wire                    m_axi_wlast;
    wire                    m_axi_wvalid;
    reg                     m_axi_wready;

    //==================================================================
    // AXI WRITE RESPONSE CHANNEL
    //==================================================================

    reg  [ID_WIDTH-1:0]     m_axi_bid;
    reg  [1:0]              m_axi_bresp;
    reg                     m_axi_bvalid;
    wire                    m_axi_bready;

    //==================================================================
    // AXI READ ADDRESS CHANNEL
    //==================================================================

    wire [ID_WIDTH-1:0]     m_axi_arid;
    wire [ADDR_WIDTH-1:0]   m_axi_araddr;
    wire [7:0]              m_axi_arlen;
    wire [2:0]              m_axi_arsize;
    wire [1:0]              m_axi_arburst;
    wire                    m_axi_arlock;
    wire [3:0]              m_axi_arcache;
    wire [2:0]              m_axi_arprot;
    wire [3:0]              m_axi_arqos;
    wire [3:0]              m_axi_arregion;
    wire                    m_axi_arvalid;
    reg                     m_axi_arready;

    //==================================================================
    // AXI READ DATA CHANNEL
    //==================================================================

    reg  [ID_WIDTH-1:0]     m_axi_rid;
    reg  [DATA_WIDTH-1:0]   m_axi_rdata;
    reg  [1:0]              m_axi_rresp;
    reg                     m_axi_rlast;
    reg                     m_axi_rvalid;
    wire                    m_axi_rready;

    //==================================================================
    // Simple behavioral memory for the AXI slave model
    //==================================================================

    reg [31:0] memory [0:255];

    reg [31:0] slave_awaddr;
    reg [7:0]  slave_awlen;
    reg [2:0]  slave_awsize;
    reg [1:0]  slave_awburst;
    reg        slave_aw_seen;

    reg [31:0] slave_araddr;
    reg [7:0]  slave_arlen;
    reg [2:0]  slave_arsize;
    reg [1:0]  slave_arburst;
    reg        slave_ar_seen;

    integer i;

    //==================================================================
    // DUT
    //==================================================================

    axi_master #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .STRB_WIDTH(STRB_WIDTH),
        .ID_WIDTH(ID_WIDTH)
    ) dut (

        .clk(clk),
        .rst(rst),

        // High-level WRITE command
        .wr_cmd_valid(wr_cmd_valid),
        .wr_cmd_ready(wr_cmd_ready),
        .wr_cmd_id(wr_cmd_id),
        .wr_cmd_addr(wr_cmd_addr),
        .wr_cmd_len(wr_cmd_len),
        .wr_cmd_size(wr_cmd_size),
        .wr_cmd_burst(wr_cmd_burst),

        .wr_data_valid(wr_data_valid),
        .wr_data_ready(wr_data_ready),
        .wr_data(wr_data),
        .wr_strb(wr_strb),
        .wr_data_last(wr_data_last),

        .wr_done(wr_done),
        .wr_resp(wr_resp),

        // High-level READ command
        .rd_cmd_valid(rd_cmd_valid),
        .rd_cmd_ready(rd_cmd_ready),
        .rd_cmd_id(rd_cmd_id),
        .rd_cmd_addr(rd_cmd_addr),
        .rd_cmd_len(rd_cmd_len),
        .rd_cmd_size(rd_cmd_size),
        .rd_cmd_burst(rd_cmd_burst),

        .rd_data_valid(rd_data_valid),
        .rd_data_ready(rd_data_ready),
        .rd_data(rd_data),
        .rd_data_id(rd_data_id),
        .rd_data_resp(rd_data_resp),
        .rd_data_last(rd_data_last),

        .rd_done(rd_done),
        .rd_resp(rd_resp),

        // AXI AW
        .m_axi_awid(m_axi_awid),
        .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awlen(m_axi_awlen),
        .m_axi_awsize(m_axi_awsize),
        .m_axi_awburst(m_axi_awburst),
        .m_axi_awlock(m_axi_awlock),
        .m_axi_awcache(m_axi_awcache),
        .m_axi_awprot(m_axi_awprot),
        .m_axi_awqos(m_axi_awqos),
        .m_axi_awregion(m_axi_awregion),
        .m_axi_awuser(),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready),

        // AXI W
        .m_axi_wdata(m_axi_wdata),
        .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wlast(m_axi_wlast),
        .m_axi_wuser(),
        .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready),

        // AXI B
        .m_axi_bid(m_axi_bid),
        .m_axi_bresp(m_axi_bresp),
        .m_axi_buser(1'b0),
        .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready),

        // AXI AR
        .m_axi_arid(m_axi_arid),
        .m_axi_araddr(m_axi_araddr),
        .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize),
        .m_axi_arburst(m_axi_arburst),
        .m_axi_arlock(m_axi_arlock),
        .m_axi_arcache(m_axi_arcache),
        .m_axi_arprot(m_axi_arprot),
        .m_axi_arqos(m_axi_arqos),
        .m_axi_arregion(m_axi_arregion),
        .m_axi_aruser(),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),

        // AXI R
        .m_axi_rid(m_axi_rid),
        .m_axi_rdata(m_axi_rdata),
        .m_axi_rresp(m_axi_rresp),
        .m_axi_rlast(m_axi_rlast),
        .m_axi_ruser(1'b0),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready)
    );

    //==================================================================
    // CLOCK
    //==================================================================

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    //==================================================================
    // Initialisation
    //==================================================================

    initial begin

        rst = 1'b1;

        wr_cmd_valid = 1'b0;
        wr_cmd_id    = 8'h00;
        wr_cmd_addr  = 32'h0;
        wr_cmd_len   = 8'h00;
        wr_cmd_size  = 3'd2;
        wr_cmd_burst = 2'b01;

        wr_data_valid = 1'b0;
        wr_data       = 32'h0;
        wr_strb       = 4'hF;
        wr_data_last  = 1'b0;

        rd_cmd_valid = 1'b0;
        rd_cmd_id    = 8'h00;
        rd_cmd_addr  = 32'h0;
        rd_cmd_len   = 8'h00;
        rd_cmd_size  = 3'd2;
        rd_cmd_burst = 2'b01;

        rd_data_ready = 1'b0;

        m_axi_awready = 1'b0;
        m_axi_wready  = 1'b0;

        m_axi_bid    = 8'h00;
        m_axi_bresp  = 2'b00;
        m_axi_bvalid = 1'b0;

        m_axi_arready = 1'b0;

        m_axi_rid    = 8'h00;
        m_axi_rdata  = 32'h0;
        m_axi_rresp  = 2'b00;
        m_axi_rlast  = 1'b0;
        m_axi_rvalid = 1'b0;

        slave_awaddr = 32'h0;
        slave_awlen  = 8'h0;
        slave_awsize = 3'd2;
        slave_awburst = 2'b01;
        slave_aw_seen = 1'b0;

        slave_araddr = 32'h0;
        slave_arlen  = 8'h0;
        slave_arsize = 3'd2;
        slave_arburst = 2'b01;
        slave_ar_seen = 1'b0;

        for (i = 0; i < 256; i = i + 1)
            memory[i] = 32'h0000_0000;

        $display("");
        $display("==============================================================");
        $display("                 AXI MASTER TESTBENCH START");
        $display("==============================================================");
        $display("");

        #30;

        rst = 1'b0;

        $display("[%0t] RESET RELEASED", $time);
        $display("");

        //==============================================================
        // WRITE #1
        //==============================================================

        $display("--------------------------------------------------------------");
        $display(" WRITE #1 : Address 0x00000010, Data 0x12345678");
        $display("--------------------------------------------------------------");

        axi_write(
            8'h01,
            32'h0000_0010,
            32'h1234_5678
        );

        //==============================================================
        // WRITE #2
        //==============================================================

        $display("--------------------------------------------------------------");
        $display(" WRITE #2 : Address 0x00000020, Data 0xA5A55A5A");
        $display("--------------------------------------------------------------");

        axi_write(
            8'h02,
            32'h0000_0020,
            32'hA5A5_5A5A
        );

        //==============================================================
        // READ #1
        //==============================================================

        $display("--------------------------------------------------------------");
        $display(" READ #1  : Address 0x00000010");
        $display("--------------------------------------------------------------");

        axi_read(
            8'h11,
            32'h0000_0010
        );

        //==============================================================
        // READ #2
        //==============================================================

        $display("--------------------------------------------------------------");
        $display(" READ #2  : Address 0x00000020");
        $display("--------------------------------------------------------------");

        axi_read(
            8'h12,
            32'h0000_0020
        );

        $display("");
        $display("==============================================================");
        $display("                 AXI MASTER TESTBENCH END");
        $display("==============================================================");

        #50;
        $finish;
    end

    //==================================================================
    // AXI WRITE TASK
    //==================================================================

    task axi_write;
        input [ID_WIDTH-1:0]   id;
        input [ADDR_WIDTH-1:0] addr;
        input [DATA_WIDTH-1:0] data;

        begin

            // Present command.
            @(posedge clk);

            wr_cmd_id    <= id;
            wr_cmd_addr  <= addr;
            wr_cmd_len   <= 8'd0;      // one beat
            wr_cmd_size  <= 3'd2;      // 4 bytes
            wr_cmd_burst <= 2'b01;     // INCR
            wr_cmd_valid <= 1'b1;

            while (!wr_cmd_ready)
                @(posedge clk);

            @(posedge clk);
            wr_cmd_valid <= 1'b0;

            $display("[%0t] MASTER: Write command accepted", $time);
            $display("       AWADDR = 0x%08h", addr);
            $display("       AWID   = 0x%02h", id);

            // Present write data.
            wr_data       <= data;
            wr_strb       <= 4'hF;
            wr_data_last  <= 1'b1;
            wr_data_valid <= 1'b1;

            while (!wr_data_ready)
                @(posedge clk);

            @(posedge clk);
            wr_data_valid <= 1'b0;

            $display("[%0t] MASTER: Write data accepted", $time);
            $display("       WDATA  = 0x%08h", data);
            $display("       WSTRB  = 0x%1h", 4'hF);
            $display("       WLAST  = 1");

            // Wait for B response.
            while (!wr_done)
                @(posedge clk);

            if (wr_resp == 2'b00) begin
                $display("[%0t] MASTER: B response = OKAY", $time);
                $display("       WRITE PASS");
            end
            else begin
                $display("[%0t] MASTER: B response = ERROR (%b)", $time, wr_resp);
                $display("       WRITE FAIL");
            end

            $display("");

        end
    endtask

    //==================================================================
    // AXI READ TASK
    //==================================================================

    task axi_read;
        input [ID_WIDTH-1:0]   id;
        input [ADDR_WIDTH-1:0] addr;

        reg [DATA_WIDTH-1:0] expected_data;

        begin

            if (addr == 32'h0000_0010)
                expected_data = 32'h1234_5678;
            else if (addr == 32'h0000_0020)
                expected_data = 32'hA5A5_5A5A;
            else
                expected_data = 32'h0000_0000;

            @(posedge clk);

            rd_cmd_id    <= id;
            rd_cmd_addr  <= addr;
            rd_cmd_len   <= 8'd0;      // one beat
            rd_cmd_size  <= 3'd2;      // 4 bytes
            rd_cmd_burst <= 2'b01;     // INCR
            rd_cmd_valid <= 1'b1;

            while (!rd_cmd_ready)
                @(posedge clk);

            @(posedge clk);
            rd_cmd_valid <= 1'b0;

            $display("[%0t] MASTER: Read command accepted", $time);
            $display("       ARADDR = 0x%08h", addr);
            $display("       ARID   = 0x%02h", id);

            rd_data_ready <= 1'b1;

            while (!rd_data_valid)
                @(posedge clk);

            @(posedge clk);

            $display("[%0t] MASTER: Read data received", $time);
            $display("       RID    = 0x%02h", rd_data_id);
            $display("       RDATA  = 0x%08h", rd_data);
            $display("       RRESP  = %b", rd_data_resp);
            $display("       RLAST  = %b", rd_data_last);

            if ((rd_data == expected_data) &&
                (rd_data_resp == 2'b00) &&
                rd_data_last) begin
                $display("       READ PASS");
            end
            else begin
                $display("       READ FAIL");
                $display("       EXPECTED = 0x%08h", expected_data);
            end

            rd_data_ready <= 1'b0;

            while (!rd_done)
                @(posedge clk);

            $display("[%0t] MASTER: Read transaction complete", $time);
            $display("");

        end
    endtask

    //==================================================================
    // SIMPLE AXI SLAVE MODEL
    //
    // This model accepts AW and W independently and generates B.
    // It accepts AR and returns RDATA from the local memory.
    //==================================================================

    always @(posedge clk) begin

        if (rst) begin

            m_axi_awready <= 1'b0;
            m_axi_wready  <= 1'b0;
            m_axi_bvalid  <= 1'b0;

            m_axi_arready <= 1'b0;
            m_axi_rvalid  <= 1'b0;
            m_axi_rlast  <= 1'b0;

            slave_aw_seen <= 1'b0;
            slave_ar_seen <= 1'b0;

        end
        else begin

            //==========================================================
            // WRITE ADDRESS
            //==========================================================

            m_axi_awready <= 1'b1;

            if (m_axi_awvalid && m_axi_awready) begin

                slave_awaddr    <= m_axi_awaddr;
                slave_awlen     <= m_axi_awlen;
                slave_awsize    <= m_axi_awsize;
                slave_awburst   <= m_axi_awburst;
                slave_aw_seen   <= 1'b1;

                $display("[%0t] SLAVE : AW handshake", $time);
                $display("       AWADDR = 0x%08h", m_axi_awaddr);
                $display("       AWLEN  = %0d", m_axi_awlen);
                $display("       AWSIZE = %0d", m_axi_awsize);
                $display("       AWBURST= %b", m_axi_awburst);

            end

            //==========================================================
            // WRITE DATA
            //==========================================================

            m_axi_wready <= 1'b1;

            if (m_axi_wvalid && m_axi_wready) begin

                if (slave_aw_seen) begin

                    // Address is byte address; divide by 4 for
                    // 32-bit word index.
                    memory[slave_awaddr[9:2]] <= m_axi_wdata;

                    $display("[%0t] SLAVE : W handshake", $time);
                    $display("       WDATA = 0x%08h", m_axi_wdata);
                    $display("       WSTRB = 0x%1h", m_axi_wstrb);
                    $display("       WLAST = %b", m_axi_wlast);

                    m_axi_bid    <= m_axi_awid;
                    m_axi_bresp  <= 2'b00;
                    m_axi_bvalid <= 1'b1;

                    slave_aw_seen <= 1'b0;

                end

            end

            //==========================================================
            // WRITE RESPONSE
            //==========================================================

            if (m_axi_bvalid && m_axi_bready) begin

                $display("[%0t] SLAVE : B handshake", $time);
                $display("       BID   = 0x%02h", m_axi_bid);
                $display("       BRESP = %b", m_axi_bresp);

                m_axi_bvalid <= 1'b0;

            end

            //==========================================================
            // READ ADDRESS
            //==========================================================

            m_axi_arready <= 1'b1;

            if (m_axi_arvalid && m_axi_arready) begin

                slave_araddr  <= m_axi_araddr;
                slave_arlen   <= m_axi_arlen;
                slave_arsize  <= m_axi_arsize;
                slave_arburst <= m_axi_arburst;
                slave_ar_seen <= 1'b1;

                $display("[%0t] SLAVE : AR handshake", $time);
                $display("       ARADDR = 0x%08h", m_axi_araddr);
                $display("       ARLEN  = %0d", m_axi_arlen);
                $display("       ARSIZE = %0d", m_axi_arsize);
                $display("       ARBURST= %b", m_axi_arburst);

            end

            //==========================================================
            // READ DATA
            //==========================================================

            if (slave_ar_seen && !m_axi_rvalid) begin

                m_axi_rid    <= m_axi_arid;
                m_axi_rdata  <= memory[slave_araddr[9:2]];
                m_axi_rresp  <= 2'b00;
                m_axi_rlast  <= 1'b1;
                m_axi_rvalid <= 1'b1;

                slave_ar_seen <= 1'b0;

                $display("[%0t] SLAVE : Preparing RDATA = 0x%08h",
                         $time,
                         memory[slave_araddr[9:2]]);

            end

            //==========================================================
            // READ DATA HANDSHAKE
            //==========================================================

            if (m_axi_rvalid && m_axi_rready) begin

                $display("[%0t] SLAVE : R handshake", $time);
                $display("       RID   = 0x%02h", m_axi_rid);
                $display("       RDATA = 0x%08h", m_axi_rdata);
                $display("       RRESP = %b", m_axi_rresp);
                $display("       RLAST = %b", m_axi_rlast);

                m_axi_rvalid <= 1'b0;
                m_axi_rlast  <= 1'b0;

            end

        end

    end

    //==================================================================
    // TIMEOUT WATCHDOG
    //==================================================================

    initial begin

        #5000;

        $display("");
        $display("ERROR: TESTBENCH TIMEOUT");
        $display("Check AXI VALID/READY handshakes.");
        $finish;

    end

    //==================================================================
    // WAVEFORM DUMP
    //==================================================================

    initial begin
        $dumpfile("axi_master_tb.vcd");
        $dumpvars(0, tb_axi_master);
    end

endmodule

`default_nettype wire
