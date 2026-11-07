// ============================================================================
// File   : scripts/uart_uvm_tb/uart_test.sv
// ============================================================================

class uart_test extends uvm_test;
    virtual uart_if vif;
    uart_env env;

    `uvm_component_utils(uart_test)

    function new(string n, uvm_component p);
        super.new(n, p);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual uart_if)::get(this, "", "vif", vif)) begin
            void'(uvm_config_db#(virtual uart_if)::get(this, "", "uart_vif", vif));
        end
        if (vif != null) begin
            uvm_config_db#(virtual uart_if)::set(this, "env*", "vif", vif);
        end
        env = uart_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        `uvm_info("UART_TEST", "UART VIP Test active: monitoring UART TX transmitted by RISC-V CPU", UVM_LOW)
        #200ms;
        phase.drop_objection(this);
    endtask
endclass
