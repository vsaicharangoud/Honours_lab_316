module fifo_diag#(
parameter PTR_WIDTH = 5,
        STUCK_THRESHOLD = 16
        )   (
    // Write domain signals      
    input wr_clk,
    input wr_rst_n, 
    input wr_en,
    input wr_full,
    input [PTR_WIDTH-1 : 0]wr_gray_ptr, 
    input wr_overflow,
    input wr_diag_clear,
    
    // Read domain signals
    input rd_clk, 
    input rd_rst_n, 
    input rd_en,
    input rd_empty,
    input [PTR_WIDTH-1 : 0]rd_gray_ptr, 
    input rd_underflow,
    input rd_diag_clear,
        
    // Write domain outputs
    output wr_gray_error,
    output wr_overflow_sticky,
    output wr_pointer_stuck,
    
    // Read domain outputs
    output rd_gray_error,
    output rd_underflow_sticky,
    output rd_pointer_stuck
    );

reg [PTR_WIDTH-1:0] prev_wr_gray;
reg wr_gray_error_reg;
wire [PTR_WIDTH-1:0] wr_diff;

reg [PTR_WIDTH-1:0] prev_rd_gray;
reg rd_gray_error_reg;
wire [PTR_WIDTH-1:0] rd_diff;

reg wr_overflow_sticky_reg;
reg rd_underflow_sticky_reg;

reg [$clog2(STUCK_THRESHOLD+1)-1:0] wr_stuck_count;
reg wr_pointer_stuck_reg;
reg [$clog2(STUCK_THRESHOLD+1)-1:0] rd_stuck_count;
reg rd_pointer_stuck_reg;

always @(posedge wr_clk or negedge wr_rst_n) 
begin
    if (!wr_rst_n) begin
        prev_wr_gray           <= {PTR_WIDTH{1'b0}};
        wr_gray_error_reg      <= 1'b0;
        wr_overflow_sticky_reg <= 1'b0;
        wr_stuck_count        <= 0;
        wr_pointer_stuck_reg  <= 1'b0;
    end
    else if (wr_diag_clear) begin
        wr_gray_error_reg      <= 1'b0;
        wr_overflow_sticky_reg <= 1'b0;
        wr_pointer_stuck_reg   <= 1'b0;
    end
    else begin
        // Gray violation detection
        if (wr_diff != 0 && (wr_diff & (wr_diff - 1)) != 0)
            wr_gray_error_reg <= 1'b1;

        // Overflow sticky
        if (wr_overflow)
            wr_overflow_sticky_reg <= 1'b1;
            
        // WR Pointer Stuck    
        if (wr_en && !wr_full) 
        begin
            if (wr_diff == 0) 
            begin
                if (wr_stuck_count == STUCK_THRESHOLD)
                    wr_pointer_stuck_reg <= 1'b1;
                else
                    wr_stuck_count <= wr_stuck_count + 1'b1;
            end
            else begin
                wr_stuck_count <= 0;
            end
        end
        else begin
            wr_stuck_count <= 0;
        end

        // Update previous pointer
        prev_wr_gray <= wr_gray_ptr;
    end
end

always @(posedge rd_clk or negedge rd_rst_n) begin
    if (!rd_rst_n) begin
        prev_rd_gray      <= {PTR_WIDTH{1'b0}};
        rd_gray_error_reg <= 1'b0;
        rd_underflow_sticky_reg <= 1'b0;
        rd_stuck_count        <= 0;
        rd_pointer_stuck_reg  <= 1'b0;
    end
    else if (rd_diag_clear) begin
        rd_gray_error_reg       <= 1'b0;
        rd_underflow_sticky_reg <= 1'b0;
        rd_pointer_stuck_reg    <= 1'b0;
    end
    else begin
    
        // Gray violation detection
        if (rd_diff != 0 && (rd_diff & (rd_diff - 1)) != 0)
            rd_gray_error_reg <= 1'b1;
        
        // Overflow sticky
        if (rd_underflow)
            rd_underflow_sticky_reg <= 1'b1;
            
        // RD Pointer Stuck    
        if (rd_en && !rd_empty) 
        begin
            if (rd_diff == 0) 
            begin
                if (rd_stuck_count == STUCK_THRESHOLD)
                    rd_pointer_stuck_reg <= 1'b1;
                else
                    rd_stuck_count <= rd_stuck_count + 1'b1;
            end
            else begin
                rd_stuck_count <= 0;
            end
        end
        else begin
            rd_stuck_count <= 0;
        end             

        // Update previous pointer
        prev_rd_gray <= rd_gray_ptr;
    end
end

assign wr_diff = wr_gray_ptr ^ prev_wr_gray;
assign rd_diff = rd_gray_ptr ^ prev_rd_gray;

assign wr_gray_error       = wr_gray_error_reg;
assign rd_gray_error       = rd_gray_error_reg;
assign wr_overflow_sticky  = wr_overflow_sticky_reg;
assign rd_underflow_sticky = rd_underflow_sticky_reg;
assign wr_pointer_stuck    = wr_pointer_stuck_reg;
assign rd_pointer_stuck    = rd_pointer_stuck_reg;

endmodule
