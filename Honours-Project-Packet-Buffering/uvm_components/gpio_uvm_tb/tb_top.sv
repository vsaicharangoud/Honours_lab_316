module tb_top;
import uvm_pkg::*; import gpio_pkg::*;
gpio_if vif();
initial run_test("gpio_test");
endmodule
