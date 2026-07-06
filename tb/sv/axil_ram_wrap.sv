// Presents axil_ram (rtl/third_party/verilog-axi) with the same port signature
// as axi4_lite_slave: bridges the s_axil_* names and active-high reset.
`default_nettype none

module axil_ram_wrap #(
    parameter int ADDR_WIDTH = 8,
    parameter int DATA_WIDTH = 32,
    parameter int NUM_REGS   = 16   // unused; port-compatible with axi4_lite_slave
) (
    input  wire                     aclk,
    input  wire                     aresetn,

    input  wire [ADDR_WIDTH-1:0]    awaddr,
    input  wire [2:0]               awprot,
    input  wire                     awvalid,
    output wire                     awready,

    input  wire [DATA_WIDTH-1:0]    wdata,
    input  wire [DATA_WIDTH/8-1:0]  wstrb,
    input  wire                     wvalid,
    output wire                     wready,

    output wire [1:0]               bresp,
    output wire                     bvalid,
    input  wire                     bready,

    input  wire [ADDR_WIDTH-1:0]    araddr,
    input  wire [2:0]               arprot,
    input  wire                     arvalid,
    output wire                     arready,

    output wire [DATA_WIDTH-1:0]    rdata,
    output wire [1:0]               rresp,
    output wire                     rvalid,
    input  wire                     rready
);

  axil_ram #(
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH),
    .PIPELINE_OUTPUT(0)
  ) u_axil_ram (
    .clk           (aclk),
    .rst           (~aresetn),

    .s_axil_awaddr (awaddr),
    .s_axil_awprot (awprot),
    .s_axil_awvalid(awvalid),
    .s_axil_awready(awready),
    .s_axil_wdata  (wdata),
    .s_axil_wstrb  (wstrb),
    .s_axil_wvalid (wvalid),
    .s_axil_wready (wready),
    .s_axil_bresp  (bresp),
    .s_axil_bvalid (bvalid),
    .s_axil_bready (bready),
    .s_axil_araddr (araddr),
    .s_axil_arprot (arprot),
    .s_axil_arvalid(arvalid),
    .s_axil_arready(arready),
    .s_axil_rdata  (rdata),
    .s_axil_rresp  (rresp),
    .s_axil_rvalid (rvalid),
    .s_axil_rready (rready)
  );

endmodule

`default_nettype wire
