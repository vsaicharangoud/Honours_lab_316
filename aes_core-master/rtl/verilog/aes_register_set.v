`timescale 1ns/1ps

//======================================================================
// AES REGISTER SET
//
// AXI-side interface:
//   reg_wr_en    : one-cycle write strobe from AXI slave
//   reg_wr_addr  : byte address
//   reg_wr_data  : 32-bit write data
//   reg_wr_strb  : byte enables
//   reg_rd_en    : read request from AXI slave
//   reg_rd_addr  : byte address
//   reg_rd_data  : 32-bit read data
//
// AES-side interface:
//   aes_key      : 128-bit AES key
//   aes_text_in  : 128-bit plaintext/cipher input
//   aes_ld       : load/start pulse for aes_cipher_top
//   aes_text_out : ciphertext/result from AES core
//   aes_done     : completion pulse from AES core
//
// IMPORTANT:
// The supplied aes_cipher_top.v uses:
//     if(!rst) ... reset
// Therefore "rst" below is ACTIVE-LOW and should be connected directly
// to the reset used by aes_cipher_top.
//
// Register map:
//   0x0000 CONTROL   R/W
//          bit 0 = START (write 1 -> one-cycle aes_ld pulse)
//          bit 1 = CLEAR_DONE (write 1 -> clear software-visible done)
//          bit 2 = SOFT_RESET (write 1 -> clear key/input/output/status)
//
//   0x0004 STATUS    R
//          bit 0 = DONE (latched after aes_done)
//          bit 1 = BUSY
//          bit 2 = KEY_VALID
//          bit 3 = INPUT_VALID
//
//   0x0010 KEY0      R/W   AES key [127:96]
//   0x0014 KEY1      R/W   AES key [95:64]
//   0x0018 KEY2      R/W   AES key [63:32]
//   0x001C KEY3      R/W   AES key [31:0]
//
//   0x0020 TEXT_IN0  R/W   plaintext [127:96]
//   0x0024 TEXT_IN1  R/W   plaintext [95:64]
//   0x0028 TEXT_IN2  R/W   plaintext [63:32]
//   0x002C TEXT_IN3  R/W   plaintext [31:0]
//
//   0x0030 TEXT_OUT0 R     ciphertext [127:96]
//   0x0034 TEXT_OUT1 R     ciphertext [95:64]
//   0x0038 TEXT_OUT2 R     ciphertext [63:32]
//   0x003C TEXT_OUT3 R     ciphertext [31:0]
//
//======================================================================

module aes_register_set #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input  wire                  clk,
    input  wire                  rst,          // ACTIVE-LOW

    //==================================================================
    // Register interface from AXI slave
    //==================================================================
    input  wire                  reg_wr_en,
    input  wire [ADDR_WIDTH-1:0] reg_wr_addr,
    input  wire [DATA_WIDTH-1:0] reg_wr_data,
    input  wire [3:0]            reg_wr_strb,

    input  wire                  reg_rd_en,
    input  wire [ADDR_WIDTH-1:0] reg_rd_addr,
    output reg  [DATA_WIDTH-1:0] reg_rd_data,

    //==================================================================
    // AES encryption core interface
    //==================================================================
    output wire [127:0]           aes_key,
    output wire [127:0]           aes_text_in,
    output reg                    aes_ld,

    input  wire [127:0]           aes_text_out,
    input  wire                    aes_done
);

    //==================================================================
    // Address definitions
    //==================================================================

    localparam [ADDR_WIDTH-1:0] ADDR_CONTROL   = 32'h0000_0000;
    localparam [ADDR_WIDTH-1:0] ADDR_STATUS    = 32'h0000_0004;

    localparam [ADDR_WIDTH-1:0] ADDR_KEY0      = 32'h0000_0010;
    localparam [ADDR_WIDTH-1:0] ADDR_KEY1      = 32'h0000_0014;
    localparam [ADDR_WIDTH-1:0] ADDR_KEY2      = 32'h0000_0018;
    localparam [ADDR_WIDTH-1:0] ADDR_KEY3      = 32'h0000_001C;

    localparam [ADDR_WIDTH-1:0] ADDR_TEXT_IN0  = 32'h0000_0020;
    localparam [ADDR_WIDTH-1:0] ADDR_TEXT_IN1  = 32'h0000_0024;
    localparam [ADDR_WIDTH-1:0] ADDR_TEXT_IN2  = 32'h0000_0028;
    localparam [ADDR_WIDTH-1:0] ADDR_TEXT_IN3  = 32'h0000_002C;

    localparam [ADDR_WIDTH-1:0] ADDR_TEXT_OUT0 = 32'h0000_0030;
    localparam [ADDR_WIDTH-1:0] ADDR_TEXT_OUT1 = 32'h0000_0034;
    localparam [ADDR_WIDTH-1:0] ADDR_TEXT_OUT2 = 32'h0000_0038;
    localparam [ADDR_WIDTH-1:0] ADDR_TEXT_OUT3 = 32'h0000_003C;

    //==================================================================
    // Internal registers
    //==================================================================

    reg [127:0] key_reg;
    reg [127:0] text_in_reg;
    reg [127:0] text_out_reg;

    reg         done_reg;
    reg         busy_reg;
    reg         key_valid_reg;
    reg         input_valid_reg;

    //==================================================================
    // AES outputs
    //
    // These remain stable while the register set is operating.
    //==================================================================

    assign aes_key     = key_reg;
    assign aes_text_in = text_in_reg;

    //==================================================================
    // Byte-enable helper
    //
    // WSTRB[0] -> DATA[7:0]
    // WSTRB[1] -> DATA[15:8]
    // WSTRB[2] -> DATA[23:16]
    // WSTRB[3] -> DATA[31:24]
    //==================================================================

    //==================================================================
    // WRITE LOGIC
    //==================================================================

    always @(posedge clk) begin

        if (!rst) begin

            key_reg        <= 128'd0;
            text_in_reg    <= 128'd0;
            text_out_reg   <= 128'd0;

            done_reg       <= 1'b0;
            busy_reg       <= 1'b0;
            key_valid_reg  <= 1'b0;
            input_valid_reg <= 1'b0;

            aes_ld         <= 1'b0;
        end

        else begin

            // Default: START is a one-clock pulse.
            aes_ld <= 1'b0;

            //==========================================================
            // Capture AES completion
            //==========================================================

            if (aes_done) begin
                text_out_reg <= aes_text_out;
                done_reg     <= 1'b1;
                busy_reg     <= 1'b0;
            end

            //==========================================================
            // AXI/register WRITE
            //==========================================================

            if (reg_wr_en) begin

                case (reg_wr_addr)

                    //==================================================
                    // CONTROL
                    //==================================================
                    ADDR_CONTROL: begin

                        // Bit 0: START
                        if (reg_wr_strb[0] && reg_wr_data[0]) begin
                            aes_ld   <= 1'b1;
                            done_reg <= 1'b0;
                            busy_reg <= 1'b1;
                        end

                        // Bit 1: CLEAR_DONE
                        if (reg_wr_strb[0] && reg_wr_data[1]) begin
                            done_reg <= 1'b0;
                        end

                        // Bit 2: SOFT_RESET
                        if (reg_wr_strb[0] && reg_wr_data[2]) begin
                            key_reg         <= 128'd0;
                            text_in_reg     <= 128'd0;
                            text_out_reg    <= 128'd0;
                            done_reg        <= 1'b0;
                            busy_reg        <= 1'b0;
                            key_valid_reg   <= 1'b0;
                            input_valid_reg <= 1'b0;
                        end

                    end

                    //==================================================
                    // KEY[127:96]
                    //==================================================
                    ADDR_KEY0: begin
                        if (reg_wr_strb[0]) key_reg[103:96] <= reg_wr_data[7:0];
                        if (reg_wr_strb[1]) key_reg[111:104] <= reg_wr_data[15:8];
                        if (reg_wr_strb[2]) key_reg[119:112] <= reg_wr_data[23:16];
                        if (reg_wr_strb[3]) key_reg[127:120] <= reg_wr_data[31:24];
                        key_valid_reg <= 1'b1;
                    end

                    //==================================================
                    // KEY[95:64]
                    //==================================================
                    ADDR_KEY1: begin
                        if (reg_wr_strb[0]) key_reg[71:64] <= reg_wr_data[7:0];
                        if (reg_wr_strb[1]) key_reg[79:72] <= reg_wr_data[15:8];
                        if (reg_wr_strb[2]) key_reg[87:80] <= reg_wr_data[23:16];
                        if (reg_wr_strb[3]) key_reg[95:88] <= reg_wr_data[31:24];
                        key_valid_reg <= 1'b1;
                    end

                    //==================================================
                    // KEY[63:32]
                    //==================================================
                    ADDR_KEY2: begin
                        if (reg_wr_strb[0]) key_reg[39:32] <= reg_wr_data[7:0];
                        if (reg_wr_strb[1]) key_reg[47:40] <= reg_wr_data[15:8];
                        if (reg_wr_strb[2]) key_reg[55:48] <= reg_wr_data[23:16];
                        if (reg_wr_strb[3]) key_reg[63:56] <= reg_wr_data[31:24];
                        key_valid_reg <= 1'b1;
                    end

                    //==================================================
                    // KEY[31:0]
                    //==================================================
                    ADDR_KEY3: begin
                        if (reg_wr_strb[0]) key_reg[7:0]  <= reg_wr_data[7:0];
                        if (reg_wr_strb[1]) key_reg[15:8] <= reg_wr_data[15:8];
                        if (reg_wr_strb[2]) key_reg[23:16] <= reg_wr_data[23:16];
                        if (reg_wr_strb[3]) key_reg[31:24] <= reg_wr_data[31:24];
                        key_valid_reg <= 1'b1;
                    end

                    //==================================================
                    // TEXT_IN[127:96]
                    //==================================================
                    ADDR_TEXT_IN0: begin
                        if (reg_wr_strb[0]) text_in_reg[103:96] <= reg_wr_data[7:0];
                        if (reg_wr_strb[1]) text_in_reg[111:104] <= reg_wr_data[15:8];
                        if (reg_wr_strb[2]) text_in_reg[119:112] <= reg_wr_data[23:16];
                        if (reg_wr_strb[3]) text_in_reg[127:120] <= reg_wr_data[31:24];
                        input_valid_reg <= 1'b1;
                    end

                    //==================================================
                    // TEXT_IN[95:64]
                    //==================================================
                    ADDR_TEXT_IN1: begin
                        if (reg_wr_strb[0]) text_in_reg[71:64] <= reg_wr_data[7:0];
                        if (reg_wr_strb[1]) text_in_reg[79:72] <= reg_wr_data[15:8];
                        if (reg_wr_strb[2]) text_in_reg[87:80] <= reg_wr_data[23:16];
                        if (reg_wr_strb[3]) text_in_reg[95:88] <= reg_wr_data[31:24];
                        input_valid_reg <= 1'b1;
                    end

                    //==================================================
                    // TEXT_IN[63:32]
                    //==================================================
                    ADDR_TEXT_IN2: begin
                        if (reg_wr_strb[0]) text_in_reg[39:32] <= reg_wr_data[7:0];
                        if (reg_wr_strb[1]) text_in_reg[47:40] <= reg_wr_data[15:8];
                        if (reg_wr_strb[2]) text_in_reg[55:48] <= reg_wr_data[23:16];
                        if (reg_wr_strb[3]) text_in_reg[63:56] <= reg_wr_data[31:24];
                        input_valid_reg <= 1'b1;
                    end

                    //==================================================
                    // TEXT_IN[31:0]
                    //==================================================
                    ADDR_TEXT_IN3: begin
                        if (reg_wr_strb[0]) text_in_reg[7:0]  <= reg_wr_data[7:0];
                        if (reg_wr_strb[1]) text_in_reg[15:8] <= reg_wr_data[15:8];
                        if (reg_wr_strb[2]) text_in_reg[23:16] <= reg_wr_data[23:16];
                        if (reg_wr_strb[3]) text_in_reg[31:24] <= reg_wr_data[31:24];
                        input_valid_reg <= 1'b1;
                    end

                    default: begin
                        // Read-only or unmapped address: ignore write.
                    end

                endcase

            end

        end

    end

    //==================================================================
    // READ LOGIC
    //
    // Register reads are combinational. The AXI slave can therefore
    // sample reg_rd_data when it services reg_rd_addr.
    //==================================================================

    always @(*) begin

        reg_rd_data = 32'h0000_0000;

        if (reg_rd_en) begin

            case (reg_rd_addr)

                //======================================================
                // CONTROL
                //======================================================
                ADDR_CONTROL: begin
                    reg_rd_data = 32'h0000_0000;
                end

                //======================================================
                // STATUS
                //======================================================
                ADDR_STATUS: begin
                    reg_rd_data = 32'h0000_0000;

                    reg_rd_data[0] = done_reg;
                    reg_rd_data[1] = busy_reg;
                    reg_rd_data[2] = key_valid_reg;
                    reg_rd_data[3] = input_valid_reg;
                end

                //======================================================
                // KEY
                //======================================================
                ADDR_KEY0: begin
                    reg_rd_data = key_reg[127:96];
                end

                ADDR_KEY1: begin
                    reg_rd_data = key_reg[95:64];
                end

                ADDR_KEY2: begin
                    reg_rd_data = key_reg[63:32];
                end

                ADDR_KEY3: begin
                    reg_rd_data = key_reg[31:0];
                end

                //======================================================
                // TEXT INPUT
                //======================================================
                ADDR_TEXT_IN0: begin
                    reg_rd_data = text_in_reg[127:96];
                end

                ADDR_TEXT_IN1: begin
                    reg_rd_data = text_in_reg[95:64];
                end

                ADDR_TEXT_IN2: begin
                    reg_rd_data = text_in_reg[63:32];
                end

                ADDR_TEXT_IN3: begin
                    reg_rd_data = text_in_reg[31:0];
                end

                //======================================================
                // TEXT OUTPUT
                //======================================================
                ADDR_TEXT_OUT0: begin
                    reg_rd_data = text_out_reg[127:96];
                end

                ADDR_TEXT_OUT1: begin
                    reg_rd_data = text_out_reg[95:64];
                end

                ADDR_TEXT_OUT2: begin
                    reg_rd_data = text_out_reg[63:32];
                end

                ADDR_TEXT_OUT3: begin
                    reg_rd_data = text_out_reg[31:0];
                end

                default: begin
                    reg_rd_data = 32'h0000_0000;
                end

            endcase

        end

    end

endmodule
