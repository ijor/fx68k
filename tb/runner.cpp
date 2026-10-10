// fx68k SingleStepTests runner (Verilator). Loads flattened SST vectors,
// executes each on the full core via a memory model, compares final state.

// Macros to build include file name
#define _quoted_string(x) #x
#define quoted_string(x) _quoted_string(x)
#define _symbols_header(x) _quoted_string(x##__Syms.h)
#define symbols_header(x) _symbols_header(x)
// Top level
#include symbols_header(VM_PREFIX)

#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <vector>
#include <string>

#if VM_TRACE
#include "verilated_vcd_c.h"
#endif /* VM_TRACE */

#define PERIOD_100MHz_ps   ((uint64_t)10000)

#define FLAT_DIR   "flats/"
#define FLAT_EXT   ".flat"
#define TRACE_EXT  ".vcd"

static VM_PREFIX* top;
static int divi    = 0;

#if VM_TRACE
uint64_t   tb_time = 0;
VerilatedVcdC* tfp = NULL;
#endif /* VM_TRACE */

static void tick()
{
    top->clk = 0;
    top->eval();
#if VM_TRACE
    if (tfp)
    {
        tfp->dump (tb_time);
        tb_time += PERIOD_100MHz_ps / 2;
    }
#endif /* VM_TRACE */
    top->clk = 1;
    top->eval();
#if VM_TRACE
    if (tfp)
    {
        tfp->dump (tb_time);
        tb_time += PERIOD_100MHz_ps / 2;
    }
#endif /* VM_TRACE */
}

static void step()
{
    top->enPhi1 = (divi == 3) ? 1 : 0;
    top->enPhi2 = (divi == 1) ? 1 : 0;
    tick();
    divi = (divi + 1) & 3;
}

// ---- memory model: sparse byte map ----
static std::map<uint32_t,uint8_t> mem;
static uint8_t rd8(uint32_t a){ auto it=mem.find(a&0xFFFFFF); return it==mem.end()?0:it->second; }
static void wr8(uint32_t a,uint8_t v){ mem[a&0xFFFFFF]=v; }

// Access to Verilator internals
#define ROOT (top->rootp)
#define RAM_L ROOT->fx68k__DOT__excUnit__DOT__U_fx68kRegs__DOT__ram_L
#define RAM_W ROOT->fx68k__DOT__excUnit__DOT__U_fx68kRegs__DOT__ram_W
#define RAM_B ROOT->fx68k__DOT__excUnit__DOT__U_fx68kRegs__DOT__ram_B
#define PCL   ROOT->fx68k__DOT__excUnit__DOT__PcL
#define PCH   ROOT->fx68k__DOT__excUnit__DOT__PcH
#define RIR   ROOT->fx68k__DOT__rIr_t1
#define RIRL  ROOT->fx68k__DOT__rIrL_t1
#define RIRD  ROOT->fx68k__DOT__rIrd_t1
#define RIRDL ROOT->fx68k__DOT__rIrdL_t1
#define PSW   ROOT->fx68k__DOT__psw
#define PSWS  ROOT->fx68k__DOT__pswS
#define PSWS2 ROOT->fx68k__DOT__excUnit__DOT__pswS
#define PSWT  ROOT->fx68k__DOT__pswT
#define PSWI  ROOT->fx68k__DOT__pswI
#define PSWCCR ROOT->fx68k__DOT__excUnit__DOT__U_fx68kAlu__DOT__rPswCcr_t3
static inline uint16_t onehot4(uint16_t instr){ return (uint16_t)(1u << ((instr>>12)&0xF)); }

static void set_reg(int idx, uint32_t v)
{
  RAM_L[idx]=(v >> 16) & 0xFFFF;
  RAM_W[idx]=(v >> 8) & 0xFF;
  RAM_B[idx]= v & 0xFF;
}

static uint32_t get_reg(int idx)
{
  return ((uint32_t)RAM_L[idx]<<16)|((uint32_t)RAM_W[idx]<<8)|RAM_B[idx];
}

// ---- flattened vector structs ----
struct State
{
    // r[] order: d0..d7(0-7) a0..a6(8-14) usp(15) ssp(16) sr(17) pc(18)
    uint32_t r[19];
    uint16_t pf[2];
    std::vector<std::pair<uint32_t,uint8_t>> ram;
};
struct Test
{
    std::string name;
    State ini;
    State fin;
    int len;
};

