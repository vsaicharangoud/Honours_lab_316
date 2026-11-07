class packet_fifo_monitor extends uvm_monitor;
virtual packet_fifo_if vif;
uvm_analysis_port #(packet_fifo_item) ap;
`uvm_component_utils(packet_fifo_monitor)
function new(string n,uvm_component p); super.new(n,p); ap=new("ap",this); endfunction
endclass
