// Functional coverage subscriber.
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
