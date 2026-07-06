// RAL: reg block (CTRL/STATUS/SCRATCH/ID) + adapter between uvm_reg_bus_op and
// axi4_lite_seq_item for the predictor.
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
