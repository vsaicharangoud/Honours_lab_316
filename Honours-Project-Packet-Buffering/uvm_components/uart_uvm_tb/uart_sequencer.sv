class uart_sequencer extends uvm_sequencer #(uart_item);
`uvm_component_utils(uart_sequencer)
function new(string n,uvm_component p);super.new(n,p);endfunction
endclass
