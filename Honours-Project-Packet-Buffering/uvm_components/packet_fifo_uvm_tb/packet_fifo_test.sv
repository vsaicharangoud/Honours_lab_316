class packet_fifo_test extends uvm_test;
packet_fifo_env env;
`uvm_component_utils(packet_fifo_test)
function new(string n,uvm_component p);super.new(n,p);endfunction
function void build_phase(uvm_phase phase); env=packet_fifo_env::type_id::create("env",this); endfunction
endclass
