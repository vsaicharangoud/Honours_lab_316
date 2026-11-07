class packet_fifo_sequencer extends uvm_sequencer #(packet_fifo_item);
`uvm_component_utils(packet_fifo_sequencer)
function new(string n,uvm_component p);super.new(n,p);endfunction
endclass
