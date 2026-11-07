class packet_fifo_item extends uvm_sequence_item;

  rand bit [31:0] ext_axis_tdata;
  rand bit ext_axis_tvalid;
  rand bit ext_axis_tlast;
  bit ext_axis_tready;

  `uvm_object_utils(packet_fifo_item)

  function new(string name="packet_fifo_item"); super.new(name); endfunction
endclass
