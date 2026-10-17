module rd_domain #(
parameter DATA_WIDTH = 32, 
          DEPTH = 16, 
          ADDR_WIDTH = $clog2(DEPTH), 
          PTR_WIDTH = ADDR_WIDTH + 1, 
          SYNC_STAGES = 2 )(

   input rd_clk,
   input rd_rst_n,
   input rd_en,
   input [PTR_WIDTH-1 : 0]wr_gray_sync,
   
   output [PTR_WIDTH-1 : 0]rd_gray_ptr,
   output [ADDR_WIDTH-1 : 0]rd_addr,
   output rd_empty,
   output rd_valid,
   output rd_underflow   
);

reg [PTR_WIDTH-1 : 0]rd_bin_ptr;
reg [PTR_WIDTH-1 : 0]rd_gray_ptr_reg;
reg rd_empty_reg;
reg rd_underflow_reg;
reg [PTR_WIDTH-1 : 0]wr_gray_sync_reg;

wire [PTR_WIDTH-1 : 0]rd_bin_next;
wire [PTR_WIDTH-1 : 0]rd_gray_next;
wire rd_empty_next;
wire rd_allow;


always @(posedge rd_clk or negedge rd_rst_n)
begin
  if(!rd_rst_n)
    begin
     rd_bin_ptr        <= {PTR_WIDTH{1'b0}};
     rd_gray_ptr_reg   <= {PTR_WIDTH{1'b0}};
     rd_empty_reg      <= 1'b1;
     rd_underflow_reg  <= 1'b0;
     wr_gray_sync_reg  <= {PTR_WIDTH{1'b0}};
    end
  else 
    begin
     
     wr_gray_sync_reg  <= wr_gray_sync;
     
     rd_bin_ptr      <= rd_bin_next;
     rd_gray_ptr_reg <= rd_gray_next;
     
     rd_empty_reg <= rd_empty_next;
     
     rd_underflow_reg <= (rd_en && rd_empty_reg);
    end
end


assign rd_allow      = rd_en && !rd_empty_reg;
assign rd_bin_next   = rd_bin_ptr + (rd_allow ? 1 : 0);
assign rd_gray_next  = rd_bin_next ^ (rd_bin_next >> 1);
assign rd_empty_next = rd_gray_next == wr_gray_sync_reg;

assign rd_gray_ptr  = rd_gray_ptr_reg;
assign rd_addr      = rd_bin_ptr[ADDR_WIDTH-1 : 0];
assign rd_empty     = rd_empty_reg;
assign rd_valid     = rd_allow;
assign rd_underflow = rd_underflow_reg;  

endmodule
