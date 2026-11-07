class gpio_sequencer extends uvm_sequencer #(gpio_item);
`uvm_component_utils(gpio_sequencer)
function new(string n,uvm_component p);super.new(n,p);endfunction
endclass
