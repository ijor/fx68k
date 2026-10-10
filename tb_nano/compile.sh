#! /bin/sh

#Verilog top module
TOP_FILE=fx68k_nano_tb

#Options for GCC compiler
COMPILE_OPT="-CFLAGS -DVM_PREFIX=V"$TOP_FILE" -CFLAGS -O3 -CFLAGS -Wno-attributes"

#Options for Verilator
VERILATOR_OPT="\
 --cc -O3\
 -Wno-WIDTH\
 -Wno-CASEINCOMPLETE\
 -Wno-UNOPTFLAT\
 -Wno-TIMESCALEMOD\
 -Wno-MULTIDRIVEN\
 -Wno-SELRANGE\
 -Wno-CMPCONST\
 -Wno-UNSIGNED\
 -Wno-LATCH\
 -Wno-IMPLICIT\
 -Wno-BLKANDNBLK\
 -Wno-COMBDLY\
"

#Comment this line if running verilator v4
V5_OPT="--no-timing --no-assert-case"

#Comment this line to disable VCD generation
TRACE_OPT="-trace"

#C++ support files
CPP_FILES="\
 main.cpp\
 verilated_dpi.cpp\
"

verilator tb_top.v $COMPILE_OPT $TRACE_OPT $VERILATOR_OPT $V5_OPT --top-module $TOP_FILE --exe $CPP_FILES

cd ./obj_dir
make -j -f V$TOP_FILE.mk V$TOP_FILE
cd ..
