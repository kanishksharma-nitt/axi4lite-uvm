// Sequence library: base helpers + directed + random.
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