static std::vector<Test> load_flat(const char* fn){
  std::vector<Test> tests; FILE* f=fopen(fn,"r"); if(!f){perror("open");exit(1);}
  char line[256]; Test t; State* cur=nullptr; int ramleft=0;
  auto rd19=[&](State&s,const char* p){ for(int i=0;i<19;i++){ s.r[i]=strtoul(p,(char**)&p,16);} };
  while(fgets(line,sizeof line,f)){
    if(!strncmp(line,"TEST ",5)){ t=Test(); t.name=line+5; if(t.name.size())t.name.pop_back(); }
    else if(!strncmp(line,"INIT ",5)) rd19(t.ini,line+5);
    else if(!strncmp(line,"IPFX ",5)){ sscanf(line+5,"%hx %hx",&t.ini.pf[0],&t.ini.pf[1]); }
    else if(!strncmp(line,"IRAM ",5)){ ramleft=atoi(line+5); cur=&t.ini; }
    else if(!strncmp(line,"FINAL ",6)) rd19(t.fin,line+6);
    else if(!strncmp(line,"FPFX ",5)){ sscanf(line+5,"%hx %hx",&t.fin.pf[0],&t.fin.pf[1]); }
    else if(!strncmp(line,"FRAM ",5)){ ramleft=atoi(line+5); cur=&t.fin; }
    else if(!strncmp(line,"LEN ",4)) t.len=atoi(line+4);
    else if(!strncmp(line,"END",3)) tests.push_back(t);
    else if(ramleft>0 && cur){ uint32_t a; unsigned b; sscanf(line,"%x %x",&a,&b); cur->ram.push_back({a,(uint8_t)b}); ramleft--; }
  }
  fclose(f); return tests;
}

