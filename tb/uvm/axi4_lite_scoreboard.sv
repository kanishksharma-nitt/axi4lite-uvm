// Reference-model checker: predicts expected read data/response per observed
// transaction and compares against the bus.
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
