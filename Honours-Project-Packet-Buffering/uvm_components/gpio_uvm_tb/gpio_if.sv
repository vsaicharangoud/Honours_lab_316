`ifndef GPIO_IF_SV
`define GPIO_IF_SV
interface gpio_if;
logic clk;
logic [31:0] gpio_i;
logic [31:0] gpio_o;
logic [31:0] gpio_oe;
endinterface
`endif
