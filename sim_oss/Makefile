# Open-source AXI4-Lite simulation (Icarus Verilog).
#   make [DUT=internal|axil_ram]   # default internal; run + check PASS
#   make both                      # run both DUTs
#   make NUM_TRANS=2000 SEED=7
#   make lint
.DEFAULT_GOAL := run

TOP        = tb_axi4_lite
VVP        = sim.vvp
NUM_TRANS ?= 400
SEED      ?= 1
DUT       ?= internal

ifeq ($(DUT),axil_ram)
    FILELIST = files_axil_ram.f
    DEFINES  = -DDUT_AXIL_RAM
else ifeq ($(DUT),internal)
    FILELIST = files.f
    DEFINES  =
else
    $(error DUT must be 'internal' or 'axil_ram', got '$(DUT)')
endif

build:
	iverilog -g2012 -Wall $(DEFINES) -s $(TOP) -o $(VVP) -f $(FILELIST)

run: build
	@echo ">>> DUT=$(DUT)"; \
	out=$$(vvp $(VVP) +NUM_TRANS=$(NUM_TRANS) +SEED=$(SEED)); \
	echo "$$out"; \
	echo "$$out" | grep -q "TEST PASSED"

both:
	@$(MAKE) run DUT=internal
	@$(MAKE) run DUT=axil_ram

lint:
	verilator --lint-only -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL \
	  -Wno-UNUSEDPARAM --top-module axi4_lite_slave \
	  ../rtl/axi4_lite_slave.sv
	verilator --lint-only -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL \
	  -Wno-UNUSEDPARAM -Wno-WIDTH -Wno-SELRANGE --top-module axil_ram \
	  ../rtl/third_party/verilog-axi/rtl/axil_ram.v

clean:
	rm -f $(VVP) *.vcd
