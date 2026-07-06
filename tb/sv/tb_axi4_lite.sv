// Self-checking testbench for the open-source flow. Runs the register-bank
// slave, or axil_ram with +define+DUT_AXIL_RAM, against an inline reference
// model. Plusargs: +NUM_TRANS=<n> (default 400), +SEED=<n>.
`default_nettype none
`timescale 1ns/1ps
module tb_axi4_lite;
  localparam int ADDR_WIDTH = 8;
  localparam logic [1:0]  OKAY = 2'b00, SLVERR = 2'b10;

  // register-bank DUT
  localparam int NUM_REGS   = 16;
  localparam int IDX_CTRL   = 0;
  localparam int IDX_STATUS = 1;
  localparam int IDX_ID     = 3;
  localparam logic [31:0] ID_VALUE = 32'h5A5A_0001;

  // axil_ram DUT
  localparam int RAM_WORDS  = (1 << (ADDR_WIDTH - 2));

  logic aclk = 0, aresetn = 0;
  always #5 aclk = ~aclk;

  logic [ADDR_WIDTH-1:0] awaddr;
  logic [2:0]  awprot = 0;
  logic        awvalid, awready;
  logic [31:0] wdata;
  logic [3:0]  wstrb;
  logic        wvalid, wready;
  logic [1:0]  bresp;
  logic        bvalid, bready;
  logic [ADDR_WIDTH-1:0] araddr;
  logic [2:0]  arprot = 0;
  logic        arvalid, arready;
  logic [31:0] rdata;
  logic [1:0]  rresp;
  logic        rvalid, rready;

`ifdef DUT_AXIL_RAM
  axil_ram_wrap #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(32)) dut (.*);
`else
  axi4_lite_slave #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(32), .NUM_REGS(NUM_REGS)) dut (.*);
`endif

  // Reference model for the selected DUT.
`ifdef DUT_AXIL_RAM
  // Plain RAM: all aligned addresses are RW, reads return last write, no SLVERR.
  logic [31:0] ref_mem[RAM_WORDS];

  function automatic logic [1:0] ref_write(logic [ADDR_WIDTH-1:0] addr,
                                           logic [31:0] data, logic [3:0] strb);
    int idx = (addr >> 2);
    for (int b = 0; b < 4; b++)
      if (strb[b]) ref_mem[idx][b*8+:8] = data[b*8+:8];
    return OKAY;
  endfunction

  task automatic ref_read(input logic [ADDR_WIDTH-1:0] addr,
                          output logic [31:0] data, output logic [1:0] resp);
    data = ref_mem[addr >> 2];
    resp = OKAY;
  endtask
