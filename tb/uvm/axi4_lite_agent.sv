// Config, sequencer, driver, monitor, and agent.
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
