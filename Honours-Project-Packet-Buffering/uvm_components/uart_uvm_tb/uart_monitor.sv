// ============================================================================
// File   : scripts/uart_uvm_tb/uart_monitor.sv
// Description: UART VIP Monitor watching UART_TX and printing received bytes
// ============================================================================

class uart_monitor extends uvm_monitor;
    virtual uart_if vif;
    uvm_analysis_port #(uart_item) ap;

    `uvm_component_utils(uart_monitor)

    function new(string n, uvm_component p);
        super.new(n, p);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual uart_if)::get(this, "", "vif", vif)) begin
            void'(uvm_config_db#(virtual uart_if)::get(this, "", "uart_vif", vif));
        end
    endfunction

    task run_phase(uvm_phase phase);
        realtime bit_period = 8680.55ns; // 115200 baud (50MHz / 434)
        bit [7:0] rx_byte;
        string rx_buffer = "";

        if (vif == null) begin
            if (!uvm_config_db#(virtual uart_if)::get(this, "", "vif", vif)) begin
                void'(uvm_config_db#(virtual uart_if)::get(this, "", "uart_vif", vif));
            end
        end

        `uvm_info("UART_VIP_MONITOR", "UART VIP Monitor started run_phase. Monitoring vif.UART_TX...", UVM_LOW)
        $display("[UART VIP MONITOR] Started watching UART TX interface at time %0t", $realtime);

        forever begin
            // Wait for start bit (falling edge on UART_TX, which idles high)
            @(negedge vif.UART_TX);

            // Wait 1.5 bit periods to sample at the center of data bit 0
            #(bit_period * 1.5);

            // Sample 8 data bits (LSB first)
            for (int i = 0; i < 8; i++) begin
                rx_byte[i] = vif.UART_TX;
                if (i < 7) #(bit_period);
            end

            // Wait through stop bit
            #(bit_period);

            // Print each received byte in the monitor
            `uvm_info("UART_VIP_MONITOR", $sformatf("Received Byte from UART TX: 0x%02X ('%c')",
                      rx_byte, (rx_byte >= 32 && rx_byte < 127) ? rx_byte : 8'h2E), UVM_NONE)
            $display("[UART VIP MONITOR] >>> DATA RECEIVED FROM UART TX: 0x%02X ('%c') at time %0t <<<",
                     rx_byte, (rx_byte >= 32 && rx_byte < 127) ? rx_byte : 8'h2E, $realtime);

            // Broadcast on analysis port
            begin
                uart_item item = uart_item::type_id::create("item");
                item.UART_TX = vif.UART_TX;
                ap.write(item);
            end

            // Accumulate and print full line
            if (rx_byte == 8'h0A || rx_byte == 8'h0D) begin
                if (rx_buffer.len() > 0) begin
                    $display("[UART VIP MONITOR] >>> COMPLETE STRING CAPTURED: \"%s\" <<<", rx_buffer);
                    rx_buffer = "";
                end
            end else begin
                rx_buffer = {rx_buffer, string'(rx_byte)};
            end
        end
    endtask
endclass
