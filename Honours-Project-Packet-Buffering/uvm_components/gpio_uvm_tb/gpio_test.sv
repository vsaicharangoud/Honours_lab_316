class gpio_test extends uvm_test;
gpio_env env;
`uvm_component_utils(gpio_test)
function new(string n,uvm_component p);super.new(n,p);endfunction
function void build_phase(uvm_phase phase); env=gpio_env::type_id::create("env",this); endfunction
endclass
