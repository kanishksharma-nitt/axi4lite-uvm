// Bind-able AXI4-Lite protocol assertions: handshake stability, payload
// stability while stalled, no-unknowns, one B per write, legal responses.
`default_nettype none

module axi4_lite_assertions #(
    parameter int ADDR_WIDTH = 8,
    parameter int DATA_WIDTH = 32
) (
    input wire                    aclk,
    input wire                    aresetn,
    input wire [ADDR_WIDTH-1:0]   awaddr,
    input wire                    awvalid,
    input wire                    awready,
    input wire [DATA_WIDTH-1:0]   wdata,
    input wire [DATA_WIDTH/8-1:0] wstrb,
    input wire                    wvalid,
    input wire                    wready,
    input wire [1:0]              bresp,
    input wire                    bvalid,
    input wire                    bready,
    input wire [ADDR_WIDTH-1:0]   araddr,
    input wire                    arvalid,
    input wire                    arready,
    input wire [DATA_WIDTH-1:0]   rdata,
    input wire [1:0]              rresp,
    input wire                    rvalid,
    input wire                    rready
);

  default clocking cb @(posedge aclk); endclocking
  default disable iff (!aresetn);

  // Handshake stability: VALID must hold until READY (AXI A3.2.1).
  property p_valid_stable(valid, ready);
    valid && !ready |=> valid;
  endproperty
  a_awvalid_stable: assert property (p_valid_stable(awvalid, awready))
    else $error("AWVALID dropped before AWREADY");
  a_wvalid_stable : assert property (p_valid_stable(wvalid,  wready))
    else $error("WVALID dropped before WREADY");
  a_bvalid_stable : assert property (p_valid_stable(bvalid,  bready))
    else $error("BVALID dropped before BREADY");
  a_arvalid_stable: assert property (p_valid_stable(arvalid, arready))
    else $error("ARVALID dropped before ARREADY");
  a_rvalid_stable : assert property (p_valid_stable(rvalid,  rready))
    else $error("RVALID dropped before RREADY");

  // Payload stable while stalled (VALID high, READY low).
  a_awaddr_stable: assert property
    (awvalid && !awready |=> $stable(awaddr))
    else $error("AWADDR changed during stall");
  a_wdata_stable: assert property
    (wvalid && !wready |=> $stable(wdata) && $stable(wstrb))
    else $error("WDATA/WSTRB changed during stall");
  a_araddr_stable: assert property
    (arvalid && !arready |=> $stable(araddr))
    else $error("ARADDR changed during stall");

  // No unknowns on qualified signals.
  a_awaddr_known: assert property (awvalid |-> !$isunknown(awaddr));
  a_wdata_known : assert property (wvalid  |-> !$isunknown({wdata, wstrb}));
  a_araddr_known: assert property (arvalid |-> !$isunknown(araddr));
  a_rdata_known : assert property (rvalid  |-> !$isunknown(rdata));

  // Legal response encodings (OKAY=00 or SLVERR=10).
  a_bresp_legal: assert property (bvalid |-> (bresp == 2'b00 || bresp == 2'b10));
  a_rresp_legal: assert property (rvalid |-> (rresp == 2'b00 || rresp == 2'b10));

  // Every accepted write eventually gets a B response.
  wire aw_fire = awvalid && awready;
  wire b_fire  = bvalid  && bready;
  a_write_gets_resp: assert property (aw_fire |-> ##[1:$] b_fire)
    else $error("Accepted write never received a B response");

  // Protocol-corner coverage.
  c_back_to_back_wr: cover property (b_fire ##1 aw_fire);
  c_slverr_write   : cover property (b_fire && bresp == 2'b10);
  c_slverr_read    : cover property (rvalid && rready && rresp == 2'b10);
  c_partial_strobe : cover property (wvalid && wready && (wstrb != '1) && (wstrb != '0));

endmodule

`default_nettype wire
