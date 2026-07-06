// One AXI4-Lite transaction (read or write).
typedef enum bit {AXI_READ = 1'b0, AXI_WRITE = 1'b1} axi_dir_e;

class axi4_lite_seq_item extends uvm_sequence_item;

  rand axi_dir_e               dir;
  rand bit [`AXI_ADDR_W-1:0]   addr;
  rand bit [`AXI_DATA_W-1:0]   data;   // wdata, or rdata filled by the monitor
  rand bit [`AXI_DATA_W/8-1:0] strb;
  bit [1:0]                    resp;   // BRESP/RRESP
  rand int unsigned            delay;  // inter-transaction idle (clocks)

  `uvm_object_utils_begin(axi4_lite_seq_item)
    `uvm_field_enum(axi_dir_e, dir, UVM_ALL_ON)
    `uvm_field_int (addr, UVM_ALL_ON)
    `uvm_field_int (data, UVM_ALL_ON)
    `uvm_field_int (strb, UVM_ALL_ON)
    `uvm_field_int (resp, UVM_ALL_ON | UVM_NOCOMPARE)
    `uvm_field_int (delay, UVM_ALL_ON | UVM_NOCOMPARE)
  `uvm_object_utils_end

  constraint c_align { addr[1:0] == 2'b00; }
  constraint c_strb  { soft strb == '1; }
  constraint c_delay { delay inside {[0:3]}; }

  function new(string name = "axi4_lite_seq_item");
    super.new(name);
  endfunction
endclass
