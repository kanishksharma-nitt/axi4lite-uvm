// AXI4-Lite interface with driver/monitor clocking blocks.
`default_nettype none

interface axi4_lite_if #(
    parameter int ADDR_WIDTH = 8,
    parameter int DATA_WIDTH = 32
) (input wire aclk, input wire aresetn);

  localparam int STRB_WIDTH = DATA_WIDTH/8;

  logic [ADDR_WIDTH-1:0] awaddr;
  logic [2:0]            awprot;
  logic                  awvalid, awready;
  logic [DATA_WIDTH-1:0] wdata;
  logic [STRB_WIDTH-1:0] wstrb;
  logic                  wvalid, wready;
  logic [1:0]            bresp;
  logic                  bvalid, bready;
  logic [ADDR_WIDTH-1:0] araddr;
  logic [2:0]            arprot;
  logic                  arvalid, arready;
  logic [DATA_WIDTH-1:0] rdata;
  logic [1:0]            rresp;
  logic                  rvalid, rready;

  // Master driver view.
  clocking drv_cb @(posedge aclk);
    default input #1step output #1ns;
    output awaddr, awprot, awvalid, wdata, wstrb, wvalid, bready,
           araddr, arprot, arvalid, rready;
    input  awready, wready, bresp, bvalid, arready, rdata, rresp, rvalid;
  endclocking

  // Passive monitor view.
  clocking mon_cb @(posedge aclk);
    default input #1step;
    input awaddr, awprot, awvalid, awready, wdata, wstrb, wvalid, wready,
          bresp, bvalid, bready, araddr, arprot, arvalid, arready,
          rdata, rresp, rvalid, rready;
  endclocking

  modport drv (clocking drv_cb, input aclk, input aresetn);
  modport mon (clocking mon_cb, input aclk, input aresetn);
endinterface

`default_nettype wire