`else
  // Register-bank slave: RO STATUS/ID, write counter, SLVERR out of range.
  logic [31:0] ref_regs[NUM_REGS];
  int unsigned ref_wr_count;

  function automatic logic [1:0] ref_write(logic [ADDR_WIDTH-1:0] addr,
                                           logic [31:0] data, logic [3:0] strb);
    int idx;
    if ((addr >> 2) >= NUM_REGS) return SLVERR;
    idx = (addr >> 2);
    if (idx != IDX_STATUS && idx != IDX_ID) begin
      for (int b = 0; b < 4; b++)
        if (strb[b]) ref_regs[idx][b*8+:8] = data[b*8+:8];
      ref_wr_count++;
    end
    return OKAY;
  endfunction

  task automatic ref_read(input logic [ADDR_WIDTH-1:0] addr,
                          output logic [31:0] data, output logic [1:0] resp);
    int idx;
    if ((addr >> 2) >= NUM_REGS) begin data = 32'hDEAD_DEAD; resp = SLVERR; end
    else begin
      idx = (addr >> 2);
      if (idx == IDX_ID) begin data = ID_VALUE; resp = OKAY; end
      else if (idx == IDX_STATUS) begin
        data = {ref_wr_count[15:0], 15'b0, ref_regs[IDX_CTRL][0]};
        resp = OKAY;
      end else begin
        data = ref_regs[idx];
        resp = OKAY;
      end
    end
  endtask
`endif

  // AXI4-Lite master BFM. bvalid/rvalid can assert in the same cycle as the
  // address-channel ready, so wait on the response before advancing.
  task automatic axi_write(input logic [ADDR_WIDTH-1:0] addr, input logic [31:0] data,
                            input logic [3:0] strb, output logic [1:0] resp);
    awaddr = addr; awvalid = 1;
    wdata = data; wstrb = strb; wvalid = 1;
    bready = 1;
    do @(posedge aclk); while (!(awready && wready));
    awvalid = 0; wvalid = 0;
    while (!bvalid) @(posedge aclk);
    resp = bresp;
    bready = 0;
  endtask

  task automatic axi_read(input logic [ADDR_WIDTH-1:0] addr, output logic [31:0] data,
                           output logic [1:0] resp);
    araddr = addr; arvalid = 1;
    rready = 1;
    do @(posedge aclk); while (!arready);
    arvalid = 0;
    while (!rvalid) @(posedge aclk);
    data = rdata; resp = rresp;
    rready = 0;
  endtask

  int errors = 0;

  task automatic check_write(input logic [ADDR_WIDTH-1:0] addr, input logic [31:0] data,
                              input logic [3:0] strb = 4'hF);
    logic [1:0] got, exp;
    exp = ref_write(addr, data, strb);
    axi_write(addr, data, strb, got);
    if (got !== exp) begin
      errors++;
      $display("FAIL write @%0h: resp exp=%0b got=%0b", addr, exp, got);
    end
  endtask

  task automatic check_read(input logic [ADDR_WIDTH-1:0] addr);
    logic [31:0] got_d, exp_d;
    logic [1:0]  got_r, exp_r;
    ref_read(addr, exp_d, exp_r);
    axi_read(addr, got_d, got_r);
    if (got_r !== exp_r || got_d !== exp_d) begin
      errors++;
      $display("FAIL read @%0h: resp exp=%0b got=%0b data exp=%0h got=%0h",
                addr, exp_r, got_r, exp_d, got_d);
    end
  endtask

  // axil_ram keeps its contents across reset, so its model isn't cleared here.
  task automatic reset_dut;
    aresetn = 0;
    awvalid = 0; wvalid = 0; bready = 0; arvalid = 0; rready = 0;
`ifndef DUT_AXIL_RAM
    for (int i = 0; i < NUM_REGS; i++) ref_regs[i] = 0;
    ref_wr_count = 0;
`endif
    repeat (5) @(posedge aclk);
    aresetn = 1;
    @(posedge aclk);
  endtask

`ifdef DUT_AXIL_RAM
  task automatic test_smoke;
    reset_dut();
    check_write(8'h00, 32'h12345678); check_read(8'h00);
    check_write(8'h04, 32'hDEADBEEF); check_read(8'h04);
    check_write(8'h40, 32'hCAFEF00D); check_read(8'h40);
    check_read(8'h08);                // never written -> 0
    check_write(8'h00, 32'hA5A5A5A5); check_read(8'h00);  // overwrite
    $display("smoke test done (errors so far: %0d)", errors);
  endtask
`else
  // Directed walk over the register map.
  task automatic test_smoke;
    reset_dut();
    check_write(8'h00, 32'h1);
    check_read(8'h00);
    check_read(8'h04);           // STATUS[0] mirrors CTRL[0]
    check_write(8'h08, 32'hDEADBEEF);
    check_read(8'h08);
    check_read(8'h0C);           // constant 0x5A5A0001
    check_write(8'h0C, 32'hFFFFFFFF); // RO -> ignored
    check_read(8'h0C);
    $display("smoke test done (errors so far: %0d)", errors);
  endtask
`endif

  task automatic test_byte_strobes;
    reset_dut();
    check_write(8'h08, 32'h00000000, 4'hF);
    check_write(8'h08, 32'hAABBCCDD, 4'h1);
    check_read(8'h08);
    check_write(8'h08, 32'h11223344, 4'hC);
    check_read(8'h08);
    $display("byte-strobe test done (errors so far: %0d)", errors);
  endtask

`ifndef DUT_AXIL_RAM
  task automatic test_error_response;   // out-of-range -> SLVERR
    reset_dut();
    check_write(8'h80, 32'h12345678);
    check_read(8'h80);
    $display("error-response test done (errors so far: %0d)", errors);
  endtask
`endif

  // Constrained-random reads/writes checked against the reference model.
  task automatic test_random_regression(int n, int seed_in);
    logic [ADDR_WIDTH-1:0] addr;
    logic [31:0] data;
    logic [3:0]  strb;
    int r;
    int seed;
    seed = seed_in; // $random(seed) mutates its argument; keep seed_in for reporting
    reset_dut();
    for (int i = 0; i < n; i++) begin
`ifdef DUT_AXIL_RAM
      addr = ({$random(seed)} % RAM_WORDS) << 2;
`else
      // bias toward in-range registers, with some out-of-range accesses
      r = {$random(seed)} % 10;
      addr = (r < 7) ? (({$random(seed)} % 16) << 2) : (64 + (({$random(seed)} % 48) << 2));
`endif
      if (({$random(seed)} % 2) == 0) begin
        data = $random(seed);
        r = {$random(seed)} % 7;
        strb = (r == 0) ? 4'h1 : (r == 1) ? 4'h3 : (r == 2) ? 4'hC : (r == 3) ? 4'h8 : 4'hF;
        check_write(addr, data, strb);
      end else begin
        check_read(addr);
      end
    end
    $display("random regression done: %0d transactions, seed=%0d (errors so far: %0d)", n, seed_in, errors);
  endtask

  int num_trans;
  int seed;
  initial begin
    if (!$value$plusargs("NUM_TRANS=%d", num_trans)) num_trans = 400;
    if (!$value$plusargs("SEED=%d", seed)) seed = 1;
`ifdef DUT_AXIL_RAM
    for (int i = 0; i < RAM_WORDS; i++) ref_mem[i] = 0;
    $display("=== DUT: axil_ram (alexforencich/verilog-axi) ===");
`else
    $display("=== DUT: axi4_lite_slave (internal) ===");
`endif

    test_smoke();
    test_byte_strobes();
`ifndef DUT_AXIL_RAM
    test_error_response();
`endif
    test_random_regression(num_trans, seed);

    if (errors == 0) $display("TEST PASSED");
    else $display("TEST FAILED (%0d error(s))", errors);
    $finish;
  end

  initial begin
    $dumpfile("tb_axi4_lite.vcd");
    $dumpvars(0, tb_axi4_lite);
  end
endmodule
`default_nettype wire
