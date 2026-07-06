// UVM testbench top: clock/reset, DUT, interface, SVA bind.
// Run: vsim -c tb_top +UVM_TESTNAME=axi4_lite_regression_test
`default_nettype none
`timescale 1ns/1ps

module tb_top;
  import uvm_pkg::*;
  import axi4_lite_pkg::*;
  `include "uvm_macros.svh"

  localparam int ADDR_WIDTH = `AXI_ADDR_W;
  localparam int DATA_WIDTH = `AXI_DATA_W;

  // Clock / reset
  logic aclk = 0;
  logic aresetn = 0;
  always #5 aclk = ~aclk;          // 100 MHz

  initial begin
    aresetn = 0;
    repeat (5) @(posedge aclk);
    aresetn = 1;
  end

  // Interface
  axi4_lite_if #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH))
      axi_if (.aclk(aclk), .aresetn(aresetn));

  // DUT: our register-bank slave (default) or, with +define+DUT_AXIL_RAM, the
  // third-party axil_ram (alexforencich/verilog-axi) via axil_ram_wrap, which
  // exposes the identical port signature. Both bind to the same interface.
`ifdef DUT_AXIL_RAM
  axil_ram_wrap #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) dut (
`else
  axi4_lite_slave #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH),
                    .NUM_REGS(`AXI_NUM_REGS)) dut (
`endif
    .aclk(aclk), .aresetn(aresetn),
    .awaddr(axi_if.awaddr), .awprot(axi_if.awprot),
    .awvalid(axi_if.awvalid), .awready(axi_if.awready),
    .wdata(axi_if.wdata), .wstrb(axi_if.wstrb),
    .wvalid(axi_if.wvalid), .wready(axi_if.wready),
    .bresp(axi_if.bresp), .bvalid(axi_if.bvalid), .bready(axi_if.bready),
    .araddr(axi_if.araddr), .arprot(axi_if.arprot),
    .arvalid(axi_if.arvalid), .arready(axi_if.arready),
    .rdata(axi_if.rdata), .rresp(axi_if.rresp),
    .rvalid(axi_if.rvalid), .rready(axi_if.rready)
  );

  // Bind protocol assertions onto the selected DUT. The assertions only look at
  // interface signals, so they apply to either DUT unchanged.
`ifdef DUT_AXIL_RAM
  bind axil_ram_wrap axi4_lite_assertions #(
`else
  bind axi4_lite_slave axi4_lite_assertions #(
`endif
      .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) u_sva (
    .aclk(aclk), .aresetn(aresetn),
    .awaddr(awaddr), .awvalid(awvalid), .awready(awready),
    .wdata(wdata), .wstrb(wstrb), .wvalid(wvalid), .wready(wready),
    .bresp(bresp), .bvalid(bvalid), .bready(bready),
    .araddr(araddr), .arvalid(arvalid), .arready(arready),
    .rdata(rdata), .rresp(rresp), .rvalid(rvalid), .rready(rready)
  );

  // Publish the virtual interface and launch UVM.
  initial begin
    uvm_config_db#(virtual axi4_lite_if)::set(null, "uvm_test_top", "vif", axi_if);
    run_test();
  end

  // Waveform dump (FSDB/VCD depending on tool).
  initial begin
    $dumpfile("tb_top.vcd");
    $dumpvars(0, tb_top);
  end
endmodule

`default_nettype wire