int main(int argc,char**argv)
{
    int limit   = 1000000;
    int verbose = 0;
    int trace   = 0;
    int pass    = 0;
    int fail    = 0;
    int done    = 0;
    std::string str;

    Verilated::commandArgs(argc,argv);
    if (argc < 2)
    {
        fprintf(stderr,"usage: runner file.flat [--limit N] [--verbose]\n");
        return 1;
    }

    for(int i = 2; i < argc; i++)
    {
        if (!strcmp(argv[i],"--limit"))   limit   = atoi(argv[++i]);
        if (!strcmp(argv[i],"--verbose")) verbose = 1;
        if (!strcmp(argv[i],"--trace"))   trace   = 1;
    }
    str  = FLAT_DIR;
    str += argv[1];
    str += FLAT_EXT;

    auto tests = load_flat(str.c_str());
    top = new VM_PREFIX;
#if VM_TRACE
    if (trace)
    {
        Verilated::traceEverOn(true);
        tfp = new VerilatedVcdC;
        top->trace (tfp, 99);
        tfp->spTrace()->set_time_resolution ("1 ps");
        str  = quoted_string(VM_PREFIX) "_";
        str += argv[1];
        str += TRACE_EXT;
        tfp->open (str.c_str());
    }
#endif /* VM_TRACE */
    for(auto&t: tests)
    {
        if (done >= limit) break;
        done++;
        // ---- build memory: test RAM + reset vector pointing at the instruction ----
        mem.clear();
        for (auto&pr: t.ini.ram) wr8(pr.first,pr.second);
        uint32_t tpc  = t.ini.r[18];
        uint32_t boot = (tpc - 4) & 0xFFFFFF;          // instruction sits at PC-4
        uint32_t ssp  = t.ini.r[16];
        wr8(0,(ssp >> 24) & 0xFF);
        wr8(1,(ssp >> 16) & 0xFF);
        wr8(2,(ssp >>  8) & 0xFF);
        wr8(3, ssp & 0xFF);         // reset SSP
        wr8(4,(boot >> 24) & 0xFF);
        wr8(5,(boot >> 16) & 0xFF);
        wr8(6,(boot >>  8) & 0xFF);
        wr8(7, boot & 0xFF);        // reset PC = boot

        // ---- reset (memory active so it fetches the reset vector) ----
        top->HALTn    = 1;
        top->VPAn     = 1;
        top->BERRn    = 1;
        top->BRn      = 1;
        top->BGACKn   = 1;
        top->IPL2n    = 1;
        top->IPL1n    = 1;
        top->IPL0n    = 1;
        top->iEdb     = 0;
        top->extReset = 1;
        top->pwrUp    = 1;
        top->DTACKn   = 1;

        divi = 0;
        for (int i = 0; i < 64; i++)
        {
            step();
            // load D/A/USP during reset so reg-file output latches settle from
            // correct data before any instruction reads them (boot doesn't touch D/A)
            for (int r = 0; r < 16; r++) set_reg(r, t.ini.r[r]);
        }
        top->extReset = 0;
        top->pwrUp    = 0;
 
        // SR/flags loaded once out of reset (boot sets S; we override full SR)
        // Load the status register properly. pswS (supervisor) is a REGISTER that
        // selects USP vs SSP for A7 — the psw word is only a derived wire, so poke
        // the real pswS/pswT/pswI registers, not psw. Getting pswS right is what
        // makes (A7)/-(A7)/(A7)+ use the mode-correct stack pointer.
        {
            uint16_t sr = t.ini.r[17] & 0xFFFF;
            PSWCCR = sr & 0x1F;
            PSWS   = (sr >> 13) & 1;
            PSWS2  = (sr >> 13) & 1;
            PSWT   = (sr >> 15) & 1;
            PSWI   = (sr >>  8) & 7;
            PSW    = sr;
        }

        // ---- run until the core issues its first fetch AT 'boot' (the instr) ----
        auto serve=[&]()
        {
            if (!top->ASn)
            {
                uint32_t a = ((uint32_t)top->eab << 1) & 0xFFFFFF;
                top->DTACKn=0;
                if (top->eRWn)
                {
                    top->iEdb = ((uint16_t)rd8(a) << 8) | rd8(a+1);
                }
                else
                {
                    if(!top->UDSn) wr8(a,(top->oEdb>>8)&0xFF);
                    if(!top->LDSn) wr8(a+1,top->oEdb&0xFF);
                }
                return a;
            }
            else
            {
                top->DTACKn=1;
                return (uint32_t)0xFFFFFFFF;
            }
        };
        // D/A/USP regs were loaded DURING reset (below). Now run until the target
        // instruction (pf[0]) latches in IRD, then execute until it RETIRES
        // (IRD reloads to a different opcode = next instruction fetched). Sample
        // the final state at the last cycle before that reload.
        uint16_t opc = t.ini.pf[0];
        bool latched=false; int guard=0;
        // snapshot-on-retire: keep last state while opc is in IRD
        uint32_t snapR[19]; uint16_t snapCCR=0; bool have_snap=false;
        auto snapshot=[&]()
        {
            for (int i = 0; i < 17; i++)
                snapR[i] = get_reg(i < 15 ? i : (i));
            snapCCR = PSWCCR & 0x1F;
            have_snap = true;
        };

        while (guard++<4000)
        {
          serve();
          uint16_t ird = RIRD;
          if(!latched){ if(ird==opc){ latched=true; } }
          else {
            if(ird==opc){ snapshot(); }        // still executing target: keep snapping
            else {
              // IRD reloaded: target is retiring. Snapshot CCR now (final flags),
              // then run a few more cycles to let the late register writeback land,
              // updating only the register snapshot.
              snapshot();
              for(int k=0;k<8;k++){ serve(); step(); for(int r=0;r<17;r++) snapR[r]=get_reg(r); }
              break;
            }
          }
          step();
        }
        (void)have_snap;

        // ---- execute for the test's cycle length (plus slack), serving bus ----
        for(int i=0;i<t.len*4+60;i++){ serve(); step(); }

        // ---- compare D/A regs + CCR at retirement snapshot ----
        bool ok=true;
        std::string diff;
        if (!have_snap)
        {
            ok=false; diff="NO_RETIRE ";
        }
        else
        {
            for(int i=0;i<8;i++) if(snapR[i]!=t.fin.r[i]){ok=false;char b[64];sprintf(b,"D%d=%08X!=%08X ",i,snapR[i],t.fin.r[i]);diff+=b;}
            for(int i=0;i<7;i++) if(snapR[8+i]!=t.fin.r[8+i]){ok=false;char b[64];sprintf(b,"A%d=%08X!=%08X ",i,snapR[8+i],t.fin.r[8+i]);diff+=b;}
            uint16_t exp_ccr=t.fin.r[17]&0x1F;
            if(snapCCR!=exp_ccr){ok=false;char b[64];sprintf(b,"CCR=%02X!=%02X ",snapCCR,exp_ccr);diff+=b;}
        }
        if(ok) pass++; else { fail++; if(verbose && fail<=1000) printf("FAIL %s: %s\n", t.name.c_str(), diff.c_str()); }
    }
    printf("RESULT: %d pass, %d fail (of %d run)\n", pass, fail, done);

#if VM_TRACE
    if (tfp) tfp->close();
#endif /* VM_TRACE */
    delete top;

    return 0;
}
