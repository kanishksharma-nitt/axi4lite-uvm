# EDA Playground bundle (AXI4-Lite UVM)

Two self-contained files that run the full UVM environment (agent, scoreboard,
functional coverage, RAL, SVA, and the smoke/strobe/error/regression tests) in
a browser on [edaplayground.com](https://edaplayground.com), so you don't need
a local commercial simulator. Everything is inlined, so there are no include
paths to set up.

- `design.sv` goes in the Design pane. It holds the synthesizable DUTs.
- `testbench.sv` goes in the Testbench pane: interface, UVM package (every
  class), SVA, and `tb_top`.

## Left-panel settings

| Setting | Value |
|---|---|
| Testbench + Design | SystemVerilog/Verilog |
| UVM / OVM | UVM 1.2 |
| Tools & Simulators | Aldec Riviera-Pro 2023.06 (free, UVM-capable), or Questa / VCS / Xcelium |
| Run Options | leave empty, or `+UVM_TESTNAME=<test>` and/or a coverage flag (below) |
| Open EPWave after run | checked, for the waveform |

Then click Run. With defaults it runs `axi4_lite_regression_test` against the
internal slave. Riviera-Pro needs no license or login. If it's busy or errors,
Questa is the next pick with the same files and no edits; VCS and Xcelium also
work (checked on Xcelium 25.03).

## Functional coverage

The covergroup samples every transaction, but a simulator only records coverage
when its coverage engine is on. Otherwise `get_inst_coverage()` reports `0.00%`
(and Xcelium prints a `COVNSM: ... sampling is not enabled` note). Turn it on in
Run Options:

```
-coverage all                  # Cadence Xcelium (functional + code/toggle/FSM)
-cm line+cond+fsm+tgl+assert    # Synopsys VCS
+cover=bcefst                   # Aldec Riviera-Pro / Siemens Questa
```

Expect a partial number, not 100%: the random sequence runs 100-300
transactions and `cp_addr` alone spawns a bin per word offset. Re-run with a
different seed (VCS `+ntb_random_seed`, Xcelium `-svseed`, or the sim's seed
field) to accumulate more bins.

## Picking a test

`tb_top` calls `run_test("axi4_lite_regression_test")` by default, but a
`+UVM_TESTNAME` plusarg overrides it. Put one of these in Run Options:

```
+UVM_TESTNAME=axi4_lite_smoke_test        # directed walk of the register map
+UVM_TESTNAME=axi4_lite_strobe_test       # byte-strobe merge
+UVM_TESTNAME=axi4_lite_error_test        # out-of-range -> SLVERR
+UVM_TESTNAME=axi4_lite_regression_test   # directed + constrained-random (default)
```

## Switching the DUT

Default is the internal register-bank slave (`axi4_lite_slave`). To verify the
third-party `alexforencich/verilog-axi` `axil_ram` instead, add this as the
first line of the Testbench pane:

```systemverilog
`define DUT_AXIL_RAM
```

Nothing else changes: `design.sv` already compiles both DUTs, and the
scoreboard switches its reference model on the same define. The SVA bind and
the agent follow automatically.

## What to look for in the log

A passing run ends with the scoreboard and coverage reports, e.g.:

```
UVM_INFO ... [SCB] PASS  NN checks matched
UVM_INFO ... [axi4_lite_coverage] Functional coverage = XX.XX%
UVM_INFO ... [UVM/REPORT/SERVER] ... UVM_ERROR : 0 ...
```

`UVM_ERROR : 0` (and `UVM_FATAL : 0`) with a `PASS` from `[SCB]` means every
transaction matched the reference model and no protocol assertion fired. The
waveform opens in EPWave (`dump.vcd`). The coverage line reads `0.00%` unless
you enabled a coverage flag (see Functional coverage above); that's a tool
setting, not a testbench failure.

## Relationship to the repo flows

This bundle is the same source as [`../tb/uvm/`](../tb/uvm/) and
[`../sim/`](../sim/), flattened for the browser. The command-line UVM flow lives
in [`../sim/Makefile`](../sim/Makefile) (Questa/VCS/Xcelium); the open-source
non-UVM flow that CI runs is in [`../sim_oss/`](../sim_oss/). If you edit the
UVM sources, re-flatten rather than hand-editing these two files.
</content>
