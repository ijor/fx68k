// Trace configuration
// -------------------
`verilator_config

tracing_on -file "../bram/fx68kRom_generic.sv"
tracing_on -file "fx68k_nano_tb.sv"

`verilog

`include "../bram/fx68kRom_generic.sv"
`include "../fx68k_pkg.sv"
`include "fx68k_nano_tb.sv"
