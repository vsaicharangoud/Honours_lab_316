// ============================================================================
// File   : scripts/uart_uvm_tb/uart_driver.sv
// ============================================================================

class uart_driver extends uvm_driver #(uart_item);
    virtual uart_if vif;

    `uvm_component_utils(uart_driver)

    function new(string n, uvm_component p);
        super.new(n, p);
    endfunction

    task run_phase(uvm_phase phase);
        if (vif == null) begin
            if (!uvm_config_db#(virtual uart_if)::get(this, "", "vif", vif)) begin
                void'(uvm_config_db#(virtual uart_if)::get(this, "", "uart_vif", vif));
            end
        end
        if (vif != null) begin
            forever begin
                seq_item_port.get_next_item(req);
                @(posedge vif.clk);
                seq_item_port.item_done();
            end
        end
    endtask
endclass
