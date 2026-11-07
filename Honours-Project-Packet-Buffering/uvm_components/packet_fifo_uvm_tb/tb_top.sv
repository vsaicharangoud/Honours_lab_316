module tb_top;
import uvm_pkg::*; import packet_fifo_pkg::*;
packet_fifo_if vif();
initial run_test("packet_fifo_test");
endmodule
