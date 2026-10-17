module fifo_mem #(
parameter DATA_WIDTH = 32, 
          DEPTH = 16, 
          ADDR_WIDTH = $clog2(DEPTH)
          )(
    input wr_clk,
    input [DATA_WIDTH-1 : 0]wr_data,
    input wr_en,
    input [ADDR_WIDTH-1 : 0]wr_addr,
    
    input rd_clk,
    input [ADDR_WIDTH-1 : 0]rd_addr,
    output reg [DATA_WIDTH-1 : 0]rd_data
    );
    

reg [DATA_WIDTH-1 : 0] mem [0 : DEPTH-1];

always @(posedge wr_clk)
   if(wr_en)
      mem[wr_addr] <= wr_data;

always @(posedge rd_clk)
   rd_data <= mem[rd_addr];
endmodule
