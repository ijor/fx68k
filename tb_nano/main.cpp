// Macros to build include file name
#define _quoted_string(x) #x
#define quoted_string(x) _quoted_string(x)
#define _symbols_header(x) _quoted_string(x##__Syms.h)
#define symbols_header(x) _symbols_header(x)
// Top level
#include symbols_header(VM_PREFIX)

#include <ctime>

#if VM_TRACE
#include "verilated_vcd_c.h"
#endif

int main(int argc, char **argv, char **env)
{
    // Simulation duration
    clock_t beg, end;
    double secs;
    // Trace index
    int trc_idx = 0;
    int min_idx = 0;
    // File name generation
    char file_name[256];
    // Simulation time
    vluint64_t tb_time;
    vluint64_t max_time;
    // Testbench configuration
    const char *arg;
    // Clock generation
    int clk_ctr = 0;
    
    beg = clock();
    
    // Parse parameters
    Verilated::commandArgs(argc, argv);
    
    // Default : 1 msec
    max_time = (vluint64_t)1000000000;
    
    // Simulation duration : +usec=<num>
    arg = Verilated::commandArgsPlusMatch("usec=");
    if ((arg) && (arg[0]))
    {
        arg += 6;
        max_time = (vluint64_t)atoi(arg) * (vluint64_t)1000000;
    }
    
    // Simulation duration : +msec=<num>
    arg = Verilated::commandArgsPlusMatch("msec=");
    if ((arg) && (arg[0]))
    {
        arg += 6;
        max_time = (vluint64_t)atoi(arg) * (vluint64_t)1000000000;
    }
    
    // Trace start index : +tidx=<num>
    arg = Verilated::commandArgsPlusMatch("tidx=");
    if ((arg) && (arg[0]))
    {
        arg += 6;
        min_idx = atoi(arg);
    }
    else
    {
        min_idx = 0;
    }
    
    // Initialize top verilog instance
    VM_PREFIX* top = new VM_PREFIX;
    
    tb_time = (vluint64_t)0;
    top->clk = 0;
    
    
#if VM_TRACE
    // Initialize VCD trace dump
    Verilated::traceEverOn(true);
    VerilatedVcdC* tfp = new VerilatedVcdC;
    top->trace (tfp, 99);
    tfp->spTrace()->set_time_resolution ("1 ps");
    if (trc_idx == min_idx)
    {
        sprintf(file_name, quoted_string(VM_PREFIX) "_%04d.vcd", trc_idx);
        printf("Opening VCD file \"%s\"\n", file_name);
        tfp->open (file_name);
    }
#endif /* VM_TRACE */
  
    // Reset loop
    top->rst = 1;
    while (tb_time < (vluint64_t)100000)
    {
        // Toggle clocks
        top->clk    =  clk_ctr & 1;
        top->enPhi1 = (clk_ctr & 2) ? 1 : 0;
        top->enPhi2 = (clk_ctr & 2) ? 0 : 1;
        clk_ctr     = (clk_ctr + 1) & 3;
        tb_time    += (vluint64_t)5000;
        // Evaluate verilated model
        top->eval ();
        
#if VM_TRACE
        // Dump signals into VCD file
        if (tfp)
        {
            if (trc_idx >= min_idx)
            {
                tfp->dump (tb_time);
            }
        }
#endif /* VM_TRACE */
    }
    top->rst = 0;

    // Simulation loop
    while (tb_time < max_time)
    {
        // Toggle clocks
        top->clk    =  clk_ctr & 1;
        top->enPhi1 = (clk_ctr & 2) ? 1 : 0;
        top->enPhi2 = (clk_ctr & 2) ? 0 : 1;
        clk_ctr     = (clk_ctr + 1) & 3;
        tb_time    += (vluint64_t)5000;
        // Evaluate verilated model
        top->eval ();
        
#if VM_TRACE
        // Dump signals into VCD file
        if (tfp)
        {
            if (trc_idx >= min_idx)
            {
                tfp->dump (tb_time);
            }
        }
#endif /* VM_TRACE */

        if (Verilated::gotFinish()) break;
    }
    
#if VM_TRACE
    if (tfp && trc_idx >= min_idx) tfp->close();
#endif /* VM_TRACE */

    top->final();
    
    delete top;
    
    // Calculate running time
    end = clock();
    printf("\nSeconds elapsed : %5.3f\n", (float)(end - beg) / CLOCKS_PER_SEC);

    exit(0);
}
