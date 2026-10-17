module sync_ptr #(
parameter PTR_WIDTH = 5, 
          SYNC_STAGES = 2 )(
          
    input clk_dest,
    input rst_dest_n,
    input [PTR_WIDTH-1 : 0]ptr_gray_src,   // Gray pointer from source domain
    
    output [PTR_WIDTH-1 : 0]ptr_gray_sync  // Safe synchronized pointer
);

reg [PTR_WIDTH-1 : 0] sync_reg [0 : SYNC_STAGES-1];
integer i;

always @(posedge clk_dest or negedge rst_dest_n)
begin
 if(!rst_dest_n)
  begin
   for( i = 0; i < (SYNC_STAGES); i=i+1)
      sync_reg[i] <= {PTR_WIDTH{1'b0}};
  end 
 else
  begin
   sync_reg[0] <= ptr_gray_src;
  
   for(i = 1; i < SYNC_STAGES; i = i + 1)
     sync_reg[i] <= sync_reg[i-1];
  end
end

assign ptr_gray_sync = sync_reg[SYNC_STAGES-1];
endmodule
