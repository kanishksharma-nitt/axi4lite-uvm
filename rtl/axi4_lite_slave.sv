// AXI4-Lite slave, NUM_REGS x 32 register bank. Byte-strobe writes, SLVERR
// out of range. STATUS and ID are read-only.
`default_nettype none

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

  // accept a write once AW and W are valid and any prior B has drained
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
