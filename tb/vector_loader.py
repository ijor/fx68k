#!/usr/bin/env python3
"""
SingleStepTests/m68000 loader. Reads a DECODED .json file (run the repo's
decode.py first to turn .json.bin -> .json) and flattens each test to a compact
line format the C++ Verilator runner consumes (keeps JSON parsing in Python).

Schema (from the repo decode.py):
  test = { name, initial:{state}, final:{state}, transactions, length }
  state = { d0..d7, a0..a6, usp, ssp, sr, pc, prefetch:[pf0,pf1], ram:[[addr,byte],...] }
  (a7 is NOT stored; it's usp or ssp per SR S-bit. ram is byte-granular.)

fx68k reg-file index map (for the runner's poke/peek):
  D0..D7 -> 0..7 ; A0..A6 -> 8..14 ; USP -> 15 ; SSP -> 16 ; (DT -> 17 internal)
  PC -> PcL/PcH regs ; CCR/flags -> excUnit.alu.pswCcr ; S/T bits in SR.

Flat output per test:
  TEST <name>
  INIT <d0..d7 a0..a6 usp ssp sr pc>   (19 hex32 values, sr is 16-bit in low half)
  IPFX <pf0> <pf1>
  IRAM <n> ; then n lines: <addr06> <byte02>
  FINAL <same 19 values>
  FPFX <pf0> <pf1>
  FRAM <n> ; then n lines
  LEN <cycle length>
  END
"""
import json, sys

ORDER = ['d0','d1','d2','d3','d4','d5','d6','d7',
         'a0','a1','a2','a3','a4','a5','a6','usp','ssp','sr','pc']

def line(tag, s):
    return tag + " " + " ".join("%08X" % (s[k] & 0xFFFFFFFF) for k in ORDER)

def emit(t, out):
    out.write("TEST %s\n" % t['name'].replace('\n',' '))
    ini, fin = t['initial'], t['final']
    out.write(line("INIT", ini) + "\n")
    out.write("IPFX %04X %04X\n" % (ini['prefetch'][0]&0xFFFF, ini['prefetch'][1]&0xFFFF))
    out.write("IRAM %d\n" % len(ini['ram']))
    for addr,b in ini['ram']:
        out.write("%06X %02X\n" % (addr & 0xFFFFFF, b & 0xFF))
    out.write(line("FINAL", fin) + "\n")
    out.write("FPFX %04X %04X\n" % (fin['prefetch'][0]&0xFFFF, fin['prefetch'][1]&0xFFFF))
    out.write("FRAM %d\n" % len(fin['ram']))
    for addr,b in fin['ram']:
        out.write("%06X %02X\n" % (addr & 0xFFFFFF, b & 0xFF))
    out.write("LEN %d\n" % t.get('length',0))
    out.write("END\n")

def main():
    if len(sys.argv)<2:
        print("usage: vector_loader.py decoded.json [out.flat] [--limit N]", file=sys.stderr); sys.exit(1)
    limit = None
    if '--limit' in sys.argv:
        limit = int(sys.argv[sys.argv.index('--limit')+1])
    data = json.load(open(sys.argv[1]))
    outname = sys.argv[2] if len(sys.argv)>2 and not sys.argv[2].startswith('--') else None
    out = open(outname,'w') if outname else sys.stdout
    n=0
    for t in data:
        emit(t, out); n+=1
        if limit and n>=limit: break
    print("flattened %d tests" % n, file=sys.stderr)

if __name__=='__main__':
    main()
