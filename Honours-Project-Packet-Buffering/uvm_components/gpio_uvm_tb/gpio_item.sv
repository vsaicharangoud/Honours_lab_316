class gpio_item extends uvm_sequence_item;

  rand bit [31:0] gpio_i;
  bit [31:0] gpio_o;
  bit [31:0] gpio_oe;

  `uvm_object_utils(gpio_item)

  function new(string name="gpio_item"); super.new(name); endfunction
endclass
