# Packet Source IP Core — RISC-V VeeR EL2 SoC Packet Buffering

## 1. Overview
The Packet Source IP Core provides external AXI-Stream packet generation for the RISC-V VeeR EL2 SoC. It connects upstream to the Packet FIFO slave interface (`s_axis_*`), feeding variable-length packets, supporting programmable inter-packet gaps, and injecting data/CRC errors on demand for integrity testing.

- **Architecture Reference:** Section 2.11 (External Packet Source)
- **Data Flow:** Packet Source -> Packet FIFO -> CRC Checker
- **Bus Protocol:** 32-bit AXI-Stream Master (`tdata`, `tkeep`, `tlast`, `tvalid`, `tready`)
- **Clock Domain:** `clk` (Synchronous with FIFO write domain `wr_clk`)

## 2. Features
- Programmable packet size in 32-bit words
- Hardware backpressure handling with steady valid/data assertions
- Single triggered packet generation or continuous streaming
- Error injection mode for testing CRC error detection
- Single-cycle `packet_sent_o` completion pulse for driving Packet Counter events

## 3. Hardware Ports
- Clock & Reset: `clk`, `rst_n` (active-low)
- Control: `enable`, `trigger_pulse`, `pkt_words[15:0]`, `inter_pkt_gap[7:0]`, `inject_error`
- AXI-Stream Master: `m_axis_tdata[31:0]`, `m_axis_tkeep[3:0]`, `m_axis_tlast`, `m_axis_tvalid`, `m_axis_tready`
- Status: `packet_sent_o`, `busy_o`

## 4. Verification
Run `./run_sim.sh` to compile and execute the self-checking testbench (`tb_packet_source.v`) with Synopsys VCS.
All tests pass.
