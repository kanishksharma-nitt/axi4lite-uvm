// Base test + concrete tests.
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
