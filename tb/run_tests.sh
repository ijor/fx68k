#!/bin/bash

set -e
EXE="./obj_dir/Vfx68k" # path to verilator test
#TRACE="--trace"
VERBOSE="--verbose"

# The instructions that exercise the ALU add/sub/flag paths — the regression set.
INSTRS="SUB.b SUB.w SUB.l SUBX.b SUBX.w SUBX.l SUBA.w SUBA.l \
        ADD.b ADD.w ADD.l ADDX.b ADDX.w ADDX.l ADDA.w ADDA.l \
        CMP.b CMP.w CMP.l CMPA.w CMPA.l \
        NEG.b NEG.w NEG.l NEGX.b NEGX.w NEGX.l \
        ORItoCCR ANDItoCCR \
        AND.b AND.w AND.l OR.b OR.w OR.l EOR.b EOR.w EOR.l \
        ASL.w ASR.w LSL.w LSR.w ROL.w ROR.w ROXL.w ROXR.w \
        ABCD SBCD NBCD NOP"

for i in $INSTRS; do
  echo "================ $i ================"
  $EXE $i $TRACE $VERBOSE
done

echo "================ DONE! ================"
