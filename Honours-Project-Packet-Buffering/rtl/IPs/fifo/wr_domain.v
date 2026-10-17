module wr_domain #(
parameter DATA_WIDTH = 32, 
          DEPTH = 16, 
          ADDR_WIDTH = $clog2(DEPTH), 
          PTR_WIDTH = ADDR_WIDTH + 1, 
          SYNC_STAGES = 2 )(
          
    input wr_clk,
    input wr_rst_n,
    input wr_en,
    input [PTR_WIDTH-1 : 0]rd_gray_sync,
    
    output [PTR_WIDTH-1 : 0]wr_gray_ptr,
    output [ADDR_WIDTH-1 : 0]wr_addr,
    output wr_allow,
    output wr_full,
    output wr_overflow
    );

reg [PTR_WIDTH-1 : 0]wr_bin_ptr;
reg [PTR_WIDTH-1 : 0]wr_gray_ptr_reg;
reg wr_full_reg;
reg [PTR_WIDTH-1 : 0]rd_gray_sync_reg; 
reg wr_overflow_reg;

wire wr_full_next;
wire [PTR_WIDTH-1 : 0]wr_bin_next;
wire [PTR_WIDTH-1 : 0]wr_gray_next;

always @(posedge wr_clk or negedge wr_rst_n)
 begin
   if(!wr_rst_n)
     begin
     wr_bin_ptr        <= {PTR_WIDTH{1'b0}};
     wr_gray_ptr_reg   <= {PTR_WIDTH{1'b0}};
     wr_full_reg       <= 1'b0;
     wr_overflow_reg   <= 1'b0;
     rd_gray_sync_reg  <= {PTR_WIDTH{1'b0}};
     end
   else
     begin
       // Capture synchronized read pointer
      rd_gray_sync_reg <= rd_gray_sync;

      // Update write pointer
      wr_bin_ptr      <= wr_bin_next;
      wr_gray_ptr_reg <= wr_gray_next;

      // Update full flag
      wr_full_reg <= wr_full_next;

      // Overflow detection (write when full)
      wr_overflow_reg <= (wr_en && wr_full_reg);
     end 
end
 
assign wr_allow     = (wr_en && !wr_full);
assign wr_addr      = wr_bin_ptr[ADDR_WIDTH-1:0];
assign wr_bin_next  = wr_bin_ptr + (wr_allow ? 1'b1 : 1'b0); 
assign wr_gray_next = wr_bin_next ^ (wr_bin_next >> 1); 
assign wr_full_next = 
                    (wr_gray_next == 
                        {~rd_gray_sync_reg[PTR_WIDTH-1:PTR_WIDTH-2],   // inverted top 2 bits of rd_gray_sync_reg,
                          rd_gray_sync_reg[PTR_WIDTH-3:0]});           //     remaining lower bits unchanged

assign wr_gray_ptr = wr_gray_ptr_reg;
assign wr_full     = wr_full_reg;
assign wr_overflow = wr_overflow_reg;

endmodule
