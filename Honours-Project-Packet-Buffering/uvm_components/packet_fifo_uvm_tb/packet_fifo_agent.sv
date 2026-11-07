class packet_fifo_agent extends uvm_agent;
packet_fifo_driver drv; packet_fifo_monitor mon; packet_fifo_sequencer seqr;
`uvm_component_utils(packet_fifo_agent)
function new(string n,uvm_component p);super.new(n,p);endfunction
function void build_phase(uvm_phase phase); drv=packet_fifo_driver::type_id::create("drv",this); mon=packet_fifo_monitor::type_id::create("mon",this); seqr=packet_fifo_sequencer::type_id::create("seqr",this); endfunction
function void connect_phase(uvm_phase phase); drv.seq_item_port.connect(seqr.seq_item_export); endfunction
endclass
