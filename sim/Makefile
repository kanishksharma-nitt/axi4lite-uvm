# AXI4-Lite UVM sim (Questa / VCS / Xcelium). Needs a UVM-capable simulator.
#   make questa|vcs|xrun TEST=axi4_lite_regression_test
#   make cov     # coverage report (Questa)
TEST    ?= axi4_lite_regression_test
SEED    ?= 1
UVM_VERB?= UVM_MEDIUM
FILES    = -f files.f
TOP      = tb_top

questa:
	vlib work
	vlog -sv +acc -L $$QUESTA_HOME/uvm-1.2 -mfcu $(FILES)
	vsim -c $(TOP) -do "run -all; quit" \
	     +UVM_TESTNAME=$(TEST) +UVM_VERBOSITY=$(UVM_VERB) \
	     -sv_seed $(SEED) -coverage \
	     -do "coverage save -onexit cov.ucdb"

vcs:
	vcs -full64 -sverilog -ntb_opts uvm-1.2 -timescale=1ns/1ps \
	    -debug_access+all -cm line+cond+fsm+tgl+assert $(FILES) -o simv
	./simv +UVM_TESTNAME=$(TEST) +UVM_VERBOSITY=$(UVM_VERB) \
	    +ntb_random_seed=$(SEED) -cm line+cond+fsm+tgl+assert

xrun:
	xrun -64bit -sv -uvm -timescale 1ns/1ps -coverage all \
	     $(FILES) +UVM_TESTNAME=$(TEST) +UVM_VERBOSITY=$(UVM_VERB) \
	     -svseed $(SEED)

cov:
	vcover report -details -html -htmldir covhtml cov.ucdb

clean:
	rm -rf work transcript *.vcd *.wlf *.ucdb covhtml simv* csrc *.log \
	       ucli.key vc_hdrs.h DVEfiles AN.DB
