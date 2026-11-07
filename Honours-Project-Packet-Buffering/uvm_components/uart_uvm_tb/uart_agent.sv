// ============================================================================
// File   : scripts/uart_uvm_tb/uart_agent.sv
// ============================================================================

class uart_agent extends uvm_agent;
    virtual uart_if vif;
    uart_driver drv;
    uart_monitor mon;
    uart_sequencer seqr;

    `uvm_component_utils(uart_agent)

    function new(string n, uvm_component p);
        super.new(n, p);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual uart_if)::get(this, "", "vif", vif)) begin
            void'(uvm_config_db#(virtual uart_if)::get(this, "", "uart_vif", vif));
        end
        drv  = uart_driver::type_id::create("drv", this);
        mon  = uart_monitor::type_id::create("mon", this);
        seqr = uart_sequencer::type_id::create("seqr", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        drv.seq_item_port.connect(seqr.seq_item_export);
        if (vif != null) begin
            mon.vif = vif;
            drv.vif = vif;
        end
    endfunction
endclass
