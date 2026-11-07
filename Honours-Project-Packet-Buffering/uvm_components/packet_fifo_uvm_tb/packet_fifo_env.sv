class packet_fifo_env extends uvm_env;
packet_fifo_agent agent; packet_fifo_scoreboard sb;
`uvm_component_utils(packet_fifo_env)
function new(string n,uvm_component p);super.new(n,p);endfunction
function void build_phase(uvm_phase phase); agent=packet_fifo_agent::type_id::create("agent",this); sb=packet_fifo_scoreboard::type_id::create("sb",this); endfunction
endclass
