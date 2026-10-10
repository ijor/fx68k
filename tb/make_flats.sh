#!/bin/bash
# Flatten the arithmetic-relevant SST vectors into compact .flat files.
# Run from .  (the dir containing sst_m68k/v1/ and decode.py).
# Produces ./flats/*.flat  — small files (~a few hundred KB each at 300 tests).

set -e
LOADER="./vector_loader.py" # path to vector_loader.py
LIMIT="${1:-300}"           # tests per instruction (300 is plenty for regression)
mkdir -p flats

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
  if [ -f "./sst_m68k/v1/$i.json" ]; then
    python3 "$LOADER" "./sst_m68k/v1/$i.json" "flats/$i.flat" --limit "$LIMIT" 2>/dev/null \
      && echo "  flattened $i"
  fi
done

echo "--- sizes ---"
du -sh flats
tar czf sst_flats.tgz flats
echo "--- created sst_flats.tgz ($(du -h sst_flats.tgz | cut -f1)) — upload THIS ---"
