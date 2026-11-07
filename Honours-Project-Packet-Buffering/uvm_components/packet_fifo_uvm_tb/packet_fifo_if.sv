`ifndef PACKET_FIFO_IF_SV
`define PACKET_FIFO_IF_SV
interface packet_fifo_if;
logic clk;
logic [31:0] ext_axis_tdata;
logic ext_axis_tvalid;
logic ext_axis_tlast;
logic ext_axis_tready;
endinterface
`endif
