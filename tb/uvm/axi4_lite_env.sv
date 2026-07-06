// Environment: agent -> { scoreboard, coverage, reg_predictor } + RAL.
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
