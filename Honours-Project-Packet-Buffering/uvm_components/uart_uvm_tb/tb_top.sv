module tb_top;
import uvm_pkg::*; import uart_pkg::*;
uart_if vif();
initial run_test("uart_test");
endmodule
