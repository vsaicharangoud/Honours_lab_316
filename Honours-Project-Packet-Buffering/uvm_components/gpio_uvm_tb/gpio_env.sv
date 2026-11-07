class gpio_env extends uvm_env;
gpio_agent agent; gpio_scoreboard sb;
`uvm_component_utils(gpio_env)
function new(string n,uvm_component p);super.new(n,p);endfunction
function void build_phase(uvm_phase phase); agent=gpio_agent::type_id::create("agent",this); sb=gpio_scoreboard::type_id::create("sb",this); endfunction
endclass
