module async_fifo_top  #(
parameter DATA_WIDTH = 32, 
          DEPTH = 16,  
          SYNC_STAGES = 2 )(
    
    // Write Side Interface
    input wr_clk,
    input wr_rst_n,
    input wr_en,
    input [DATA_WIDTH-1 : 0]wr_data,
    output wr_full,
    output wr_overflow,

    // Read Side Interface
    input rd_clk,
    input rd_rst_n,
    input rd_en,
    output [DATA_WIDTH-1 : 0]rd_data,
    output rd_empty,
    output rd_valid,
    output rd_underflow,
    
    // Write diagnostic inputs & outputs
    input  wr_diag_clear,
    output wr_gray_error,
    output wr_overflow_sticky,
    output wr_pointer_stuck,
    
    // Read diagnostic inputs & outputs
    input  rd_diag_clear,
    output rd_gray_error,
    output rd_underflow_sticky,
    output rd_pointer_stuck
    );
    
 
localparam ADDR_WIDTH = $clog2(DEPTH);
localparam PTR_WIDTH  = ADDR_WIDTH + 1;   
    
// Between Write Domain and Sync
wire [PTR_WIDTH-1:0] wr_gray_ptr;
wire [PTR_WIDTH-1:0] rd_gray_ptr;
// Synchronized Versions
wire [PTR_WIDTH-1:0] wr_gray_sync;
wire [PTR_WIDTH-1:0] rd_gray_sync;
// Memory Interface
wire [ADDR_WIDTH-1:0] wr_addr;
wire [ADDR_WIDTH-1:0] rd_addr;
wire wr_allow;


wr_domain #(
    .DATA_WIDTH(DATA_WIDTH), 
    .DEPTH(DEPTH), 
    .ADDR_WIDTH(ADDR_WIDTH), 
    .PTR_WIDTH(PTR_WIDTH), 
    .SYNC_STAGES(SYNC_STAGES)
    ) WR_Domain(
    .wr_clk(wr_clk), 
    .wr_rst_n(wr_rst_n), 
    .wr_en(wr_en), 
    .rd_gray_sync(rd_gray_sync),
    .wr_gray_ptr(wr_gray_ptr),
    .wr_addr(wr_addr),
    .wr_allow(wr_allow),
    .wr_full(wr_full),
    .wr_overflow(wr_overflow)
      );


rd_domain #(
    .DATA_WIDTH(DATA_WIDTH), 
    .DEPTH(DEPTH), 
    .ADDR_WIDTH(ADDR_WIDTH), 
    .PTR_WIDTH(PTR_WIDTH), 
    .SYNC_STAGES(SYNC_STAGES)
    ) RD_Domain (
    .rd_clk(rd_clk), 
    .rd_rst_n(rd_rst_n), 
    .rd_en(rd_en), 
    .wr_gray_sync(wr_gray_sync),
    .rd_gray_ptr(rd_gray_ptr),
    .rd_addr(rd_addr),
    .rd_valid(rd_valid),
    .rd_empty(rd_empty),
    .rd_underflow(rd_underflow)
      );

// Read pointer ? Write domain
sync_ptr #(
    .PTR_WIDTH(PTR_WIDTH), 
    .SYNC_STAGES(SYNC_STAGES)
    ) u_sync_rd2wr (
   .clk_dest(wr_clk),
   .rst_dest_n(wr_rst_n),
   .ptr_gray_src(rd_gray_ptr),
   .ptr_gray_sync(rd_gray_sync)
);

// Write pointer ? Read domain
sync_ptr #(
    .PTR_WIDTH(PTR_WIDTH), 
    .SYNC_STAGES(SYNC_STAGES)
    ) u_sync_wr2rd (
   .clk_dest(rd_clk),
   .rst_dest_n(rd_rst_n),
   .ptr_gray_src(wr_gray_ptr),
   .ptr_gray_sync(wr_gray_sync)
);

// Instantiate Memory
fifo_mem #(
    .DATA_WIDTH(DATA_WIDTH), 
    .DEPTH(DEPTH), 
    .ADDR_WIDTH(ADDR_WIDTH)
    ) u_mem (
   .wr_clk(wr_clk),
   .wr_en(wr_allow),
   .wr_addr(wr_addr),
   .wr_data(wr_data),

   .rd_clk(rd_clk),
   .rd_addr(rd_addr),
   .rd_data(rd_data)
);

fifo_diag #(
    .PTR_WIDTH(PTR_WIDTH),
    .STUCK_THRESHOLD(16)
) u_fifo_diag (

    // Write domain
    .wr_clk(wr_clk),
    .wr_rst_n(wr_rst_n),
    .wr_en(wr_en),
    .wr_full(wr_full),
    .wr_gray_ptr(wr_gray_ptr),
    .wr_overflow(wr_overflow),
    .wr_diag_clear(wr_diag_clear),

    // Read domain
    .rd_clk(rd_clk),
    .rd_rst_n(rd_rst_n),
    .rd_en(rd_en),
    .rd_empty(rd_empty),
    .rd_gray_ptr(rd_gray_ptr),
    .rd_underflow(rd_underflow),
    .rd_diag_clear(rd_diag_clear),

    // Write outputs
    .wr_gray_error(wr_gray_error),
    .wr_overflow_sticky(wr_overflow_sticky),
    .wr_pointer_stuck(wr_pointer_stuck),

    // Read outputs
    .rd_gray_error(rd_gray_error),
    .rd_underflow_sticky(rd_underflow_sticky),
    .rd_pointer_stuck(rd_pointer_stuck)
);

initial begin
    if ((DEPTH & (DEPTH-1)) != 0)
        $error("DEPTH must be power of 2");
end

endmodule
