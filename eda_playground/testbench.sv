// =============================================================================
// EDA Playground  ->  paste this whole file into the "Testbench" pane
// (testbench.sv). Requires: UVM/OVM = "UVM 1.2", a UVM-capable simulator
// (Aldec Riviera-Pro / Siemens Questa / Synopsys VCS / Cadence Xcelium).
// See README.md in this folder for the exact left-panel settings.
//
// Everything the UVM env needs is inlined here (no include paths):
//   macros -> interface -> package(all classes) -> SVA module -> tb_top.
// The DUT modules live in the Design pane (design.sv).
// =============================================================================
`timescale 1ns/1ps

// ---- Register-map / geometry macros (from axi4_lite_pkg.sv) ------------------
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

// =============================================================================
// AXI4-Lite interface with driver/monitor clocking blocks.
// =============================================================================
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

// =============================================================================
// UVM environment package (all classes inlined in compile order).
// =============================================================================
package axi4_lite_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // ---- axi4_lite_seq_item.sv -------------------------------------------------
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

  // ---- axi4_lite_agent.sv ----------------------------------------------------
  class axi4_lite_agent_cfg extends uvm_object;
    virtual axi4_lite_if vif;
    uvm_active_passive_enum is_active = UVM_ACTIVE;
    `uvm_object_utils(axi4_lite_agent_cfg)
    function new(string name = "axi4_lite_agent_cfg"); super.new(name); endfunction
  endclass

  typedef uvm_sequencer #(axi4_lite_seq_item) axi4_lite_sequencer;

  class axi4_lite_driver extends uvm_driver #(axi4_lite_seq_item);
    `uvm_component_utils(axi4_lite_driver)
    virtual axi4_lite_if vif;
    axi4_lite_agent_cfg  cfg;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(axi4_lite_agent_cfg)::get(this, "", "cfg", cfg))
        `uvm_fatal(get_type_name(), "agent cfg not set")
      vif = cfg.vif;
    endfunction

    task run_phase(uvm_phase phase);
      reset_signals();
      @(posedge vif.aresetn);
      forever begin
        axi4_lite_seq_item tr;
        seq_item_port.get_next_item(tr);
        repeat (tr.delay) @(vif.drv_cb);
        if (tr.dir == AXI_WRITE) drive_write(tr);
        else                     drive_read(tr);
        seq_item_port.item_done();
      end
    endtask

    task reset_signals();
      vif.drv_cb.awvalid <= 1'b0; vif.drv_cb.awaddr <= '0; vif.drv_cb.awprot <= '0;
      vif.drv_cb.wvalid  <= 1'b0; vif.drv_cb.wdata  <= '0; vif.drv_cb.wstrb  <= '0;
      vif.drv_cb.bready  <= 1'b0;
      vif.drv_cb.arvalid <= 1'b0; vif.drv_cb.araddr <= '0; vif.drv_cb.arprot <= '0;
      vif.drv_cb.rready  <= 1'b0;
    endtask

    task drive_write(axi4_lite_seq_item tr);
      @(vif.drv_cb);
      vif.drv_cb.awaddr  <= tr.addr;
      vif.drv_cb.awvalid <= 1'b1;
      vif.drv_cb.wdata   <= tr.data;
      vif.drv_cb.wstrb   <= tr.strb;
      vif.drv_cb.wvalid  <= 1'b1;
      vif.drv_cb.bready  <= 1'b1;
      do @(vif.drv_cb); while (!(vif.drv_cb.awready && vif.drv_cb.wready));
      vif.drv_cb.awvalid <= 1'b0;
      vif.drv_cb.wvalid  <= 1'b0;
      // Check-first: bvalid can assert the same cycle as the AW/W accept, so a
      // wait-first do-while would step past the one-cycle B pulse and hang.
      while (!vif.drv_cb.bvalid) @(vif.drv_cb);
      tr.resp = vif.drv_cb.bresp;
      vif.drv_cb.bready <= 1'b0;
    endtask

    task drive_read(axi4_lite_seq_item tr);
      @(vif.drv_cb);
      vif.drv_cb.araddr  <= tr.addr;
      vif.drv_cb.arvalid <= 1'b1;
      vif.drv_cb.rready  <= 1'b1;
      do @(vif.drv_cb); while (!vif.drv_cb.arready);
      vif.drv_cb.arvalid <= 1'b0;
      // Check-first: rvalid can assert the same cycle as ARREADY.
      while (!vif.drv_cb.rvalid) @(vif.drv_cb);
      tr.data = vif.drv_cb.rdata;
      tr.resp = vif.drv_cb.rresp;
      vif.drv_cb.rready <= 1'b0;
    endtask
  endclass

  class axi4_lite_monitor extends uvm_monitor;
    `uvm_component_utils(axi4_lite_monitor)
    virtual axi4_lite_if vif;
    axi4_lite_agent_cfg  cfg;
    uvm_analysis_port #(axi4_lite_seq_item) ap;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(axi4_lite_agent_cfg)::get(this, "", "cfg", cfg))
        `uvm_fatal(get_type_name(), "agent cfg not set")
      vif = cfg.vif;
    endfunction

    // Write and read channel observers run in parallel.
    task run_phase(uvm_phase phase);
      @(posedge vif.aresetn);
      fork
        mon_writes();
        mon_reads();
      join
    endtask

    task mon_writes();
      forever begin
        axi4_lite_seq_item tr;
        @(vif.mon_cb);
        if (vif.mon_cb.awvalid && vif.mon_cb.awready &&
            vif.mon_cb.wvalid  && vif.mon_cb.wready) begin
          tr      = axi4_lite_seq_item::type_id::create("wr_obs");
          tr.dir  = AXI_WRITE;
          tr.addr = vif.mon_cb.awaddr;
          tr.data = vif.mon_cb.wdata;
          tr.strb = vif.mon_cb.wstrb;
          while (!(vif.mon_cb.bvalid && vif.mon_cb.bready)) @(vif.mon_cb);
          tr.resp = vif.mon_cb.bresp;
          ap.write(tr);
        end
      end
    endtask

    task mon_reads();
      forever begin
        axi4_lite_seq_item tr;
        @(vif.mon_cb);
        if (vif.mon_cb.arvalid && vif.mon_cb.arready) begin
          tr      = axi4_lite_seq_item::type_id::create("rd_obs");
          tr.dir  = AXI_READ;
          tr.addr = vif.mon_cb.araddr;
          while (!(vif.mon_cb.rvalid && vif.mon_cb.rready)) @(vif.mon_cb);
          tr.data = vif.mon_cb.rdata;
          tr.resp = vif.mon_cb.rresp;
          ap.write(tr);
        end
      end
    endtask
  endclass

  class axi4_lite_agent extends uvm_agent;
    `uvm_component_utils(axi4_lite_agent)
    axi4_lite_agent_cfg  cfg;
    axi4_lite_driver     driver;
    axi4_lite_sequencer  sequencer;
    axi4_lite_monitor    monitor;
    uvm_analysis_port #(axi4_lite_seq_item) ap;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(axi4_lite_agent_cfg)::get(this, "", "cfg", cfg))
        `uvm_fatal(get_type_name(), "agent cfg not set")
      monitor = axi4_lite_monitor::type_id::create("monitor", this);
      if (cfg.is_active == UVM_ACTIVE) begin
        driver    = axi4_lite_driver::type_id::create("driver", this);
        sequencer = axi4_lite_sequencer::type_id::create("sequencer", this);
      end
    endfunction

    function void connect_phase(uvm_phase phase);
      monitor.ap.connect(ap);
      if (cfg.is_active == UVM_ACTIVE)
        driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction
  endclass

  // ---- axi4_lite_coverage.sv -------------------------------------------------
  class axi4_lite_coverage extends uvm_subscriber #(axi4_lite_seq_item);
    `uvm_component_utils(axi4_lite_coverage)

    axi4_lite_seq_item tr;

    covergroup cg;
      option.per_instance = 1;

      cp_dir : coverpoint tr.dir;

      // Exercise every register offset in the map plus an out-of-range bucket.
      cp_addr: coverpoint tr.addr {
        bins ctrl     = {`AXI_A_CTRL};
        bins status   = {`AXI_A_STATUS};
        bins scratch0 = {`AXI_A_SCRATCH};
        bins id       = {`AXI_A_ID};
        bins others[] = {[16:60]};            // remaining in-range word offsets
        bins oor      = {[64:$]};             // out-of-range
      }

      // Response codes seen.
      cp_resp: coverpoint tr.resp {
        bins okay   = {2'b00};
        bins slverr = {2'b10};
      }

      // Byte-strobe patterns (writes): full, none, and partials.
      cp_strb: coverpoint tr.strb iff (tr.dir == AXI_WRITE) {
        bins full    = {4'hF};
        bins lo_half = {4'h3};
        bins hi_half = {4'hC};
        bins byte0   = {4'h1};
        bins others  = default;
      }

      // Cross direction x response to ensure both error paths are hit.
      x_dir_resp : cross cp_dir, cp_resp;
      // Writes to every register offset.
      x_dir_addr : cross cp_dir, cp_addr;
    endgroup

    function new(string name, uvm_component parent);
      super.new(name, parent);
      cg = new();
    endfunction

    function void write(axi4_lite_seq_item t);
      tr = t;
      cg.sample();
    endfunction

    function void report_phase(uvm_phase phase);
      `uvm_info(get_type_name(),
        $sformatf("Functional coverage = %0.2f%%", cg.get_inst_coverage()), UVM_LOW)
    endfunction
  endclass

  // ---- axi4_lite_scoreboard.sv -----------------------------------------------
  class axi4_lite_scoreboard extends uvm_component;
    `uvm_component_utils(axi4_lite_scoreboard)

    uvm_analysis_imp #(axi4_lite_seq_item, axi4_lite_scoreboard) ap_imp;

    // Reference model state. The model array spans the whole word-addressable
    // space (not just NUM_REGS) so it also covers the axil_ram DUT; the
    // register-bank slave only ever touches the first NUM_REGS via in_range().
    localparam int NUM_REGS  = `AXI_NUM_REGS;
    localparam int MEM_WORDS = (1 << (`AXI_ADDR_W - 2));
    bit [`AXI_DATA_W-1:0] model [MEM_WORDS];
    bit [15:0]            wr_count;

    int unsigned n_matches, mismatches;   // 'matches' is a reserved SV keyword

    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap_imp = new("ap_imp", this);
    endfunction

    function void reset_model();
      foreach (model[i]) model[i] = '0;
      wr_count = '0;
    endfunction

    function void start_of_simulation_phase(uvm_phase phase);
      reset_model();
    endfunction

    function int unsigned idx(bit [`AXI_ADDR_W-1:0] a);    return a[`AXI_ADDR_W-1:2]; endfunction
    function bit          in_range(bit [`AXI_ADDR_W-1:0] a); return (a >> 2) < NUM_REGS; endfunction
    function bit          is_ro(int unsigned i);
      return (i == `AXI_IDX_STATUS) || (i == `AXI_IDX_ID);
    endfunction

    // Compose the STATUS read value the way the RTL maintains it.
    function bit [`AXI_DATA_W-1:0] status_value();
      bit [`AXI_DATA_W-1:0] v = '0;
      v[31:16] = wr_count;
      v[0]     = model[`AXI_IDX_CTRL][0];
      return v;
    endfunction

    function void write(axi4_lite_seq_item tr);
      if (tr.dir == AXI_WRITE) check_write(tr);
      else                     check_read(tr);
    endfunction

    function void check_write(axi4_lite_seq_item tr);
      bit [1:0] exp_resp;
      int unsigned i = idx(tr.addr);
`ifdef DUT_AXIL_RAM
      // axil_ram: every aligned address is a valid RW word, never SLVERR.
      exp_resp = 2'b00;
      for (int b = 0; b < `AXI_DATA_W/8; b++)
        if (tr.strb[b]) model[i][b*8 +: 8] = tr.data[b*8 +: 8];
`else
      if (!in_range(tr.addr)) begin
        exp_resp = 2'b10;                       // SLVERR
      end else begin
        exp_resp = 2'b00;
        if (!is_ro(i)) begin
          for (int b = 0; b < `AXI_DATA_W/8; b++)
            if (tr.strb[b]) model[i][b*8 +: 8] = tr.data[b*8 +: 8];
          wr_count++;
        end
      end
`endif
      check_resp("WRITE", tr, exp_resp);
    endfunction

    function void check_read(axi4_lite_seq_item tr);
      bit [`AXI_DATA_W-1:0] exp_data;
      bit [1:0]             exp_resp;
      int unsigned          i = idx(tr.addr);
`ifdef DUT_AXIL_RAM
      // axil_ram: read returns the last value written, response always OKAY.
      exp_resp = 2'b00;
      exp_data = model[i];
`else
      if (!in_range(tr.addr)) begin
        exp_data = 32'hDEAD_DEAD; exp_resp = 2'b10;
      end else begin
        exp_resp = 2'b00;
        case (i)
          `AXI_IDX_ID    : exp_data = `AXI_ID_VALUE;
          `AXI_IDX_STATUS: exp_data = status_value();
          default        : exp_data = model[i];
        endcase
      end
`endif
      if (tr.data !== exp_data) begin
        mismatches++;
        `uvm_error("SCB", $sformatf(
          "READ  @0x%02h data mismatch: exp=0x%08h got=0x%08h",
          tr.addr, exp_data, tr.data))
      end else n_matches++;
      check_resp("READ", tr, exp_resp);
    endfunction

    function void check_resp(string kind, axi4_lite_seq_item tr, bit [1:0] exp_resp);
      if (tr.resp !== exp_resp) begin
        mismatches++;
        `uvm_error("SCB", $sformatf(
          "%s @0x%02h resp mismatch: exp=%02b got=%02b",
          kind, tr.addr, exp_resp, tr.resp))
      end else n_matches++;
    endfunction

    function void report_phase(uvm_phase phase);
      if (mismatches == 0)
        `uvm_info("SCB", $sformatf("PASS  %0d checks matched", n_matches), UVM_LOW)
      else
        `uvm_error("SCB", $sformatf("FAIL  %0d mismatches / %0d checks",
                                    mismatches, n_matches + mismatches))
    endfunction
  endclass

  // ---- axi4_lite_ral.sv ------------------------------------------------------
  class axi_reg_ctrl extends uvm_reg;
    rand uvm_reg_field val;
    `uvm_object_utils(axi_reg_ctrl)
    function new(string name = "CTRL"); super.new(name, 32, UVM_NO_COVERAGE); endfunction
    virtual function void build();
      val = uvm_reg_field::type_id::create("val");
      val.configure(this, 32, 0, "RW", 0, 32'h0, 1, 1, 1);
    endfunction
  endclass

  class axi_reg_status extends uvm_reg;
    uvm_reg_field val;
    `uvm_object_utils(axi_reg_status)
    function new(string name = "STATUS"); super.new(name, 32, UVM_NO_COVERAGE); endfunction
    virtual function void build();
      val = uvm_reg_field::type_id::create("val");
      val.configure(this, 32, 0, "RO", 0, 32'h0, 1, 0, 1);
    endfunction
  endclass

  class axi_reg_scratch extends uvm_reg;
    rand uvm_reg_field val;
    `uvm_object_utils(axi_reg_scratch)
    function new(string name = "SCRATCH"); super.new(name, 32, UVM_NO_COVERAGE); endfunction
    virtual function void build();
      val = uvm_reg_field::type_id::create("val");
      val.configure(this, 32, 0, "RW", 0, 32'h0, 1, 1, 1);
    endfunction
  endclass

  class axi_reg_id extends uvm_reg;
    uvm_reg_field val;
    `uvm_object_utils(axi_reg_id)
    function new(string name = "ID"); super.new(name, 32, UVM_NO_COVERAGE); endfunction
    virtual function void build();
      val = uvm_reg_field::type_id::create("val");
      val.configure(this, 32, 0, "RO", 0, 32'h5A5A0001, 1, 0, 1);
    endfunction
  endclass

  class axi4_lite_reg_block extends uvm_reg_block;
    `uvm_object_utils(axi4_lite_reg_block)
    rand axi_reg_ctrl    ctrl;
         axi_reg_status  status;
    rand axi_reg_scratch scratch;
         axi_reg_id      id;

    function new(string name = "axi4_lite_reg_block");
      super.new(name, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
      default_map = create_map("default_map", 0, 4, UVM_LITTLE_ENDIAN);

      ctrl = axi_reg_ctrl::type_id::create("ctrl");
      ctrl.configure(this); ctrl.build();
      default_map.add_reg(ctrl, 'h00, "RW");

      status = axi_reg_status::type_id::create("status");
      status.configure(this); status.build();
      default_map.add_reg(status, 'h04, "RO");

      scratch = axi_reg_scratch::type_id::create("scratch");
      scratch.configure(this); scratch.build();
      default_map.add_reg(scratch, 'h08, "RW");

      id = axi_reg_id::type_id::create("id");
      id.configure(this); id.build();
      default_map.add_reg(id, 'h0C, "RO");

      lock_model();
    endfunction
  endclass

  class axi4_lite_reg_adapter extends uvm_reg_adapter;
    `uvm_object_utils(axi4_lite_reg_adapter)
    function new(string name = "axi4_lite_reg_adapter");
      super.new(name);
      supports_byte_enable = 1;
      provides_responses   = 1;
    endfunction

    virtual function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
      axi4_lite_seq_item tr = axi4_lite_seq_item::type_id::create("ral_tr");
      tr.dir  = (rw.kind == UVM_WRITE) ? AXI_WRITE : AXI_READ;
      tr.addr = rw.addr;
      tr.data = rw.data;
      tr.strb = (rw.kind == UVM_WRITE) ? rw.byte_en : '1;
      tr.delay = 0;
      return tr;
    endfunction

    virtual function void bus2reg(uvm_sequence_item bus_item, ref uvm_reg_bus_op rw);
      axi4_lite_seq_item tr;
      if (!$cast(tr, bus_item)) begin
        `uvm_fatal("RAL_ADAPTER", "bus_item is not axi4_lite_seq_item")
        return;
      end
      rw.kind   = (tr.dir == AXI_WRITE) ? UVM_WRITE : UVM_READ;
      rw.addr   = tr.addr;
      rw.data   = tr.data;
      rw.byte_en= tr.strb;
      rw.status = (tr.resp == 2'b00) ? UVM_IS_OK : UVM_NOT_OK;
    endfunction
  endclass

  // ---- axi4_lite_env.sv ------------------------------------------------------
  class axi4_lite_env_cfg extends uvm_object;
    virtual axi4_lite_if vif;
    `uvm_object_utils(axi4_lite_env_cfg)
    function new(string name = "axi4_lite_env_cfg"); super.new(name); endfunction
  endclass

  class axi4_lite_env extends uvm_env;
    `uvm_component_utils(axi4_lite_env)

    axi4_lite_env_cfg     cfg;
    axi4_lite_agent       agent;
    axi4_lite_scoreboard  scb;
    axi4_lite_coverage    cov;

    axi4_lite_reg_block                            regmodel;
    axi4_lite_reg_adapter                          adapter;
    uvm_reg_predictor #(axi4_lite_seq_item)        predictor;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
      axi4_lite_agent_cfg acfg;
      super.build_phase(phase);
      if (!uvm_config_db#(axi4_lite_env_cfg)::get(this, "", "cfg", cfg))
        `uvm_fatal(get_type_name(), "env cfg not set")

      acfg = axi4_lite_agent_cfg::type_id::create("acfg");
      acfg.vif = cfg.vif;
      uvm_config_db#(axi4_lite_agent_cfg)::set(this, "agent*", "cfg", acfg);

      agent = axi4_lite_agent::type_id::create("agent", this);
      scb   = axi4_lite_scoreboard::type_id::create("scb", this);
      cov   = axi4_lite_coverage::type_id::create("cov", this);

      regmodel = axi4_lite_reg_block::type_id::create("regmodel");
      regmodel.build();
      regmodel.set_hdl_path_root("tb_top.dut");
      adapter   = axi4_lite_reg_adapter::type_id::create("adapter");
      predictor = uvm_reg_predictor#(axi4_lite_seq_item)::type_id::create("predictor", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      agent.ap.connect(scb.ap_imp);
      agent.ap.connect(cov.analysis_export);
      agent.ap.connect(predictor.bus_in);

      // Explicit-predict RAL; sequences drive the agent sequencer.
      regmodel.default_map.set_sequencer(agent.sequencer, adapter);
      regmodel.default_map.set_auto_predict(0);
      predictor.map     = regmodel.default_map;
      predictor.adapter = adapter;
    endfunction
  endclass

  // ---- sequences/axi4_lite_seq_lib.sv ----------------------------------------
  class axi4_lite_base_seq extends uvm_sequence #(axi4_lite_seq_item);
    `uvm_object_utils(axi4_lite_base_seq)
    function new(string name = "axi4_lite_base_seq"); super.new(name); endfunction

    task wr(bit [`AXI_ADDR_W-1:0] a, bit [`AXI_DATA_W-1:0] d,
            bit [`AXI_DATA_W/8-1:0] s = '1);
      axi4_lite_seq_item t = axi4_lite_seq_item::type_id::create("t");
      start_item(t);
      if (!t.randomize() with { dir == AXI_WRITE; addr == a; data == d; strb == s; })
        `uvm_error("SEQ","randomize failed")
      finish_item(t);
    endtask

    task rd(bit [`AXI_ADDR_W-1:0] a);
      axi4_lite_seq_item t = axi4_lite_seq_item::type_id::create("t");
      start_item(t);
      if (!t.randomize() with { dir == AXI_READ; addr == a; })
        `uvm_error("SEQ","randomize failed")
      finish_item(t);
    endtask
  endclass

  // Directed smoke: walk the register map.
  class axi4_lite_smoke_seq extends axi4_lite_base_seq;
    `uvm_object_utils(axi4_lite_smoke_seq)
    function new(string name = "axi4_lite_smoke_seq"); super.new(name); endfunction
    task body();
      wr(`AXI_A_CTRL,    32'h0000_0001);
      rd(`AXI_A_CTRL);
      rd(`AXI_A_STATUS);
      wr(`AXI_A_SCRATCH, 32'hDEAD_BEEF);
      rd(`AXI_A_SCRATCH);
      rd(`AXI_A_ID);
      wr(`AXI_A_ID,      32'hFFFF_FFFF); // RO
      rd(`AXI_A_ID);
    endtask
  endclass

  // Byte-strobe merge.
  class axi4_lite_strobe_seq extends axi4_lite_base_seq;
    `uvm_object_utils(axi4_lite_strobe_seq)
    function new(string name = "axi4_lite_strobe_seq"); super.new(name); endfunction
    task body();
      wr(`AXI_A_SCRATCH, 32'h0000_0000);
      wr(`AXI_A_SCRATCH, 32'hAABB_CCDD, 4'h1);
      rd(`AXI_A_SCRATCH);                       // -> 0x000000DD
      wr(`AXI_A_SCRATCH, 32'h1122_3344, 4'hC);
      rd(`AXI_A_SCRATCH);                       // -> 0x112200DD
    endtask
  endclass

  // Out-of-range access -> SLVERR.
  class axi4_lite_error_seq extends axi4_lite_base_seq;
    `uvm_object_utils(axi4_lite_error_seq)
    function new(string name = "axi4_lite_error_seq"); super.new(name); endfunction
    task body();
      wr(`AXI_A_OOR, 32'h1234_5678);
      rd(`AXI_A_OOR);
    endtask
  endclass

  class axi4_lite_random_seq extends axi4_lite_base_seq;
    `uvm_object_utils(axi4_lite_random_seq)
    rand int unsigned num_trans;
    constraint c_n { num_trans inside {[100:300]}; }
    function new(string name = "axi4_lite_random_seq"); super.new(name); endfunction
    task body();
      repeat (num_trans) begin
        axi4_lite_seq_item t = axi4_lite_seq_item::type_id::create("t");
        start_item(t);
        if (!t.randomize() with {
              addr[1:0] == 2'b00;
              dir dist {AXI_WRITE := 1, AXI_READ := 1};
              addr dist { [0:60] := 7, [64:255] := 3 };
            })
          `uvm_error("SEQ","randomize failed")
        finish_item(t);
      end
    endtask
  endclass

  // ---- tests/axi4_lite_test_lib.sv -------------------------------------------
  class axi4_lite_base_test extends uvm_test;
    `uvm_component_utils(axi4_lite_base_test)
    axi4_lite_env     env;
    axi4_lite_env_cfg cfg;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      cfg = axi4_lite_env_cfg::type_id::create("cfg");
      if (!uvm_config_db#(virtual axi4_lite_if)::get(this, "", "vif", cfg.vif))
        `uvm_fatal(get_type_name(), "virtual interface 'vif' not set")
      uvm_config_db#(axi4_lite_env_cfg)::set(this, "env", "cfg", cfg);
      env = axi4_lite_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
      phase.phase_done.set_drain_time(this, 200ns);  // observe last response
    endtask
  endclass

  class axi4_lite_smoke_test extends axi4_lite_base_test;
    `uvm_component_utils(axi4_lite_smoke_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
      axi4_lite_smoke_seq seq;
      super.run_phase(phase);
      phase.raise_objection(this);
      seq = axi4_lite_smoke_seq::type_id::create("seq");
      seq.start(env.agent.sequencer);
      phase.drop_objection(this);
    endtask
  endclass

  class axi4_lite_strobe_test extends axi4_lite_base_test;
    `uvm_component_utils(axi4_lite_strobe_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
      axi4_lite_strobe_seq seq;
      super.run_phase(phase);
      phase.raise_objection(this);
      seq = axi4_lite_strobe_seq::type_id::create("seq");
      seq.start(env.agent.sequencer);
      phase.drop_objection(this);
    endtask
  endclass

  class axi4_lite_error_test extends axi4_lite_base_test;
    `uvm_component_utils(axi4_lite_error_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
      axi4_lite_error_seq seq;
      super.run_phase(phase);
      phase.raise_objection(this);
      seq = axi4_lite_error_seq::type_id::create("seq");
      seq.start(env.agent.sequencer);
      phase.drop_objection(this);
    endtask
  endclass

  // Full regression: directed + constrained-random.
  class axi4_lite_regression_test extends axi4_lite_base_test;
    `uvm_component_utils(axi4_lite_regression_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
      axi4_lite_smoke_seq  s0;
      axi4_lite_strobe_seq s1;
      axi4_lite_error_seq  s2;
      axi4_lite_random_seq s3;
      super.run_phase(phase);
      phase.raise_objection(this);
      s0 = axi4_lite_smoke_seq ::type_id::create("s0"); s0.start(env.agent.sequencer);
      s1 = axi4_lite_strobe_seq::type_id::create("s1"); s1.start(env.agent.sequencer);
      s2 = axi4_lite_error_seq ::type_id::create("s2"); s2.start(env.agent.sequencer);
      s3 = axi4_lite_random_seq::type_id::create("s3");
      if (!s3.randomize()) `uvm_error("TEST","rand failed");
      s3.start(env.agent.sequencer);
      phase.drop_objection(this);
    endtask
  endclass

endpackage

// =============================================================================
// Bind-able AXI4-Lite protocol assertions: handshake stability, payload
// stability while stalled, no-unknowns, one B per write, legal responses.
// =============================================================================
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

// =============================================================================
// UVM testbench top: clock/reset, DUT, interface, SVA bind.
// Default DUT is the internal slave. To target alexforencich/verilog-axi's
// axil_ram instead, add `define DUT_AXIL_RAM as the FIRST line of this pane
// (design.sv always compiles both DUTs, so nothing changes there).
// =============================================================================
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

  // Publish the virtual interface and launch UVM. run_test's argument is the
  // default; +UVM_TESTNAME=<test> in Run Options overrides it. Available tests:
  //   axi4_lite_smoke_test  axi4_lite_strobe_test
  //   axi4_lite_error_test  axi4_lite_regression_test (default)
  initial begin
    uvm_config_db#(virtual axi4_lite_if)::set(null, "uvm_test_top", "vif", axi_if);
    run_test("axi4_lite_regression_test");
  end

  // Waveform dump for EPWave ("Open EPWave after run").
  initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, tb_top);
  end
endmodule

`default_nettype wire
