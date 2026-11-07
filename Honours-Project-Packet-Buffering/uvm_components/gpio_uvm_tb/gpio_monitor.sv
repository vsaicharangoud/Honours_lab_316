class gpio_monitor extends uvm_monitor;
virtual gpio_if vif;
uvm_analysis_port #(gpio_item) ap;
`uvm_component_utils(gpio_monitor)
function new(string n,uvm_component p); super.new(n,p); ap=new("ap",this); endfunction
endclass
