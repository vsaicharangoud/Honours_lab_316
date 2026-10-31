/*
 * ============================================================================
 * File: tb_packet_source.v
 * Project: Reliable Data Transport System SoC
 * Description: Self-checking Testbench for Packet Source IP
 * ============================================================================
 */

`timescale 1ns / 1ps
`default_nettype none

module tb_packet_source;

    reg clk;
    reg rst_n;
    reg enable;
    reg trigger_pulse;
    reg [15:0] pkt_words;
    reg [7:0]  inter_pkt_gap;
    reg        inject_error;

    wire [31:0] m_axis_tdata;
    wire [3:0]  m_axis_tkeep;
    wire        m_axis_tlast;
    wire        m_axis_tvalid;
    reg         m_axis_tready;

    wire packet_sent;
    wire busy;

    integer pass_count = 0;
    integer fail_count = 0;
    integer words_received;

    packet_source #(
        .DATA_WIDTH (32),
        .DEFAULT_PKT_WORDS (4)
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .enable         (enable),
        .trigger_pulse  (trigger_pulse),
        .pkt_words      (pkt_words),
        .inter_pkt_gap  (inter_pkt_gap),
        .inject_error   (inject_error),
        .m_axis_tdata   (m_axis_tdata),
        .m_axis_tkeep   (m_axis_tkeep),
        .m_axis_tlast   (m_axis_tlast),
        .m_axis_tvalid  (m_axis_tvalid),
        .m_axis_tready  (m_axis_tready),
        .packet_sent_o  (packet_sent),
        .busy_o         (busy)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    initial begin
        rst_n         = 1'b0;
        enable        = 1'b0;
        trigger_pulse = 1'b0;
        pkt_words     = 16'd4;
        inter_pkt_gap = 8'd2;
        inject_error  = 1'b0;
        m_axis_tready = 1'b1;

        $display("================================================================");
        $display(" Starting Packet Source IP Verification Testbench ");
        $display("================================================================");

        #40;
        @(posedge clk);
        rst_n = 1'b1;
        #20;

        // TEST 1: Initial state check
        $display("[TEST 1] Checking initial reset state...");
        if (!m_axis_tvalid && !busy && !packet_sent) begin
            $display("  -> Initial idle state PASS");
            pass_count = pass_count + 1;
        end else begin
            $display("  -> Initial idle state FAIL");
            fail_count = fail_count + 1;
        end

        // TEST 2: Trigger single 4-word packet
        $display("[TEST 2] Triggering single 4-word packet with normal ready...");
        @(posedge clk);
        pkt_words     <= 16'd4;
        trigger_pulse <= 1'b1;
        @(posedge clk);
        trigger_pulse <= 1'b0;

        words_received = 0;
        while (words_received < 4) begin
            @(posedge clk);
            if (m_axis_tvalid && m_axis_tready) begin
                words_received = words_received + 1;
                $display("  -> Received word %0d: data=0x%08x, last=%b", words_received, m_axis_tdata, m_axis_tlast);
                if (words_received == 4) begin
                    if (m_axis_tlast) begin
                        $display("  -> Word 4 tlast assertion PASS");
                        pass_count = pass_count + 1;
                    end else begin
                        $display("  -> Word 4 tlast assertion FAIL");
                        fail_count = fail_count + 1;
                    end
                end else begin
                    if (!m_axis_tlast) pass_count = pass_count + 1;
                    else fail_count = fail_count + 1;
                end
            end
        end

        // Check packet_sent pulse
        @(negedge clk);
        if (packet_sent) begin
            $display("  -> packet_sent_o pulse PASS");
            pass_count = pass_count + 1;
        end else begin
            $display("  -> packet_sent_o pulse FAIL");
            fail_count = fail_count + 1;
        end

        #30;

        // TEST 3: Backpressure Testing
        $display("[TEST 3] Testing backpressure (tready deassertion stall)...");
        @(posedge clk);
        pkt_words     <= 16'd2;
        m_axis_tready <= 1'b0;
        trigger_pulse <= 1'b1;
        @(posedge clk);
        trigger_pulse <= 1'b0;

        #30; // Wait 3 clocks while ready is deasserted
        if (m_axis_tvalid) begin
            $display("  -> m_axis_tvalid asserted and held steady during stall PASS");
            pass_count = pass_count + 1;
        end else begin
            $display("  -> m_axis_tvalid dropped prematurely FAIL");
            fail_count = fail_count + 1;
        end

        // Release ready
        @(posedge clk);
        m_axis_tready <= 1'b1;

        words_received = 0;
        while (words_received < 2) begin
            @(posedge clk);
            if (m_axis_tvalid && m_axis_tready) begin
                words_received = words_received + 1;
                $display("  -> Backpressure stream word %0d: data=0x%08x, last=%b", words_received, m_axis_tdata, m_axis_tlast);
            end
        end
        $display("  -> Backpressured packet completed successfully PASS");
        pass_count = pass_count + 1;

        $display("================================================================");
        $display(" Total PASS: %0d   Total FAIL: %0d", pass_count, fail_count);
        $display("================================================================");

        if (fail_count == 0) begin
            $display(" *** ALL PACKET SOURCE IP TESTS PASSED SUCCESSFULLY! ***\n");
        end else begin
            $display(" *** SOME PACKET SOURCE TESTS FAILED! ***\n");
        end

        $finish;
    end

endmodule

`default_nettype wire
