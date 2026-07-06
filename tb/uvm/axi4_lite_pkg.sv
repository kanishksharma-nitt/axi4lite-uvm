// UVM environment package (import axi4_lite_pkg::*).
`ifndef AXI4_LITE_PKG_SV
`define AXI4_LITE_PKG_SV

`define AXI_ADDR_W   8
`define AXI_DATA_W   32
`define AXI_NUM_REGS 16
`define AXI_IDX_HI   5          // addr[5:2] selects one of 16 words

`define AXI_IDX_CTRL    0
`define AXI_IDX_STATUS  1
`define AXI_IDX_ID      3

`define AXI_A_CTRL    8'h00
`define AXI_A_STATUS  8'h04
`define AXI_A_SCRATCH 8'h08
`define AXI_A_ID      8'h0C
`define AXI_A_OOR     8'h80     // out-of-range address (>= 0x40)

`define AXI_ID_VALUE  32'h5A5A_0001

package axi4_lite_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  `include "axi4_lite_seq_item.sv"
  `include "axi4_lite_agent.sv"
  `include "axi4_lite_coverage.sv"
  `include "axi4_lite_scoreboard.sv"
  `include "axi4_lite_ral.sv"
  `include "axi4_lite_env.sv"
  `include "axi4_lite_seq_lib.sv"
  `include "axi4_lite_test_lib.sv"
endpackage

`endif
