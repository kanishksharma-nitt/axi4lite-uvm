// =============================================================================
// EDA Playground  ->  paste this whole file into the "Design" pane (design.sv)
// =============================================================================
// Contains all synthesizable DUTs. The UVM testbench in testbench.sv selects
// one of them (via `define DUT_AXIL_RAM at the top of the Testbench pane):
//   * default (no define) -> axi4_lite_slave  (internal register-bank slave)
//   * `define DUT_AXIL_RAM -> axil_ram_wrap    (alexforencich/verilog-axi RAM)
// Both DUTs share the identical port signature, so the same UVM env drives
// either one. All three modules below always compile; the unused ones are
// harmless. Nothing in this pane needs editing to switch DUTs.
// =============================================================================
`timescale 1ns/1ps
`default_nettype none

// -----------------------------------------------------------------------------
// Internal DUT: synthesizable AXI4-Lite slave with a NUM_REGS x 32 register
// bank. Byte-strobe writes, SLVERR out of range. STATUS[0] mirrors CTRL[0] and
// STATUS[31:16] counts accepted writes; ID is constant; both are read-only.
// -----------------------------------------------------------------------------
module axi4_lite_slave #(
    parameter int ADDR_WIDTH = 8,
    parameter int DATA_WIDTH = 32,
    parameter int NUM_REGS   = 16
) (
    input  wire                     aclk,
    input  wire                     aresetn,

    input  wire [ADDR_WIDTH-1:0]    awaddr,
    input  wire [2:0]               awprot,
    input  wire                     awvalid,
    output reg                      awready,

    input  wire [DATA_WIDTH-1:0]    wdata,
    input  wire [DATA_WIDTH/8-1:0]  wstrb,
    input  wire                     wvalid,
    output reg                      wready,

    output reg  [1:0]               bresp,
    output reg                      bvalid,
    input  wire                     bready,

    input  wire [ADDR_WIDTH-1:0]    araddr,
    input  wire [2:0]               arprot,
    input  wire                     arvalid,
    output reg                      arready,

    output reg  [DATA_WIDTH-1:0]    rdata,
    output reg  [1:0]               rresp,
    output reg                      rvalid,
    input  wire                     rready
);

  localparam logic [1:0] RESP_OKAY   = 2'b00;
  localparam logic [1:0] RESP_SLVERR = 2'b10;

  localparam int REG_IDX_BITS = $clog2(NUM_REGS);
  localparam int LSB          = $clog2(DATA_WIDTH/8);

  logic [DATA_WIDTH-1:0] regs [NUM_REGS];

  localparam logic [REG_IDX_BITS-1:0] IDX_STATUS = 1;  // 0x04
  localparam logic [REG_IDX_BITS-1:0] IDX_ID     = 3;  // 0x0C
  localparam logic [31:0] ID_VALUE = 32'h5A5A_0001;

  // Accept a write when AW and W are both valid and any prior B has drained.
  wire do_write = awvalid && wvalid && ~awready && ~wready &&
                  (~bvalid || bready);

  always_ff @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
      awready <= 1'b0;
      wready  <= 1'b0;
    end else begin
      awready <= do_write;
      wready  <= do_write;
    end
  end

  wire [REG_IDX_BITS-1:0] wr_index    = awaddr[LSB +: REG_IDX_BITS];
  wire                    wr_in_range = (32'(awaddr) >> LSB) < NUM_REGS;
  wire                    wr_is_ro    = (wr_index == IDX_STATUS) ||
                                        (wr_index == IDX_ID);

  integer bi;
  always_ff @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
      for (bi = 0; bi < NUM_REGS; bi = bi + 1) regs[bi] <= '0;
    end else begin
      if (do_write && wr_in_range && !wr_is_ro) begin
        for (bi = 0; bi < DATA_WIDTH/8; bi = bi + 1)
          if (wstrb[bi]) regs[wr_index][bi*8 +: 8] <= wdata[bi*8 +: 8];
      end
      // STATUS mirrors CTRL[0] and counts accepted writes.
      regs[IDX_STATUS][0] <= regs[0][0];
      if (do_write && wr_in_range && !wr_is_ro)
        regs[IDX_STATUS][31:16] <= regs[IDX_STATUS][31:16] + 1'b1;
    end
  end

  always_ff @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
      bvalid <= 1'b0;
      bresp  <= RESP_OKAY;
    end else begin
      if (do_write) begin
        bvalid <= 1'b1;
        bresp  <= wr_in_range ? RESP_OKAY : RESP_SLVERR;
      end else if (bvalid && bready) begin
        bvalid <= 1'b0;
      end
    end
  end

  wire do_read = arvalid && ~arready && (~rvalid || rready);

  wire [REG_IDX_BITS-1:0] rd_index    = araddr[LSB +: REG_IDX_BITS];
  wire                    rd_in_range = (32'(araddr) >> LSB) < NUM_REGS;

  always_ff @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
      arready <= 1'b0;
      rvalid  <= 1'b0;
      rresp   <= RESP_OKAY;
      rdata   <= '0;
    end else begin
      arready <= 1'b0;
      if (do_read) begin
        arready <= 1'b1;
        rvalid  <= 1'b1;
        rresp   <= rd_in_range ? RESP_OKAY : RESP_SLVERR;
        if (!rd_in_range)            rdata <= 32'hDEAD_DEAD;
        else if (rd_index == IDX_ID) rdata <= ID_VALUE;
        else                          rdata <= regs[rd_index];
      end else if (rvalid && rready) begin
        rvalid <= 1'b0;
      end
    end
  end

endmodule

`default_nettype wire

// -----------------------------------------------------------------------------
// Third-party DUT (only used with +define+DUT_AXIL_RAM):
// alexforencich/verilog-axi  axil_ram, plus a thin wrapper that maps its
// s_axil_* ports and active-high reset to the axi4_lite_slave signature.
//
// Copyright (c) 2018 Alex Forencich  (MIT License) - verbatim from verilog-axi.
// -----------------------------------------------------------------------------
`resetall
`timescale 1ns / 1ps
`default_nettype none

module axil_ram #
(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 16,
    parameter STRB_WIDTH = (DATA_WIDTH/8),
    parameter PIPELINE_OUTPUT = 0
)
(
    input  wire                   clk,
    input  wire                   rst,

    input  wire [ADDR_WIDTH-1:0]  s_axil_awaddr,
    input  wire [2:0]             s_axil_awprot,
    input  wire                   s_axil_awvalid,
    output wire                   s_axil_awready,
    input  wire [DATA_WIDTH-1:0]  s_axil_wdata,
    input  wire [STRB_WIDTH-1:0]  s_axil_wstrb,
    input  wire                   s_axil_wvalid,
    output wire                   s_axil_wready,
    output wire [1:0]             s_axil_bresp,
    output wire                   s_axil_bvalid,
    input  wire                   s_axil_bready,
    input  wire [ADDR_WIDTH-1:0]  s_axil_araddr,
    input  wire [2:0]             s_axil_arprot,
    input  wire                   s_axil_arvalid,
    output wire                   s_axil_arready,
    output wire [DATA_WIDTH-1:0]  s_axil_rdata,
    output wire [1:0]             s_axil_rresp,
    output wire                   s_axil_rvalid,
    input  wire                   s_axil_rready
);

parameter VALID_ADDR_WIDTH = ADDR_WIDTH - $clog2(STRB_WIDTH);
parameter WORD_WIDTH = STRB_WIDTH;
parameter WORD_SIZE = DATA_WIDTH/WORD_WIDTH;

reg mem_wr_en;
reg mem_rd_en;

reg s_axil_awready_reg = 1'b0, s_axil_awready_next;
reg s_axil_wready_reg = 1'b0, s_axil_wready_next;
reg s_axil_bvalid_reg = 1'b0, s_axil_bvalid_next;
reg s_axil_arready_reg = 1'b0, s_axil_arready_next;
reg [DATA_WIDTH-1:0] s_axil_rdata_reg = {DATA_WIDTH{1'b0}}, s_axil_rdata_next;
reg s_axil_rvalid_reg = 1'b0, s_axil_rvalid_next;
reg [DATA_WIDTH-1:0] s_axil_rdata_pipe_reg = {DATA_WIDTH{1'b0}};
reg s_axil_rvalid_pipe_reg = 1'b0;

reg [DATA_WIDTH-1:0] mem[(2**VALID_ADDR_WIDTH)-1:0];

wire [VALID_ADDR_WIDTH-1:0] s_axil_awaddr_valid = s_axil_awaddr >> (ADDR_WIDTH - VALID_ADDR_WIDTH);
wire [VALID_ADDR_WIDTH-1:0] s_axil_araddr_valid = s_axil_araddr >> (ADDR_WIDTH - VALID_ADDR_WIDTH);

assign s_axil_awready = s_axil_awready_reg;
assign s_axil_wready = s_axil_wready_reg;
assign s_axil_bresp = 2'b00;
assign s_axil_bvalid = s_axil_bvalid_reg;
assign s_axil_arready = s_axil_arready_reg;
assign s_axil_rdata = PIPELINE_OUTPUT ? s_axil_rdata_pipe_reg : s_axil_rdata_reg;
assign s_axil_rresp = 2'b00;
assign s_axil_rvalid = PIPELINE_OUTPUT ? s_axil_rvalid_pipe_reg : s_axil_rvalid_reg;

integer i, j;

initial begin
    for (i = 0; i < 2**VALID_ADDR_WIDTH; i = i + 2**(VALID_ADDR_WIDTH/2)) begin
        for (j = i; j < i + 2**(VALID_ADDR_WIDTH/2); j = j + 1) begin
            mem[j] = 0;
        end
    end
end

always @* begin
    mem_wr_en = 1'b0;

    s_axil_awready_next = 1'b0;
    s_axil_wready_next = 1'b0;
    s_axil_bvalid_next = s_axil_bvalid_reg && !s_axil_bready;

    if (s_axil_awvalid && s_axil_wvalid && (!s_axil_bvalid || s_axil_bready) && (!s_axil_awready && !s_axil_wready)) begin
        s_axil_awready_next = 1'b1;
        s_axil_wready_next = 1'b1;
        s_axil_bvalid_next = 1'b1;

        mem_wr_en = 1'b1;
    end
end

always @(posedge clk) begin
    s_axil_awready_reg <= s_axil_awready_next;
    s_axil_wready_reg <= s_axil_wready_next;
    s_axil_bvalid_reg <= s_axil_bvalid_next;

    for (i = 0; i < WORD_WIDTH; i = i + 1) begin
        if (mem_wr_en && s_axil_wstrb[i]) begin
            mem[s_axil_awaddr_valid][WORD_SIZE*i +: WORD_SIZE] <= s_axil_wdata[WORD_SIZE*i +: WORD_SIZE];
        end
    end

    if (rst) begin
        s_axil_awready_reg <= 1'b0;
        s_axil_wready_reg <= 1'b0;
        s_axil_bvalid_reg <= 1'b0;
    end
end

always @* begin
    mem_rd_en = 1'b0;

    s_axil_arready_next = 1'b0;
    s_axil_rvalid_next = s_axil_rvalid_reg && !(s_axil_rready || (PIPELINE_OUTPUT && !s_axil_rvalid_pipe_reg));

    if (s_axil_arvalid && (!s_axil_rvalid || s_axil_rready || (PIPELINE_OUTPUT && !s_axil_rvalid_pipe_reg)) && (!s_axil_arready)) begin
        s_axil_arready_next = 1'b1;
        s_axil_rvalid_next = 1'b1;

        mem_rd_en = 1'b1;
    end
end

always @(posedge clk) begin
    s_axil_arready_reg <= s_axil_arready_next;
    s_axil_rvalid_reg <= s_axil_rvalid_next;

    if (mem_rd_en) begin
        s_axil_rdata_reg <= mem[s_axil_araddr_valid];
    end

    if (!s_axil_rvalid_pipe_reg || s_axil_rready) begin
        s_axil_rdata_pipe_reg <= s_axil_rdata_reg;
        s_axil_rvalid_pipe_reg <= s_axil_rvalid_reg;
    end

    if (rst) begin
        s_axil_arready_reg <= 1'b0;
        s_axil_rvalid_reg <= 1'b0;
        s_axil_rvalid_pipe_reg <= 1'b0;
    end
end

endmodule

`resetall

// Wrapper: presents axil_ram with the axi4_lite_slave port signature.
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
