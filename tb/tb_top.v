// Trace configuration
// -------------------
`verilator_config

//tracing_on -file "../bram/fx68kRegs_distributed.sv"
tracing_on -file "../bram/fx68kRegs_generic.sv"
tracing_on -file "../bram/fx68kRom_generic.sv"
tracing_on -file "../uaddrPla.sv"
tracing_on -file "../fx68kAlu.sv"
tracing_on -file "../fx68k.sv"

`verilog

//`include "../bram/fx68kRegs_distributed.sv"
`include "../bram/fx68kRegs_generic.sv"
`include "../bram/fx68kRom_generic.sv"
`include "../fx68k_pkg.sv"
`include "../uaddrPla.sv"
`include "../fx68kAlu.sv"
`include "../fx68k.sv"
