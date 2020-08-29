//
// FX68K
//
// M68000 cycle accurate, fully synchronous
// Copyright (c) 2018 by Jorge Cwik
//
// TODO:
// - Everything except bus retry already implemented.

`timescale 1 ns / 1 ns

// Define this to run a self contained compilation test build
// `define FX68K_TEST

`ifdef _VLINT_
`include "fx68k_pkg.sv"
`include "uaddrPla.sv"
`include "fx68kAlu.sv"
`endif /* _VLINT_ */

import fx68k_pkg::*;

module fx68k
(
    input         clk,      // Master clock
    input         enPhi1,   // Clock enable : next cycle is PHI1 (clock rising edge)
    input         enPhi2,   // Clock enable : next cycle is PHI2 (clock falling edge)
    
    input         HALTn,    // Used for single step only. Force high if not used
    // These two signals don't need to be registered. They are not async reset.
    input         extReset, // External sync reset on emulated system
    input         pwrUp,    // Asserted together with reset on emulated system coldstart
    output        oRESETn,
    output        oHALTEDn,
    // 6800 peripheral access
    output logic  E,        // E clock
    output        E_rise,   // E clock rising edge
    output        E_fall,   // E clock falling edge
    input         VPAn,     // Valid peripheral address
    output        VMAn,     // Valid memory address
    // Control signals
    output        ASn,      // Address strobe
    output        eRWn,     // Read (1) / Write (0)
    output        LDSn,     // Lower data strobe
    output        UDSn,     // Upper data strobe
    output        FC2,      // Function code
    output        FC1,
    output        FC0,
    input         DTACKn,   // Data acknowledge
    input         BERRn,    // Bus error
    // Bus cycles stealing
    input         BRn,      // Bus request
    output        BGn,      // Bus granted
    input         BGACKn,   // Bus granted acknowledge
    // Interrupts requests
    input         IPL2n,    // Interrupt level
    input         IPL1n,
    input         IPL0n,
    // Data bus
    input  [15:0] iEdb,
    output [15:0] oEdb,
    // Address bus
    output [31:1] eab
);

    s_clks Clks;

    //assign Clks.clk      = clk;
    assign Clks.extReset = extReset;
    assign Clks.pwrUp    = pwrUp;
    assign Clks.enPhi1   = enPhi1;
    assign Clks.enPhi2   = enPhi2;

    wire wClk;

    // Internal sub clocks T1-T4
    localparam
        T0 = 0,
        T1 = 1,
        T2 = 2,
        T3 = 3,
        T4 = 4;
    reg [4:0] tState;

    // T4 continues ticking during reset and group0 exception.
    // We also need it to erase ucode output latched on T4.
    always_ff @(posedge clk) begin

        if (Clks.pwrUp) begin
            tState <= 5'b00001; // T0
        end
        else begin
            tState <= 5'b00000;
            case (1'b1)
                tState[T0]:
                begin
                    if (Clks.enPhi2) begin
                        tState[T4] <= 1'b1;
                    end
                    else begin
                        tState[T0] <= 1'b1;
                    end
                end
                tState[T1]:
                begin
                    if (Clks.enPhi2) begin
                        tState[T2] <= 1'b1;
                    end
                    else begin
                        tState[T1] <= 1'b1;
                    end
                end
                tState[T2]:
                begin
                    if (Clks.enPhi1) begin
                        tState[T3] <= 1'b1;
                    end
                    else begin
                        tState[T2] <= 1'b1;
                    end
                end
                tState[T3]:
                begin
                    if (Clks.enPhi2) begin
                        tState[T4] <= 1'b1;
                    end
                    else begin
                        tState[T3] <= 1'b1;
                    end
                end
                tState[T4]:
                begin
                    if (Clks.enPhi1) begin
                        tState[T0] <= wClk;
                        tState[T1] <= ~wClk;
                    end
                    else begin
                        tState[T4] <= 1'b1;
                    end
                end
            endcase
        end
    end

    wire enT1 = Clks.enPhi1 & tState[T4] & ~wClk;
    wire enT2 = Clks.enPhi2 & tState[T1];
    wire enT3 = Clks.enPhi1 & tState[T2];
    wire enT4 = Clks.enPhi2 & (tState[T0] | tState[T3]);

    // The following signals are synchronized with 3 couplers, phi1-phi2-phi1.
    // Will be valid internally one cycle later if changed at the rasing edge of the clock.
    //
    // DTACK, BERR

    // DTACK valid at S6 if changed at the rasing edge of S4 to avoid wait states.
    // SNC (sncClkEn) is deasserted together (unless DTACK asserted too early).
    //
    // We synchronize some signals half clock earlier. We compensate later
    reg rDtack, rBerr;
    reg [2:0] rIpl, iIpl;
    reg Vpai, BeI, Halti, BRi, BgackI, BeiDelay;
    // reg rBR, rHALT;
    wire BeDebounced = ~( BeI | BeiDelay);

    always_ff @(posedge clk) begin

        if (Clks.pwrUp) begin
            rBerr    <= 1'b0;
            BeI      <= 1'b0;
        end
        else if (Clks.enPhi2) begin
            rDtack   <= DTACKn;
            rBerr    <= BERRn;
            rIpl     <= ~{ IPL2n, IPL1n, IPL0n};
            iIpl     <= rIpl;

            // Needed for cycle accuracy but only if BR or HALT are asserted on the wrong edge of the clock
            // rBR <= BRn;
            // rHALT <= HALTn;
        end
        else if (Clks.enPhi1) begin
            Vpai     <= VPAn;
            BeI      <= rBerr;
            BeiDelay <= BeI;
            BgackI   <= BGACKn;

            BRi      <= BRn;
            Halti    <= HALTn;
            // BRi <= rBR;
            // Halti <= rHALT;
        end
    end

    // Instantiate micro and nano rom
    logic  [NANO_WIDTH-1:0] nanoLatch;
    logic  [NANO_WIDTH-1:0] nanoOutput;
    logic  [UROM_WIDTH-1:0] microLatch;
    logic  [UROM_WIDTH-1:0] microOutput;

    logic [UADDR_WIDTH-1:0] microAddr, nma;
    logic [NADDR_WIDTH-1:0] nanoAddr, orgAddr;
    wire rstUrom;

    // For the time being, address translation is done for nanorom only.
    microToNanoAddr microToNanoAddr( .uAddr( nma), .orgAddr);

    // Output of these modules will be updated at T2 at the latest (depending on clock division)

    nanoRom nanoRom( .clk(clk), .nanoAddr, .nanoOutput);
    uRom uRom( .clk(clk), .microAddr, .microOutput);

    always_ff @(posedge clk) begin
        // uaddr originally latched on T1, except bits 6 & 7, the conditional bits, on T2
        // Seems we can latch whole address at either T1 or T2

        // Originally it's invalid on hardware reset, and forced later when coming out of reset
        if (Clks.pwrUp) begin
            microAddr <= RSTP0_NMA[UADDR_WIDTH-1:0];
            nanoAddr  <= RSTP0_NMA[NADDR_WIDTH-1:0];
        end
        else if (enT1) begin
            microAddr <= nma;
            nanoAddr  <= orgAddr;                // Register translated uaddr to naddr
        end

        if (Clks.extReset) begin
            microLatch <= {UROM_WIDTH{1'b0}};
            nanoLatch  <= {NANO_WIDTH{1'b0}};
        end
        else if (rstUrom) begin
            // Originally reset these bits only. Not strictly needed like this.
            // Can reset the whole register if it is important.
            microLatch[16] <= 1'b0;
            microLatch[15] <= 1'b0;
            microLatch[0]  <= 1'b0;
            nanoLatch      <= {NANO_WIDTH{1'b0}};
        end
        else if (enT3) begin
            microLatch <= microOutput;
            nanoLatch  <= nanoOutput;
        end
    end


    // Decoded nanocode signals
    s_nanod_r Nanod_r;
    s_nanod_w Nanod_w;
    // IRD decoded control signals
    s_irdecod Irdecod;

    //
    reg         Tpend;
    reg         intPend; // Interrupt pending
    reg         pswT;
    reg         pswS;
    reg   [2:0] pswI;
    wire  [7:0] ccr;

    wire [15:0] psw = { pswT, 1'b0, pswS, 2'b00, pswI, ccr };

    reg  [15:0] ftu;
    reg  [15:0] Irc, Ir, Ird;

    wire [15:0] alue;
    wire [15:0] Abl;
    wire prenEmpty, au05z, dcr4, ze;

    wire [UADDR_WIDTH-1:0] a1, a2, a3;
    wire isPriv, isIllegal, isLineA, isLineF;


    // IR & IRD forwarding
    always_ff @(posedge clk) begin

        if (enT1) begin
            if (Nanod_w.Ir2Ird) begin
                Ird <= Ir;
            end
            else if(microLatch[0]) begin
                // prevented by IR => IRD !
                Ir <= Irc;
            end
        end
    end

    wire [3:0] tvn;
    wire waitBusCycle, busStarting;
    wire BusRetry = 1'b0;
    wire busAddrErr;
    wire bciWrite;                      // Last bus cycle was write
    wire bgBlock, busAvail;
    wire addrOe;

    wire busIsByte = Nanod_w.busByte & (Irdecod.isByte | Irdecod.isMovep);
    wire aob0;

    reg iStop;                              // Internal signal for ending bus cycle
    reg A0Err;                              // Force bus/address error ucode
    reg excRst;                             // Signal reset exception to sequencer
    reg BerrA;
    reg Spuria, Avia;
    wire Iac;

    reg rAddrErr, iBusErr, Err6591;
    wire iAddrErr = rAddrErr & addrOe;      // To simulate async reset
    wire enErrClk;

    // Reset micro/nano latch after T4 of the current ublock.
    assign rstUrom = Clks.enPhi1 & enErrClk;

    uaddrDecode U_uaddrDecode
    (
        .opcode (Ir),
        .a1, .a2, .a3, .isPriv, .isIllegal, .isLineA, .isLineF, .lineBmap()
    );

    sequencer sequencer( .clk, .Clks, .enT3, .microLatch, .Ird,
        .A0Err, .excRst, .BerrA, .busAddrErr, .Spuria, .Avia,
        .Tpend, .intPend, .isIllegal, .isPriv, .isLineA, .isLineF,
        .nma, .a1, .a2, .a3, .tvn,
        .psw, .prenEmpty, .au05z, .dcr4, .ze, .alue01( alue[1:0]), .i11( Irc[ 11]) );

    excUnit excUnit( .clk, .Clks, .Nanod_r, .Nanod_w, .Irdecod, .enT1, .enT2, .enT3, .enT4,
        .Ird, .ftu, .iEdb, .pswS,
        .prenEmpty, .au05z, .dcr4, .ze, .AblOut( Abl), .eab, .aob0, .Irc, .oEdb,
        .alue, .ccr);

    nDecoder3 nDecoder( .clk, .Nanod_r, .Nanod_w, .Irdecod, .enT2, .enT4, .microLatch, .nanoLatch);

    irdDecode irdDecode( .ird( Ird), .Irdecod);

    busControl busControl( .clk, .Clks, .enT1, .enT4, .permStart(Nanod_w.permStart), .permStop(Nanod_w.waitBusFinish), .iStop,
        .aob0, .isWrite(Nanod_w.isWrite), .isRmc(Nanod_r.isRmc), .isByte(busIsByte), .busAvail,
        .bciWrite, .addrOe, .bgBlock, .waitBusCycle, .busStarting, .busAddrErr,
        .rDtack, .BeDebounced, .Vpai,
        .ASn, .LDSn, .UDSn, .eRWn);

    busArbiter busArbiter( .clk, .Clks, .BRi, .BgackI, .Halti, .bgBlock, .busAvail, .BGn);


    // Output reset & halt control
    wire [1:0] uFc = microLatch[16:15];
    logic oReset, oHalted;
    assign oRESETn = !oReset;
    assign oHALTEDn = !oHalted;

    // FC without permStart is special, either reset or halt
    always_ff @(posedge clk) begin

        if (Clks.pwrUp) begin
            oReset  <= 1'b0;
            oHalted <= 1'b0;
        end
        else if (enT1) begin
            oReset  <= (uFc == 2'b01) ? ~Nanod_w.permStart : 1'b0;
            oHalted <= (uFc == 2'b10) ? ~Nanod_w.permStart : 1'b0;
        end
    end

    logic [2:0] rFC;
    assign { FC2, FC1, FC0} = rFC;                  // ~rFC;
    assign Iac = {rFC == 3'b111};                   // & Control output enable !!

    always_ff @(posedge clk) begin

        if (Clks.extReset) begin
            rFC <= 3'b000;
        end
        else if (enT1 & Nanod_w.permStart) begin      // S0 phase of bus cycle
            rFC[2] <= pswS;
            // If FC is type 'n' (0) at ucode, access type depends on PC relative mode
            // We don't care about RZ in this case. Those uinstructions with RZ don't start a bus cycle.
            rFC[1] <= microLatch[ 16] | ( ~microLatch[ 15] &  Irdecod.isPcRel);
            rFC[0] <= microLatch[ 15] | ( ~microLatch[ 16] & ~Irdecod.isPcRel);
        end
    end


    // IPL interface
    reg [2:0] inl;                          // Int level latch
    reg updIll;
    reg prevNmi;

    wire nmi = (iIpl == 3'b111);
    wire iplStable = (iIpl == rIpl);
    wire iplComp = iIpl > pswI;

    always_ff @(posedge clk) begin

        if (Clks.extReset) begin
            intPend <= 1'b0;
            prevNmi <= 1'b0;
        end
        else begin
            if (Clks.enPhi2) begin
                prevNmi <= nmi;
            end

            // Originally async RS-Latch on PHI2, followed by a transparent latch on T2
            // Tricky because they might change simultaneously
            // Syncronous on PHI2 is equivalent as long as the output is read on T3!

            // Set on stable & NMI edge or compare
            // Clear on: NMI Iack or (stable & !NMI & !Compare)

            if (Clks.enPhi2) begin
                if (iplStable & ((nmi & ~prevNmi) | iplComp)) begin
                    intPend <= 1'b1;
                end
                else if (((inl == 3'b111) & Iac) | (iplStable & !nmi & !iplComp)) begin
                    intPend <= 1'b0;
                end
            end
        end

        if (Clks.extReset) begin
            inl    <= '1;
            updIll <= 1'b0;
        end
        else if (enT4)
            updIll <= microLatch[0];        // Update on any IRC->IR
        else if (enT1 & updIll)
            inl <= iIpl;                    // Timing is correct.

        // Spurious interrupt, BERR on Interrupt Ack.
        // Autovector interrupt. VPA on IACK.
        // Timing is tight. Spuria is deasserted just after exception exception is recorded.
        if (enT4) begin
            Spuria <= ~BeiDelay & Iac;
            Avia   <= ~Vpai & Iac;
        end

    end

    assign enErrClk = iAddrErr | iBusErr;
    assign wClk = waitBusCycle | ~BeI | iAddrErr | Err6591;

    // E clock and counter, VMA
    reg [3:0] eCntr;
    reg       rVma;

    assign VMAn = rVma;

    // Internal stop just one cycle before E falling edge
    wire xVma = ~rVma & (eCntr == 8);

    always_ff @(posedge clk) begin

        if (Clks.pwrUp) begin
            E     <= 1'b0;
            eCntr <= 4'd0;
            rVma  <= 1'b1;
        end
        
        // Cycles counter
        if (Clks.enPhi2) begin
            eCntr <= (eCntr == 4'd9) ? 4'd0 : eCntr + 4'd1;
        end
        
        // E clock generation
        E <= (E | E_rise) & ~E_fall;

        if (Clks.enPhi2 & addrOe & ~Vpai & (eCntr == 4'd3))
            rVma <= 1'b0;
        else if (Clks.enPhi1 & eCntr == 4'd0)
            rVma <= 1'b1;
    end

    assign E_rise = (eCntr == 4'd5) ? Clks.enPhi2 : 1'b0;
    assign E_fall = (eCntr == 4'd9) ? Clks.enPhi2 : 1'b0;

    always_ff @(posedge clk) begin

        // This timing is critical to stop the clock phases at the exact point on bus/addr error.
        // Timing should be such that current ublock completes (up to T3 or T4).
        // But T1 for the next ublock shouldn't happen. Next T1 only after resetting ucode and ncode latches.

        if (Clks.extReset)
            rAddrErr <= 1'b0;
        else if (Clks.enPhi1) begin
            if (busAddrErr & addrOe)        // Not on T1 ?!
                rAddrErr <= 1'b1;
            else if (~addrOe)               // Actually async reset!
                rAddrErr <= 1'b0;
        end

        if (Clks.extReset)
            iBusErr <= 1'b0;
        else if (Clks.enPhi1) begin
            iBusErr <= ( BerrA & ~BeI & ~Iac & !BusRetry);
        end

        if (Clks.extReset)
            BerrA <= 1'b0;
        else if (Clks.enPhi2) begin
            if (~BeI & ~Iac & addrOe)
                BerrA <= 1'b1;
            // else if (BeI & addrOe)           // Bad, async reset since addrOe raising edge
            else if (BeI & busStarting)         // So replaced with this that raises one cycle earlier
                BerrA <= 1'b0;
        end

        // Signal reset exception to sequencer.
        // Originally cleared on 1st T2 after permstart. Must keep it until TVN latched.
        if (Clks.extReset)
            excRst <= 1'b1;
        else if (enT2 & Nanod_w.permStart)
            excRst <= 1'b0;

        if (Clks.extReset)
            A0Err <= 1'b1;                              // A0 Reset
        else if (enT3)                                  // Keep set until new urom words are being latched
            A0Err <= 1'b0;
        else if (Clks.enPhi1 & enErrClk & (busAddrErr | BerrA))     // Check bus error timing
            A0Err <= 1'b1;

        if (Clks.extReset) begin
            iStop <= 1'b0;
            Err6591 <= 1'b0;
        end
        else if (Clks.enPhi1)
            Err6591 <= enErrClk;
        else if (Clks.enPhi2)
            iStop <= xVma | (Vpai & (iAddrErr | ~rBerr));
    end

    // PSW
    logic irdToCcr_t4;
    always_ff @(posedge clk) begin

        if (Clks.pwrUp) begin
            Tpend <= 1'b0;
            { pswT, pswS, pswI } <= 5'b0_0_000;
            irdToCcr_t4 <= '0;
        end

        else if (enT4) begin
            irdToCcr_t4 <= Irdecod.toCcr;
        end

        else if (enT3) begin

            // UNIQUE IF !!
            if (Nanod_w.updTpend)
                Tpend <= pswT;
            else if (Nanod_w.clrTpend)
                Tpend <= 1'b0;

            // UNIQUE IF !!
            if (Nanod_w.ftu2Sr & !irdToCcr_t4) begin
                { pswT, pswS, pswI } <= { ftu[15], ftu[13], ftu[10:8]};
            end
            else begin
                if (Nanod_w.initST) begin
                    pswS <= 1'b1;
                    pswT <= 1'b0;
                end
                if (Nanod_w.inl2psw) begin
                    pswI <= inl;
                end
            end
        end
    end

    // FTU
    reg    [4:0] ssw;
    reg    [3:0] tvnLatch;
    logic [15:0] tvnMux;
    reg          inExcept01;

    // Seems CPU has a buglet here.
    // Flagging group 0 exceptions from TVN might not work because some bus cycles happen before TVN is updated.
    // But doesn't matter because a group 0 exception inside another one will halt the CPU anyway and won't save the SSW.

    always_ff @(posedge clk) begin

        // Updated at the start of the exception ucode
        if (Nanod_w.updSsw & enT3) begin
            ssw <= { ~bciWrite, inExcept01, rFC};
        end

        // Update TVN on T1 & IR=>IRD
        if (enT1 & Nanod_w.Ir2Ird) begin
            tvnLatch <= tvn;
            inExcept01 <= (tvn != 4'h1);
        end

        if (Clks.pwrUp) begin
            ftu <= 16'h0000;
        end
        else if (enT3) begin
            unique case (1'b1)
                Nanod_w.tvn2Ftu:   ftu <= tvnMux;

                // 0 on unused bits seem to come from ftuConst PLA previously clearing FBUS
                Nanod_w.sr2Ftu:    ftu <= {pswT, 1'b0, pswS, 2'b00, pswI, 3'b000, ccr[4:0] };

                Nanod_w.ird2Ftu:   ftu <= Ird;
                Nanod_w.ssw2Ftu:   ftu[4:0] <= ssw;                        // Undoc. Other bits must be preserved from IRD saved above!
                Nanod_w.pswIToFtu: ftu <= { 12'hFFF, pswI, 1'b0};          // Interrupt level shifted
                Nanod_w.const2Ftu: ftu <= Irdecod.ftuConst;
                Nanod_w.abl2Pren:  ftu <= Abl;                             // From ALU or datareg. Used for SR modify
                default:           ftu <= ftu;
            endcase
        end
    end

    always_comb begin

        if (inExcept01) begin
            // Unique IF !!!
            if (tvnLatch == TVN_SPURIOUS)
                tvnMux = { 9'b0, 5'd24, 2'b0 };
            else if (tvnLatch == TVN_AUTOVEC)
                tvnMux = { 9'b0, 2'b11, pswI, 2'b0 };                // Set TVN PLA decoder
            else if (tvnLatch == TVN_INTERRUPT)
                tvnMux = { 6'b0, Ird[7:0], 2'b0 };                   // Interrupt vector was read and transferred to IRD
            else
                tvnMux = { 10'b0, tvnLatch, 2'b0 };
        end
        else begin
            tvnMux = { 8'h0, Irdecod.macroTvn, 2'b0 };
        end
    end

endmodule

// Nanorom (plus) decoder for die nanocode
module nDecoder3
(
    input                   clk,
    input                   enT2,
    input                   enT4,
    input  [UROM_WIDTH-1:0] microLatch,
    input  [NANO_WIDTH-1:0] nanoLatch,
    input                   s_irdecod Irdecod,
    output                  s_nanod_r Nanod_r,
    output                  s_nanod_w Nanod_w
);

localparam
    NANO_IR2IRD       = 67,
    NANO_TOIRC        = 66,
    NANO_ALU_COL      = 63, // ALU operator column order is 63-64-65 !
    NANO_ALU_FI       = 61, // ALU finish-init 62-61
    NANO_TODBIN       = 60,
    NANO_ALUE         = 57, // 57-59 shared with DCR control
    NANO_DCR          = 57, // 57-59 shared with ALUE control
    NANO_DOBCTRL_1    = 56, // Input to control and permwrite
    NANO_LOWBYTE      = 55, // Used by MOVEP
    NANO_HIGHBYTE     = 54,
    NANO_DOBCTRL_0    = 53, // Input to control and permwrite
    NANO_ALU_DCTRL    = 51, // 52-51 databus input mux control
    NANO_ALU_ACTRL    = 50, // addrbus input mux control
    NANO_DBD2ALUB     = 49,
    NANO_ABD2ALUB     = 48,
    NANO_DBIN2DBD     = 47,
    NANO_DBIN2ABD     = 46,
    NANO_ALU2ABD      = 45,
    NANO_ALU2DBD      = 44,
    NANO_RZ           = 43,
    NANO_BUSBYTE      = 42, // If *both* this set and instruction is byte sized, then bus cycle is byte sized.
    NANO_PCLABL       = 41,
    NANO_RXL_DBL      = 40, // Switches RXL/RYL on DBL/ABL buses
    NANO_PCLDBL       = 39,
    NANO_ABDHRECHARGE = 38,
    NANO_REG2ABL      = 37, // register to ABL
    NANO_ABL2REG      = 36, // ABL to register
    NANO_ABLABD       = 35,
    NANO_DBLDBD       = 34,
    NANO_DBL2REG      = 33, // DBL to register
    NANO_REG2DBL      = 32, // register to DBL
    NANO_ATLCTRL      = 29, // 31-29
    NANO_FTUCONTROL   = 25,
    NANO_SSP          = 24,
    NANO_RXH_DBH      = 22, // Switches RXH/RYH on DBH/ABH buses
    NANO_AUOUT        = 20, // 21-20
    NANO_AUCLKEN      = 19,
    NANO_AUCTRL       = 16, // 18-16
    NANO_DBLDBH       = 15,
    NANO_ABLABH       = 14,
    NANO_EXT_ABH      = 13,
    NANO_EXT_DBH      = 12,
    NANO_ATHCTRL      = 9,  // 11-9
    NANO_REG2ABH      = 8,  // register to ABH
    NANO_ABH2REG      = 7,  // ABH to register
    NANO_REG2DBH      = 6,  // register to DBH
    NANO_DBH2REG      = 5,  // DBH to register
    NANO_AOBCTRL      = 3,  // 4-3
    NANO_PCH          = 0,  // 1-0 PchDbh PchAbh
    NANO_NO_SP_ALGN   = 0;  // Same bits as above when both set

// Reverse order!
localparam [3:0]
    NANO_FTU_UPDTPEND = 4'b1000, // Also loads FTU constant according to IRD !
    NANO_FTU_INIT_ST  = 4'b1111, // Set S, clear T (but not TPEND)
    NANO_FTU_CLRTPEND = 4'b0111,
    NANO_FTU_TVN      = 4'b1011,
    NANO_FTU_ABL2PREN = 4'b0011, // ABL => FTU & ABL => PREN. Both transfers enabled, but only one will be used depending on uroutine.
    NANO_FTU_SSW      = 4'b1101,
    NANO_FTU_RSTPREN  = 4'b0101,
    NANO_FTU_IRD      = 4'b1001,
    NANO_FTU_2ABL     = 4'b0001,
    NANO_FTU_RDSR     = 4'b1110,
    NANO_FTU_INL      = 4'b0110,
    NANO_FTU_PSWI     = 4'b1010, // Read Int Mask into FTU
    NANO_FTU_DBL      = 4'b0010,
    NANO_FTU_2SR      = 4'b0100,
    NANO_FTU_CONST    = 4'b1000;

    reg [3:0] ftuCtrl;

    wire [2:0] athCtrl = nanoLatch[NANO_ATHCTRL +: 3];
    wire [2:0] atlCtrl = nanoLatch[NANO_ATLCTRL +: 3];
    wire [1:0] aobCtrl = nanoLatch[NANO_AOBCTRL +: 2];
    wire [1:0] dobCtrl = { nanoLatch[ NANO_DOBCTRL_1], nanoLatch[NANO_DOBCTRL_0] };

    always_ff @(posedge clk) begin

        if (enT4) begin

            ftuCtrl           <= nanoLatch[NANO_FTUCONTROL +: 4];

            Nanod_r.auClkEn   <= ~nanoLatch[NANO_AUCLKEN];
            Nanod_r.auCntrl   <=  nanoLatch[NANO_AUCTRL +: 3];
            Nanod_r.noSpAlign <= &nanoLatch[NANO_NO_SP_ALGN +: 2];
            Nanod_r.extDbh    <=  nanoLatch[NANO_EXT_DBH];
            Nanod_r.extAbh    <=  nanoLatch[NANO_EXT_ABH];
            Nanod_r.todbin    <=  nanoLatch[NANO_TODBIN];
            Nanod_r.toIrc     <=  nanoLatch[NANO_TOIRC];

            // ablAbd is disabled on byte transfers (adbhCharge plus irdIsByte). Not sure the combination makes much sense.
            // It happens in a few cases but I don't see anything enabled on abL (or abH) section anyway.

            Nanod_r.ablAbd    <= nanoLatch[NANO_ABLABD];
            Nanod_r.ablAbh    <= nanoLatch[NANO_ABLABH];
            Nanod_r.dblDbd    <= nanoLatch[NANO_DBLDBD];
            Nanod_r.dblDbh    <= nanoLatch[NANO_DBLDBH];

            Nanod_r.dbl2Atl   <= (atlCtrl[2:0] == 3'b010) ? 1'b1 : 1'b0;
            Nanod_r.atl2Dbl   <= (atlCtrl[2:0] == 3'b011) ? 1'b1 : 1'b0;
            Nanod_r.abl2Atl   <= (atlCtrl[2:0] == 3'b100) ? 1'b1 : 1'b0;
            Nanod_r.atl2Abl   <= (atlCtrl[2:0] == 3'b101) ? 1'b1 : 1'b0;

            Nanod_r.aob2Ab    <= (athCtrl[2:0] == 3'b101) ? 1'b1 : 1'b0; // Used on BSER1 only

            Nanod_r.abh2Ath   <= (athCtrl[1:0] == 2'b01 ) ? 1'b1 : 1'b0;
            Nanod_r.dbh2Ath   <= (athCtrl[2:0] == 3'b100) ? 1'b1 : 1'b0;
            Nanod_r.ath2Dbh   <= (athCtrl[2:0] == 3'b110) ? 1'b1 : 1'b0;
            Nanod_r.ath2Abh   <= (athCtrl[2:0] == 3'b011) ? 1'b1 : 1'b0;

            Nanod_r.alu2Dbd   <= nanoLatch[NANO_ALU2DBD];
            Nanod_r.alu2Abd   <= nanoLatch[NANO_ALU2ABD];

            Nanod_r.abd2Dcr   <= (nanoLatch[NANO_DCR+0 +: 2]  == 2'b11) ? 1'b1 : 1'b0;
            Nanod_r.dcr2Dbd   <= (nanoLatch[NANO_DCR+1 +: 2]  == 2'b11) ? 1'b1 : 1'b0;
            Nanod_r.dbd2Alue  <= (nanoLatch[NANO_ALUE+1 +: 2] == 2'b10) ? 1'b1 : 1'b0;
            Nanod_r.alue2Dbd  <= (nanoLatch[NANO_ALUE+0 +: 2] == 2'b01) ? 1'b1 : 1'b0;

            Nanod_r.dbd2Alub  <= nanoLatch[NANO_DBD2ALUB];
            Nanod_r.abd2Alub  <= nanoLatch[NANO_ABD2ALUB];

            // Originally not latched. We better should because we transfer one cycle later, T3 instead of T1.
            Nanod_r.dobCtrl   <= dobCtrl;
            // Nanod_r.adb2Dob <= (dobCtrl == 2'b10);
            // Nanod_r.dbd2Dob <= (dobCtrl == 2'b01);
            // Nanod_r.alu2Dob <= (dobCtrl == 2'b11);

            // Might be better not to register these signals to allow latching RX/RY mux earlier!
            // But then must latch Irdecod.isPcRel on T3!

            Nanod_r.rxl2db  <= Nanod_w.reg2dbl & ~dblSpecial &  nanoLatch[NANO_RXL_DBL];
            Nanod_r.rxl2ab  <= Nanod_w.reg2abl & ~ablSpecial & ~nanoLatch[NANO_RXL_DBL];

            Nanod_r.dbl2rxl <= Nanod_w.dbl2reg & ~dblSpecial &  nanoLatch[NANO_RXL_DBL];
            Nanod_r.abl2rxl <= Nanod_w.abl2reg & ~ablSpecial & ~nanoLatch[NANO_RXL_DBL];

            Nanod_r.rxh2dbh <= Nanod_w.reg2dbh & ~dbhSpecial &  nanoLatch[NANO_RXH_DBH];
            Nanod_r.rxh2abh <= Nanod_w.reg2abh & ~abhSpecial & ~nanoLatch[NANO_RXH_DBH];

            Nanod_r.dbh2rxh <= Nanod_w.dbh2reg & ~dbhSpecial &  nanoLatch[NANO_RXH_DBH];
            Nanod_r.abh2rxh <= Nanod_w.abh2reg & ~abhSpecial & ~nanoLatch[NANO_RXH_DBH];

            Nanod_r.dbh2ryh <= Nanod_w.dbh2reg & ~dbhSpecial & ~nanoLatch[NANO_RXH_DBH];
            Nanod_r.abh2ryh <= Nanod_w.abh2reg & ~abhSpecial &  nanoLatch[NANO_RXH_DBH];

            Nanod_r.dbl2ryl <= Nanod_w.dbl2reg & ~dblSpecial & ~nanoLatch[NANO_RXL_DBL];
            Nanod_r.abl2ryl <= Nanod_w.abl2reg & ~ablSpecial &  nanoLatch[NANO_RXL_DBL];

            Nanod_r.ryl2db  <= Nanod_w.reg2dbl & ~dblSpecial & ~nanoLatch[NANO_RXL_DBL];
            Nanod_r.ryl2ab  <= Nanod_w.reg2abl & ~ablSpecial &  nanoLatch[NANO_RXL_DBL];

            Nanod_r.ryh2dbh <= Nanod_w.reg2dbh & ~dbhSpecial & ~nanoLatch[NANO_RXH_DBH];
            Nanod_r.ryh2abh <= Nanod_w.reg2abh & ~abhSpecial &  nanoLatch[NANO_RXH_DBH];

            // Originally isTas only delayed on T2 (and seems only a late mask rev fix)
            // Better latch the combination on T4
            Nanod_r.isRmc   <= Irdecod.isTas & nanoLatch[NANO_BUSBYTE];
        end
    end

    // Update SSW at the start of Bus/Addr error ucode
    assign Nanod_w.updSsw    = Nanod_r.aob2Ab;

    assign Nanod_w.updTpend  = (ftuCtrl == NANO_FTU_UPDTPEND);
    assign Nanod_w.clrTpend  = (ftuCtrl == NANO_FTU_CLRTPEND);
    assign Nanod_w.tvn2Ftu   = (ftuCtrl == NANO_FTU_TVN);
    assign Nanod_w.const2Ftu = (ftuCtrl == NANO_FTU_CONST);
    assign Nanod_w.ftu2Dbl   = (ftuCtrl == NANO_FTU_DBL) | ( ftuCtrl == NANO_FTU_INL);
    assign Nanod_w.ftu2Abl   = (ftuCtrl == NANO_FTU_2ABL);
    assign Nanod_w.inl2psw   = (ftuCtrl == NANO_FTU_INL);
    assign Nanod_w.pswIToFtu = (ftuCtrl == NANO_FTU_PSWI);
    assign Nanod_w.ftu2Sr    = (ftuCtrl == NANO_FTU_2SR);
    assign Nanod_w.sr2Ftu    = (ftuCtrl == NANO_FTU_RDSR);
    assign Nanod_w.ird2Ftu   = (ftuCtrl == NANO_FTU_IRD);       // Used on bus/addr error
    assign Nanod_w.ssw2Ftu   = (ftuCtrl == NANO_FTU_SSW);
    assign Nanod_w.initST    = (ftuCtrl == NANO_FTU_INL) | (ftuCtrl == NANO_FTU_CLRTPEND) | (ftuCtrl == NANO_FTU_INIT_ST);
    assign Nanod_w.abl2Pren  = (ftuCtrl == NANO_FTU_ABL2PREN);
    assign Nanod_w.updPren   = (ftuCtrl == NANO_FTU_RSTPREN);

    assign Nanod_w.Ir2Ird    = nanoLatch[NANO_IR2IRD];

    // ALU control better latched later after combining with IRD decoding

    wire [1:0] aluFinInit = nanoLatch[NANO_ALU_FI +: 2];

    assign Nanod_w.aluDctrl      = nanoLatch[NANO_ALU_DCTRL +: 2];
    assign Nanod_w.aluActrl      = nanoLatch[NANO_ALU_ACTRL];
    assign Nanod_w.aluColumn     = { nanoLatch[ NANO_ALU_COL], nanoLatch[ NANO_ALU_COL+1], nanoLatch[ NANO_ALU_COL+2]};
    assign Nanod_w.aluFinish     = (aluFinInit == 2'b10) ? 1'b1 : 1'b0;
    assign Nanod_w.aluInit       = (aluFinInit == 2'b01) ? 1'b1 : 1'b0;

    // FTU 2 CCR encoded as both ALU Init and ALU Finish set.
    // In theory this encoding allows writes to CCR without writing to SR
    // But FTU 2 CCR and to SR are both set together at nanorom.
    assign Nanod_w.ftu2Ccr       = (aluFinInit == 2'b11) ? 1'b1 : 1'b0;

    assign Nanod_w.abdIsByte     = nanoLatch[NANO_ABDHRECHARGE];

    // Not being latched on T4 creates non unique case warning!
    assign Nanod_w.au2Db         = (nanoLatch[NANO_AUOUT +: 2] == 2'b01) ? 1'b1 : 1'b0;
    assign Nanod_w.au2Ab         = (nanoLatch[NANO_AUOUT +: 2] == 2'b10) ? 1'b1 : 1'b0;
    assign Nanod_w.au2Pc         = (nanoLatch[NANO_AUOUT +: 2] == 2'b11) ? 1'b1 : 1'b0;

    assign Nanod_w.db2Aob        = (aobCtrl == 2'b10) ? 1'b1 : 1'b0;
    assign Nanod_w.ab2Aob        = (aobCtrl == 2'b01) ? 1'b1 : 1'b0;
    assign Nanod_w.au2Aob        = (aobCtrl == 2'b11) ? 1'b1 : 1'b0;

    assign Nanod_w.dbin2Abd      = nanoLatch[NANO_DBIN2ABD];
    assign Nanod_w.dbin2Dbd      = nanoLatch[NANO_DBIN2DBD];

    assign Nanod_w.permStart     = (aobCtrl != 2'b00) ? 1'b1 : 1'b0;
    assign Nanod_w.isWrite       = nanoLatch[NANO_DOBCTRL_1]
                                 | nanoLatch[NANO_DOBCTRL_0];
    assign Nanod_w.waitBusFinish = nanoLatch[NANO_DOBCTRL_1]
                                 | nanoLatch[NANO_DOBCTRL_0]
                                 | nanoLatch[NANO_TOIRC]
                                 | nanoLatch[NANO_TODBIN];
    assign Nanod_w.busByte       = nanoLatch[NANO_BUSBYTE];

    assign Nanod_w.noLowByte     = nanoLatch[NANO_LOWBYTE];
    assign Nanod_w.noHighByte    = nanoLatch[NANO_HIGHBYTE];

    // Not registered. Register at T4 after combining
    // Might be better to remove all those and combine here instead of at execution unit !!
    assign Nanod_w.abl2reg       = nanoLatch[NANO_ABL2REG];
    assign Nanod_w.abh2reg       = nanoLatch[NANO_ABH2REG];
    assign Nanod_w.dbl2reg       = nanoLatch[NANO_DBL2REG];
    assign Nanod_w.dbh2reg       = nanoLatch[NANO_DBH2REG];
    assign Nanod_w.reg2dbl       = nanoLatch[NANO_REG2DBL];
    assign Nanod_w.reg2dbh       = nanoLatch[NANO_REG2DBH];
    assign Nanod_w.reg2abl       = nanoLatch[NANO_REG2ABL];
    assign Nanod_w.reg2abh       = nanoLatch[NANO_REG2ABH];

    assign Nanod_w.ssp           = nanoLatch[NANO_SSP];

    assign Nanod_w.rz            = nanoLatch[NANO_RZ];

    // Actually DTL can't happen on PC relative mode. See IR decoder.

    wire dtldbd = 1'b0;
    wire dthdbh = 1'b0;
    wire dtlabd = 1'b0;
    wire dthabh = 1'b0;

    wire dblSpecial = Nanod_w.pcldbl | dtldbd;
    wire dbhSpecial = Nanod_w.pchdbh | dthdbh;
    wire ablSpecial = Nanod_w.pclabl | dtlabd;
    wire abhSpecial = Nanod_w.pchabh | dthabh;

    //
    // Combine with IRD decoding
    // Careful that IRD is updated only on T1! All output depending on IRD must be latched on T4!
    //

    // PC used instead of RY on PC relative instuctions

    assign Nanod_w.rxlDbl = nanoLatch[NANO_RXL_DBL];
    wire isPcRel  = Irdecod.isPcRel & ~nanoLatch[NANO_RZ];
    wire pcRelDbl = isPcRel & ~nanoLatch[NANO_RXL_DBL];
    wire pcRelDbh = isPcRel & ~nanoLatch[NANO_RXH_DBH];
    wire pcRelAbl = isPcRel &  nanoLatch[NANO_RXL_DBL];
    wire pcRelAbh = isPcRel &  nanoLatch[NANO_RXH_DBH];

    assign Nanod_w.pcldbl = nanoLatch[NANO_PCLDBL] | pcRelDbl;
    assign Nanod_w.pchdbh = (nanoLatch[NANO_PCH +: 2] == 2'b01) ? 1'b1 : pcRelDbh;

    assign Nanod_w.pclabl = nanoLatch[NANO_PCLABL] | pcRelAbl;
    assign Nanod_w.pchabh = (nanoLatch[NANO_PCH +: 2] == 2'b10) ? 1'b1 : pcRelAbh;

endmodule

//
// IRD execution decoder. Complements nano code decoder
//
// IRD updated on T1, while ncode still executing. To avoid using the next IRD,
// decoded signals must be registered on T3, or T4 before using them.
//
module irdDecode
(
    input [15:0] ird,
    output s_irdecod Irdecod
);

    wire [3:0] line = ird[15:12];
    logic [15:0] lineOnehot;

    // This can be registered and pipelined from the IR decoder !
    onehotEncoder4 irdLines( line, lineOnehot);

    reg  implicitSp;
    
    wire isRegShift = (lineOnehot[4'hE]) & (ird[7:6] != 2'b11);
    wire isDynShift = isRegShift & ird[5];
    wire isTas      = (ird[11:6] == 6'b101011) ? lineOnehot[4'h4] : 1'b0;

    assign Irdecod.isPcRel = (& ird[ 5:3]) & ~isDynShift & !ird[2] & ird[1];
    assign Irdecod.isTas   = isTas;

    assign Irdecod.rx = ird[11:9];
    assign Irdecod.ry = ird[ 2:0];

    wire isPreDecr = (ird[5:3] == 3'b100) ? 1'b1 : 1'b0;
    wire eaAreg    = (ird[5:3] == 3'b001) ? 1'b1 : 1'b0;

    // rx is A or D
    // movem
    always_comb begin
        unique case (1'b1)
            lineOnehot[4'h1],
            lineOnehot[4'h2],
            lineOnehot[4'h3]:
                // MOVE: RX always Areg except if dest mode is Dn 000
                Irdecod.rxIsAreg = (|ird[8:6]);

            lineOnehot[4'h4]:
                // not CHK (LEA)
                Irdecod.rxIsAreg = (&ird[8:6]);

            lineOnehot[4'h8]:
                // SBCD
                Irdecod.rxIsAreg = eaAreg & ird[8] & ~ird[7];
                
            lineOnehot[4'hC]:
                // ABCD/EXG An,An
                Irdecod.rxIsAreg = eaAreg & ird[8] & ~ird[7];

            lineOnehot[4'h9],
            lineOnehot[4'hB],
            lineOnehot[4'hD]:
                Irdecod.rxIsAreg =
                    (ird[7] & ird[6]) |                      // SUBA/CMPA/ADDA
                    (eaAreg & ird[8] & (ird[7:6] != 2'b11)); // SUBX/CMPM/ADDX
            default:
                Irdecod.rxIsAreg = implicitSp;
        endcase
    end

    // RX is movem
    assign Irdecod.rxIsMovem    = lineOnehot[4'h4] & ~ird[8] & ~implicitSp;
    assign Irdecod.movemPreDecr = lineOnehot[4'h4] & ~ird[8] & ~implicitSp & isPreDecr;

    // RX is DT.
    // but SSP explicit or pc explicit has higher priority!
    // addq/subq (scc & dbcc also, but don't use rx)
    // Immediate including static bit
    assign Irdecod.rxIsDt = lineOnehot[4'h5] | (lineOnehot[4'h0] & ~ird[8]);

    // RX is USP
    assign Irdecod.rxIsUsp = lineOnehot[4'h4] & (ird[11:4] == 8'hE6);

    // RY is DT
    // rz or PC explicit has higher priority

    wire eaImmOrAbs = (ird[5:3] == 3'b111) & ~ird[1];
    assign Irdecod.ryIsDt = eaImmOrAbs & ~isRegShift;

    // RY is Address register
    always_comb begin
        logic eaIsAreg;

        // On most cases RY is Areg expect if mode is 000 (DATA REG) or 111 (IMM, ABS,PC REL)
        eaIsAreg = (ird[5:3] != 3'b000) & (ird[5:3] != 3'b111);

        unique case (1'b1)
            // MOVE: RY always Areg expect if mode is 000 (DATA REG) or 111 (IMM, ABS,PC REL)
            // Most lines, including misc line 4, also.
            default:
                Irdecod.ryIsAreg = eaIsAreg;

            lineOnehot[4'h5]:
                // DBcc is an exception
                Irdecod.ryIsAreg = eaIsAreg & (ird[7:3] != 5'b11001);

            lineOnehot[4'h6],
            lineOnehot[4'h7]:
                Irdecod.ryIsAreg = 1'b0;

            lineOnehot[4'hE]:
                Irdecod.ryIsAreg = ~isRegShift;
        endcase
    end

    // Byte sized instruction

    // Original implementation sets this for some instructions that aren't really byte size
    // but doesn't matter because they don't have a byte transfer enabled at nanocode, such as MOVEQ

    wire xIsScc = (ird[7:6] == 2'b11) & (ird[5:3] != 3'b001);
    wire xStaticMem = (ird[11:8] == 4'b1000) & (ird[5:4] == 2'b00);     // Static bit to mem
    always_comb begin
        unique case (1'b1)
            lineOnehot[4'h0]:
                Irdecod.isByte =
                ( ird[8] & (ird[5:4] != 2'b00)                  ) | // Dynamic bit to mem
                ( (ird[11:8] == 4'b1000) & (ird[5:4] != 2'b00)  ) | // Static bit to mem
                ( (ird[8:7] == 2'b10) & (ird[5:3] == 3'b001)    ) | // Movep from mem only! For byte mux
                ( (ird[8:6] == 3'b000) & !xStaticMem );             // Immediate byte

            lineOnehot[4'h1]:
                Irdecod.isByte = 1'b1;      // MOVE.B


            lineOnehot[4'h4]:
                Irdecod.isByte = (ird[7:6] == 2'b00) | isTas;

            lineOnehot[4'h5]:
                Irdecod.isByte = (ird[7:6] == 2'b00) | xIsScc;

            lineOnehot[4'h8],
            lineOnehot[4'h9],
            lineOnehot[4'hB],
            lineOnehot[4'hC],
            lineOnehot[4'hD],
            lineOnehot[4'hE]:
                Irdecod.isByte = (ird[7:6] == 2'b00);

            default:
                Irdecod.isByte = 1'b0;
        endcase
    end

    // Need it for special byte size. Bus is byte, but whole register word is modified.
    assign Irdecod.isMovep = lineOnehot[4'h0] & ird[8] & eaAreg;


    // rxIsSP implicit use of RX for actual SP transfer
    //
    // This logic is simple and will include some instructions that don't actually reference SP.
    // But doesn't matter as long as they don't perform any RX transfer.

    always_comb begin
        unique case (1'b1)
            lineOnehot[6]:
                // BSR
                implicitSp = (ird[11:8] == 4'b0001);
            lineOnehot[4]:
                // Misc like RTS, JSR, etc
                implicitSp = (ird[11:8] == 4'b1110) | (ird[11:6] == 6'b1000_01);
            default:
                implicitSp = 1'b0;
        endcase
    end
    assign Irdecod.implicitSp = implicitSp;

    // Modify CCR (and not SR)
    // Probably overkill !! Only needs to distinguish SR vs CCR
    // RTR, MOVE to CCR, xxxI to CCR
    assign Irdecod.toCcr =  ( lineOnehot[4] & ((ird[11:0] == 12'he77) | (ird[11:6] == 6'b010011)) ) |
                            ( lineOnehot[0] & (ird[8:6] == 3'b000));

    // FTU constants
    // This should not be latched on T3/T4. Latch on T2 or not at all. FTU needs it on next T3.
    // Note: Reset instruction gets constant from ALU not from FTU!
    logic [15:0] ftuConst;
    wire [3:0] zero28 = (ird[11:9] == 0) ? 4'h8 : { 1'b0, ird[11:9]};       // xltate 0,1-7 into 8,1-7

    always_comb begin
        unique case (1'b1)
            lineOnehot[4'h6], // Bcc short
            lineOnehot[4'h7]: // MOVEQ
                ftuConst = { {8{ird[7]}}, ird[7:0] };

            // ADDQ/SUBQ/static shift double check this
            lineOnehot[4'h5],
            lineOnehot[4'hE]:
                ftuConst = { 12'h000, zero28};

            // MULU/MULS DIVU/DIVS
            lineOnehot[4'h8],
            lineOnehot[4'hC]:
                ftuConst = 16'h000F;

            lineOnehot[4'h4]: // TAS
                ftuConst = 16'h0080;

            default:
                ftuConst = 16'h0000;
        endcase
    end
    assign Irdecod.ftuConst = ftuConst;

    //
    // TRAP Vector # for group 2 exceptions
    //

    always_comb begin
        if (lineOnehot[4'h4]) begin
            case (ird[6:5])
                2'b00,
                2'b01:
                    Irdecod.macroTvn = 6'h6;                // CHK
                2'b11:
                    Irdecod.macroTvn = 6'h7;                // TRAPV
                2'b10:
                    Irdecod.macroTvn = { 2'b10, ird[3:0] }; // TRAP
            endcase
        end
        else begin
            Irdecod.macroTvn = 6'h5; // Division by zero
        end
    end


    wire eaAdir = (ird[ 5:3] == 3'b001);
    wire size11 = ird[7] & ird[6];

    // Opcodes variants that don't affect flags
    // ADDA/SUBA ADDQ/SUBQ MOVEA

    assign Irdecod.inhibitCcr =
        ( (lineOnehot[9] | lineOnehot['hd]) & size11) |             // ADDA/SUBA
        ( lineOnehot[5] & eaAdir) |                                 // ADDQ/SUBQ to An (originally checks for line[4] as well !?)
        ( (lineOnehot[2] | lineOnehot[3]) & ird[8:6] == 3'b001);    // MOVEA

endmodule

/*
 Execution unit

 Executes register transfers set by the microcode. Originally through a set of bidirectional buses.
 Most sources are available at T3, but DBIN only at T4! CCR also might be updated at T4, but it is not connected to these buses.
 We mux at T1 and T2, then transfer to the destination at T3. The exception is AOB that need to be updated earlier.

*/

module excUnit
(
    input clk,
    input s_clks Clks,
    input enT1, enT2, enT3, enT4,
    input s_nanod_r Nanod_r,
    input s_nanod_w Nanod_w,
    input s_irdecod Irdecod,
    input [15:0] Ird,           // ALU row (and others) decoder needs it
    input pswS,
    input [15:0] ftu,
    input [15:0] iEdb,

    output logic [7:0] ccr,
    output [15:0] alue,

    output prenEmpty, au05z,
    output logic dcr4, ze,
    output logic aob0,
    output [15:0] AblOut,
    output logic [15:0] Irc,
    output logic [15:0] oEdb,
    output logic [31:1] eab
);

localparam
    REG_USP = 15,
    REG_SSP = 16,
    REG_DT  = 17;

    // Register file
    reg [15:0] regs68L[0:17];
    reg [15:0] regs68H[0:17];

`ifdef verilator3

    /*
        It is bad practice to initialize simulation registers that the hardware doesn't.
        There is risk that simulation would be different than the real hardware. But in this case is the other way around.
        Some ROM uses something like sub.l An,An at powerup which clears the register
        Simulator power ups the registers with 'X, as they are really undetermined at the real hardware.
        But the simulator doesn't realize (it can't) that the same value is substracting from itself,
        and that the result should be zero even when it's 'X - 'X.
    */

    initial begin
        for( int i = 0; i < 18; i++) begin
            regs68L[i] = 16'h0000;
            regs68H[i] = 16'h0000;
        end
    end

    // For simulation display only
    wire [31:0] SSP = { regs68H[REG_SSP], regs68L[REG_SSP]};

`endif


    wire [15:0] aluOut;
    wire [15:0] dbin;
    logic [15:0] dcrOutput;

    reg [15:0] PcL, PcH;

    reg [31:0] auReg, aob;

    reg [15:0] Ath, Atl;

    // Bus execution
    reg [15:0] Dbl, Dbh;
    reg [15:0] Abh, Abl;
    reg [15:0] Abd, Dbd;

    assign AblOut = Abl;
    assign au05z = (~| auReg[5:0]);

    logic [15:0] dblMux, dbhMux;
    logic [15:0] abhMux, ablMux;
    logic [15:0] abdMux, dbdMux;

    logic abdIsByte;

    logic Pcl2Dbl, Pch2Dbh;
    logic Pcl2Abl, Pch2Abh;


    // RX RY muxes
    // RX and RY actual registers
    logic [4:0] actualRx, actualRy;
    logic [3:0] movemRx;
    logic byteNotSpAlign;           // Byte instruction and no sp word align

    // IRD decoded signals must be latched. See comments on decoder
    // But nanostore decoding can't be latched before T4.
    //
    // If we need this earlier we can register IRD decode on T3 and use nano async

    logic [4:0] rxMux, ryMux;
    logic [3:0] rxReg, ryReg;
    logic rxIsSp, ryIsSp;
    logic rxIsAreg, ryIsAreg;

    always_comb begin

        // Unique IF !!
        if (Nanod_w.ssp) begin
            rxMux  = REG_SSP[4:0];
            rxIsSp = 1'b1;
            rxReg  = 4'hX;
        end
        else if (Irdecod.rxIsUsp) begin
            rxMux  = REG_USP[4:0];
            rxIsSp = 1'b1;
            rxReg  = 4'hX;
        end
        else if (Irdecod.rxIsDt & !Irdecod.implicitSp) begin
            rxMux  = REG_DT[4:0];
            rxIsSp = 1'b0;
            rxReg  = 4'hX;
        end
        else begin
            if (Irdecod.implicitSp)
                rxReg = REG_USP[3:0];
            else if (Irdecod.rxIsMovem)
                rxReg = movemRx;
            else
                rxReg = { Irdecod.rxIsAreg, Irdecod.rx};

            if (&rxReg) begin
                rxMux  = pswS ? REG_SSP[4:0] : REG_USP[4:0];
                rxIsSp = 1'b1;
            end
            else begin
                rxMux  = { 1'b0, rxReg};
                rxIsSp = 1'b0;
            end
        end

        // RZ has higher priority!
        if (Irdecod.ryIsDt & !Nanod_w.rz) begin
            ryMux  = REG_DT[4:0];
            ryIsSp = 1'b0;
            ryReg  = 4'hX;
        end
        else begin
            ryReg = Nanod_w.rz ? Irc[15:12] : {Irdecod.ryIsAreg, Irdecod.ry};
            ryIsSp = (& ryReg);
            if (ryIsSp & pswS)          // No implicit SP on RY
                ryMux = REG_SSP[4:0];
            else
                ryMux = { 1'b0, ryReg};
        end

    end

    always_ff @(posedge clk) begin
    
        if (enT4) begin
            byteNotSpAlign <= Irdecod.isByte & ~(Nanod_w.rxlDbl ? rxIsSp : ryIsSp);

            actualRx <= rxMux;
            actualRy <= ryMux;

            rxIsAreg <= rxIsSp | rxMux[3];
            ryIsAreg <= ryIsSp | ryMux[3];

            abdIsByte <= Nanod_w.abdIsByte & Irdecod.isByte;
        end
    end

    // Set RX/RY low word to which bus segment is connected.

    wire ryl2Abl = Nanod_r.ryl2ab & ( ryIsAreg | Nanod_r.ablAbd);
    wire ryl2Abd = Nanod_r.ryl2ab & (~ryIsAreg | Nanod_r.ablAbd);
    wire ryl2Dbl = Nanod_r.ryl2db & ( ryIsAreg | Nanod_r.dblDbd);
    wire ryl2Dbd = Nanod_r.ryl2db & (~ryIsAreg | Nanod_r.dblDbd);

    wire rxl2Abl = Nanod_r.rxl2ab & ( rxIsAreg | Nanod_r.ablAbd);
    wire rxl2Abd = Nanod_r.rxl2ab & (~rxIsAreg | Nanod_r.ablAbd);
    wire rxl2Dbl = Nanod_r.rxl2db & ( rxIsAreg | Nanod_r.dblDbd);
    wire rxl2Dbd = Nanod_r.rxl2db & (~rxIsAreg | Nanod_r.dblDbd);

    // Buses. Main mux

    logic abhIdle, ablIdle, abdIdle;
    logic dbhIdle, dblIdle, dbdIdle;

    always_comb begin
        {abhIdle, ablIdle, abdIdle} = 3'b000;
        {dbhIdle, dblIdle, dbdIdle} = 3'b000;

        unique case (1'b1)
        ryl2Dbd:                dbdMux = regs68L[actualRy];
        rxl2Dbd:                dbdMux = regs68L[actualRx];
        Nanod_r.alue2Dbd:       dbdMux = alue;
        Nanod_w.dbin2Dbd:       dbdMux = dbin;
        Nanod_r.alu2Dbd:        dbdMux = aluOut;
        Nanod_r.dcr2Dbd:        dbdMux = dcrOutput;
        default: begin          dbdMux = 'X;    dbdIdle = 1'b1;             end
        endcase

        unique case (1'b1)
        rxl2Dbl:                dblMux = regs68L[actualRx];
        ryl2Dbl:                dblMux = regs68L[actualRy];
        Nanod_w.ftu2Dbl:        dblMux = ftu;
        Nanod_w.au2Db:          dblMux = auReg[15:0];
        Nanod_r.atl2Dbl:        dblMux = Atl;
        Pcl2Dbl:                dblMux = PcL;
        default: begin          dblMux = 'X;    dblIdle = 1'b1;             end
        endcase

        unique case (1'b1)
        Nanod_r.rxh2dbh:        dbhMux = regs68H[actualRx];
        Nanod_r.ryh2dbh:        dbhMux = regs68H[actualRy];
        Nanod_w.au2Db:          dbhMux = auReg[31:16];
        Nanod_r.ath2Dbh:        dbhMux = Ath;
        Pch2Dbh:                dbhMux = PcH;
        default: begin          dbhMux = 'X;    dbhIdle = 1'b1;             end
        endcase

        unique case (1'b1)
        ryl2Abd:                abdMux = regs68L[actualRy];
        rxl2Abd:                abdMux = regs68L[actualRx];
        Nanod_w.dbin2Abd:       abdMux = dbin;
        Nanod_r.alu2Abd:        abdMux = aluOut;
        default: begin          abdMux = 'X;    abdIdle = 1'b1;             end
        endcase

        unique case (1'b1)
        Pcl2Abl:                ablMux = PcL;
        rxl2Abl:                ablMux = regs68L[actualRx];
        ryl2Abl:                ablMux = regs68L[actualRy];
        Nanod_w.ftu2Abl:        ablMux = ftu;
        Nanod_w.au2Ab:          ablMux = auReg[15:0];
        Nanod_r.aob2Ab:         ablMux = aob[15:0];
        Nanod_r.atl2Abl:        ablMux = Atl;
        default: begin          ablMux = 'X;    ablIdle = 1'b1;             end
        endcase

        unique case (1'b1)
        Pch2Abh:                abhMux = PcH;
        Nanod_r.rxh2abh:        abhMux = regs68H[actualRx];
        Nanod_r.ryh2abh:        abhMux = regs68H[actualRy];
        Nanod_w.au2Ab:          abhMux = auReg[31:16];
        Nanod_r.aob2Ab:         abhMux = aob[31:16];
        Nanod_r.ath2Abh:        abhMux = Ath;
        default: begin          abhMux = 'X;    abhIdle = 1'b1;             end
        endcase

    end

    // Source starts driving the bus on T1. Bus holds data until end of T3. Destination latches at T3.

    // These registers store the first level mux, without bus interconnections.
    // Even when this uses almost to 100 registers, it saves a lot of comb muxing and it is much faster.
    reg [15:0] preAbh, preAbl, preAbd;
    reg [15:0] preDbh, preDbl, preDbd;

    always_ff @(posedge clk) begin

        // Register first level mux at T1
        if (enT1) begin
            {preAbh, preAbl, preAbd} <= { abhMux, ablMux, abdMux};
            {preDbh, preDbl, preDbd} <= { dbhMux, dblMux, dbdMux};
        end

        // Process bus interconnection at T2. Many combinations only used on DIV
        // We use a simple method. If a specific bus segment is not driven we know that it should get data from a neighbour segment.
        // In some cases this is not true and the segment is really idle without any destination. But then it doesn't matter.

        if (enT2) begin
            if (Nanod_r.extAbh)
                Abh <= { 16{ ablIdle ? preAbd[15] : preAbl[15] }};
            else if (abhIdle)
                Abh <= ablIdle ? preAbd : preAbl;
            else
                Abh <= preAbh;

            if (~ablIdle)
                Abl <= preAbl;
            else
                Abl <= Nanod_r.ablAbh ? preAbh : preAbd;

            Abd <= ~abdIdle ? preAbd : ablIdle ? preAbh : preAbl;

            if (Nanod_r.extDbh)
                Dbh <= { 16{ dblIdle ? preDbd[15] : preDbl[15] }};
            else if (dbhIdle)
                Dbh <= dblIdle ? preDbd : preDbl;
            else
                Dbh <= preDbh;

            if (~dblIdle)
                Dbl <= preDbl;
            else
                Dbl <= Nanod_r.dblDbh ? preDbh : preDbd;

            Dbd <= ~dbdIdle ? preDbd: dblIdle ? preDbh : preDbl;

            /*
            Dbl <= dblMux;
            Dbh <= dbhMux;
            Abd <= abdMux;
            Dbd <= dbdMux;
            Abh <= abhMux;
            Abl <= ablMux;
            */
        end
    end

    // AOB
    //
    // Originally change on T1. We do on T2, only then the output is enabled anyway.
    //
    // AOB[0] is used for address error. But even when raises on T1, seems not actually used until T2 or possibly T3.
    // It is used on T1 when deasserted at the BSER exception ucode. Probably deassertion timing is not critical.
    // But in that case (at BSER), AOB is loaded from AU, so we can safely transfer on T1.

    // We need to take directly from first level muxes that are updated and T1

    wire au2Aob = Nanod_w.au2Aob | (Nanod_w.au2Db & Nanod_w.db2Aob);

    always_ff @(posedge clk) begin
        // UNIQUE IF !

        if (enT1 & au2Aob)      // From AU we do can on T1
            aob <= auReg;
        else if (enT2) begin
            if (Nanod_w.db2Aob)
                aob <= { preDbh, ~dblIdle ? preDbl : preDbd};
            else if (Nanod_w.ab2Aob)
                aob <= { preAbh, ~ablIdle ? preAbl : preAbd};
        end
    end

    assign eab  = aob[31:1];
    assign aob0 = aob[0];

    // AU
    logic [31:0] auInpMux;

    // `ifdef ALW_COMB_BUG
    // Old Modelsim bug. Doesn't update ouput always. Need excplicit sensitivity list !?
    // always @( Nanod_r.auCntrl) begin

    always_comb begin
        unique case (Nanod_r.auCntrl)
            3'b000:  auInpMux = 32'h00000000;
            3'b001:  auInpMux = byteNotSpAlign | Nanod_r.noSpAlign ? 32'h00000001 : 32'h00000002; // +1/+2
            3'b010:  auInpMux = 32'hFFFFFFFC;
            3'b011:  auInpMux = { Abh, Abl};
            3'b100:  auInpMux = 32'h00000002;
            3'b101:  auInpMux = 32'h00000004;
            3'b110:  auInpMux = 32'hFFFFFFFE;
            3'b111:  auInpMux = byteNotSpAlign | Nanod_r.noSpAlign ? 32'hFFFFFFFF : 32'hFFFFFFFE; // -1/-2
            default: auInpMux = 32'h00000000;
        endcase
    end

    // Simulation problem
    // Sometimes (like in MULM1) DBH is not set. AU is used in these cases just as a 6 bits counter testing if bits 5-0 are zero.
    // But when adding something like 32'hXXXX0000, the simulator (incorrectly) will set *all the 32 bits* of the result as X.

// synthesis translate_off
    `define SIMULBUGX32 1
    wire [16:0] aulow = Dbl + auInpMux[15:0];
    wire [31:0] auResult = {Dbh + auInpMux[31:16] + {15'b0, aulow[16]}, aulow[15:0]};
// synthesis translate_on

    always_ff @(posedge clk) begin

        if (Clks.pwrUp)
            auReg <= '0;
        else if (enT3 & Nanod_r.auClkEn)
            `ifdef SIMULBUGX32
                auReg <= auResult;
            `else
                auReg <= { Dbh, Dbl } + auInpMux;
            `endif
    end


    // Main A/D registers

    always_ff @(posedge clk) begin

        if (enT3) begin
            if (Nanod_r.dbl2rxl | Nanod_r.abl2rxl) begin
                if (~rxIsAreg) begin
                    if (Nanod_r.dbl2rxl)        regs68L[actualRx] <= Dbd;
                    else if (abdIsByte)         regs68L[actualRx][7:0] <= Abd[7:0];
                    else                        regs68L[actualRx] <= Abd;
                end
                else
                    regs68L[actualRx] <= Nanod_r.dbl2rxl ? Dbl : Abl;
            end

            if (Nanod_r.dbl2ryl | Nanod_r.abl2ryl) begin
                if (~ryIsAreg) begin
                    if (Nanod_r.dbl2ryl)        regs68L[actualRy] <= Dbd;
                    else if (abdIsByte)         regs68L[actualRy][7:0] <= Abd[7:0];
                    else                        regs68L[actualRy] <= Abd;
                end
                else
                    regs68L[actualRy] <= Nanod_r.dbl2ryl ? Dbl : Abl;
            end

            // High registers are easier. Both A & D on the same buses, and not byte ops.
            if (Nanod_r.dbh2rxh | Nanod_r.abh2rxh)
                regs68H[actualRx] <= Nanod_r.dbh2rxh ? Dbh : Abh;
            if (Nanod_r.dbh2ryh | Nanod_r.abh2ryh)
                regs68H[actualRy] <= Nanod_r.dbh2ryh ? Dbh : Abh;

        end
    end

    // PC & AT
    reg dbl2Pcl, dbh2Pch, abh2Pch, abl2Pcl;

    always_ff @(posedge clk) begin
    
        if (Clks.extReset) begin
            { dbl2Pcl, dbh2Pch, abh2Pch, abl2Pcl } <= '0;

            Pcl2Dbl <= 1'b0;
            Pch2Dbh <= 1'b0;
            Pcl2Abl <= 1'b0;
            Pch2Abh <= 1'b0;
        end
        else if (enT4) begin                // Must latch on T4 !
            dbl2Pcl <= Nanod_w.dbl2reg & Nanod_w.pcldbl;
            dbh2Pch <= Nanod_w.dbh2reg & Nanod_w.pchdbh;
            abh2Pch <= Nanod_w.abh2reg & Nanod_w.pchabh;
            abl2Pcl <= Nanod_w.abl2reg & Nanod_w.pclabl;

            Pcl2Dbl <= Nanod_w.reg2dbl & Nanod_w.pcldbl;
            Pch2Dbh <= Nanod_w.reg2dbh & Nanod_w.pchdbh;
            Pcl2Abl <= Nanod_w.reg2abl & Nanod_w.pclabl;
            Pch2Abh <= Nanod_w.reg2abh & Nanod_w.pchabh;
        end

        // Unique IF !!!
        if (enT1 & Nanod_w.au2Pc)
            PcL <= auReg[15:0];
        else if (enT3) begin
            if (dbl2Pcl)
                PcL <= Dbl;
            else if (abl2Pcl)
                PcL <= Abl;
        end

        // Unique IF !!!
        if (enT1 & Nanod_w.au2Pc)
            PcH <= auReg[31:16];
        else if (enT3) begin
            if (dbh2Pch)
                PcH <= Dbh;
            else if (abh2Pch)
                PcH <= Abh;
        end

        // Unique IF !!!
        if (enT3) begin
            if (Nanod_r.dbl2Atl)
                Atl <= Dbl;
            else if (Nanod_r.abl2Atl)
                Atl <= Abl;
        end

        // Unique IF !!!
        if (enT3) begin
            if (Nanod_r.abh2Ath)
                Ath <= Abh;
            else if (Nanod_r.dbh2Ath)
                Ath <= Dbh;
        end

    end

    // Movem reg mask priority encoder

    wire         rmIdle;
    logic  [3:0] prHbit;
    logic [15:0] prenLatch;

    // Invert reg order for predecrement mode
    assign prenEmpty = (~| prenLatch);
    pren rmPren( .mask( prenLatch), .hbit (prHbit));

    always_ff @(posedge clk) begin
    
        // Cheating: PREN always loaded from DBIN
        // Must be on T1 to branch earlier if reg mask is empty!
        if (enT1 & Nanod_w.abl2Pren)
            prenLatch <= dbin;
        else if (enT3 & Nanod_w.updPren) begin
            prenLatch [prHbit] <= 1'b0;
            movemRx <= Irdecod.movemPreDecr ? ~prHbit : prHbit;
        end
    end

    // DCR
    wire [15:0] dcrCode;

    wire [3:0] dcrInput = abdIsByte ? { 1'b0, Abd[ 2:0]} : Abd[ 3:0];
    onehotEncoder4 dcrDecoder( .bin( dcrInput), .bitMap( dcrCode));

    always_ff @(posedge clk) begin

        if (Clks.pwrUp)
            dcr4 <= '0;
        else if (enT3 & Nanod_r.abd2Dcr) begin
            dcrOutput <= dcrCode;
            dcr4 <= Abd[4];
        end
    end

    // ALUB
    reg [15:0] alub;

    always_ff @(posedge clk) begin

        if (enT3) begin
            // UNIQUE IF !!
            if (Nanod_r.dbd2Alub)
                alub <= Dbd;
            else if (Nanod_r.abd2Alub)
                alub <= Abd;                // abdIsByte affects this !!??
        end
    end

    wire alueClkEn = enT3 & Nanod_r.dbd2Alue;

    // DOB/DBIN/IRC

    logic [15:0] dobInput;
    wire dobIdle = (~| Nanod_r.dobCtrl);

    always_comb begin
        unique case (Nanod_r.dobCtrl)
        NANO_DOB_ADB:       dobInput = Abd;
        NANO_DOB_DBD:       dobInput = Dbd;
        NANO_DOB_ALU:       dobInput = aluOut;
        default:            dobInput = 'X;
        endcase
    end

    dataIo U_dataIo
    (
        .clk, .Clks, .enT1, .enT2, .enT3, .enT4,
        .Nanod_r, .Nanod_w, .Irdecod,
        .iEdb, .dobIdle, .dobInput, .aob0,
        .Irc, .dbin, .oEdb
    );

    fx68kAlu U_fx68kAlu
    (
        .clk, .pwrUp( Clks.pwrUp), .enT1, .enT3, .enT4,
        .ird         (Ird),
        .aluColumn   (Nanod_w.aluColumn),
        .aluDataCtrl (Nanod_w.aluDctrl),
        .aluAddrCtrl (Nanod_w.aluActrl),
        .ftu2Ccr     (Nanod_w.ftu2Ccr),
        .init        (Nanod_w.aluInit),
        .finish      (Nanod_w.aluFinish),
        .aluIsByte   (Irdecod.isByte),
        .alub, .ftu, .alueClkEn, .alue,
        .iDataBus( Dbd), .iAddrBus(Abd),
        .ze, .aluOut, .ccr
    );

endmodule

//
// Data bus I/O
// At a separate module because it is a bit complicated and the timing is special.
// Here we do the low/high byte mux and the special case of MOVEP.
//
// Original implementation is rather complex because both the internal and external buses are bidirectional.
// Input is latched async at the EDB register.
// We capture directly from the external data bus to the internal registers (IRC & DBIN) on PHI2, starting the external S7 phase, at a T4 internal period.

module dataIo
(
    input               clk,
    input        s_clks Clks,
    input               enT1,
    input               enT2,
    input               enT3,
    input               enT4,
    input     s_nanod_r Nanod_r,
    input     s_nanod_w Nanod_w,
    input     s_irdecod Irdecod,
    input        [15:0] iEdb,
    input               aob0,

    input               dobIdle,
    input        [15:0] dobInput,

    output logic [15:0] Irc,
    output logic [15:0] dbin,
    output logic [15:0] oEdb
);

    reg [15:0] dob;

    // DBIN/IRC

    // Timing is different than any other register. We can latch only on the next T4 (bus phase S7).
    // We need to register all control signals correctly because the next ublock will already be started.
    // Can't latch control on T4 because if there are wait states there might be multiple T4 before we latch.

    reg xToDbin, xToIrc;
    reg dbinNoLow, dbinNoHigh;
    reg byteMux, isByte_T4;

    always_ff @(posedge clk) begin

        // Byte mux control. Can't latch at T1. AOB might be not ready yet.
        // Must latch IRD decode at T1 (or T4). Then combine and latch only at T3.

        // Can't latch at T3, a new IRD might be loaded already at T1.
        // Ok to latch at T4 if combination latched then at T3
        if (enT4)
            isByte_T4 <= Irdecod.isByte;    // Includes MOVEP from mem, we could OR it here

        if (enT3) begin
            dbinNoHigh <= Nanod_w.noHighByte;
            dbinNoLow  <= Nanod_w.noLowByte;
            byteMux    <= Nanod_w.busByte & isByte_T4 & ~aob0;
        end

        if (enT1) begin
            // If on wait states, we continue latching until next T1
            xToDbin <= 1'b0;
            xToIrc  <= 1'b0;
        end
        else if (enT3) begin
            xToDbin <= Nanod_r.todbin;
            xToIrc  <= Nanod_r.toIrc;
        end

        // Capture on T4 of the next ucycle
        // If there are wait states, we keep capturing every PHI2 until the next T1

        if (xToIrc & Clks.enPhi2)
            Irc <= iEdb;
        if (xToDbin & Clks.enPhi2) begin
            // Original connects both halves of EDB.
            if (~dbinNoLow)
                dbin[ 7:0] <= byteMux ? iEdb[ 15:8] : iEdb[7:0];
            if (~dbinNoHigh)
                dbin[ 15:8] <= ~byteMux & dbinNoLow ? iEdb[ 7:0] : iEdb[ 15:8];
        end
    end

    // DOB
    logic byteCycle;

    always_ff @(posedge clk) begin
        // Originaly on T1. Transfer to internal EDB also on T1 (stays enabled upto the next T1). But only on T4 (S3) output enables.
        // It is safe to do on T3, then, but control signals if derived from IRD must be registered.
        // Originally control signals are not registered.

        // Wait states don't affect DOB operation that is done at the start of the bus cycle.

        if (enT4)
            byteCycle <= Nanod_w.busByte & Irdecod.isByte;        // busIsByte but not MOVEP

        // Originally byte low/high interconnect is done at EDB, not at DOB.
        if (enT3 & ~dobIdle) begin
            dob[7:0] <= Nanod_w.noLowByte ? dobInput[15:8] : dobInput[ 7:0];
            dob[15:8] <= (byteCycle | Nanod_w.noHighByte) ? dobInput[ 7:0] : dobInput[15:8];
        end
    end
    assign oEdb = dob;

endmodule


// Provides ucode routine entries (A1/A3) for each opcode
// Also checks for illegal opcode and priv violation

// This is one of the slowest part of the processor.
// But no need to optimize or pipeline because the result is not needed until at least 4 cycles.
// IR updated at the least one microinstruction earlier.
// Just need to configure the timing analizer correctly.

module uaddrDecode
(
    input             [15:0] opcode,
    output [UADDR_WIDTH-1:0] a1,
    output [UADDR_WIDTH-1:0] a2,
    output [UADDR_WIDTH-1:0] a3,
    output logic             isPriv,
    output logic             isIllegal,
    output logic             isLineA,
    output logic             isLineF,
    output            [15:0] lineBmap
);

    wire [3:0] line = opcode[15:12];
    logic [3:0] eaCol, movEa;

    onehotEncoder4 irLineDecod( line, lineBmap);

    assign isLineA = lineBmap[ 'hA];
    assign isLineF = lineBmap[ 'hF];

    uaddrPla U_uaddrPla
    (
        .movEa    (movEa),
        .col      (eaCol),
        .opcode   (opcode),
        .lineBmap (lineBmap),
        .palIll   (isIllegal),
        .plaA1    (a1),
        .plaA2    (a2),
        .plaA3    (a3)
    );

    // ea decoding
    assign eaCol = eaDecode( opcode[ 5:0]);
    assign movEa = eaDecode( {opcode[ 8:6], opcode[ 11:9]} );

    /*
    Privileged instructions:

    ANDI/EORI/ORI SR
    MOVE to SR
    MOVE to/from USP
    RESET
    STOP
    RTE
    */

    always_comb begin
        unique case (lineBmap)

        // ori/andi/eori SR
        'h01:   isPriv = ((opcode & 16'hf5ff) == 16'h007c);

        'h10:
            begin
            // No priority !!!
                if ((opcode & 16'hffc0) == 16'h46c0)        // move to sr
                    isPriv = 1'b1;

                else if ((opcode & 16'hfff0) == 16'h4e60)   // move usp
                    isPriv = 1'b1;

                else if (   opcode == 16'h4e70 ||           // reset
                            opcode == 16'h4e73 ||           // rte
                            opcode == 16'h4e72)             // stop
                    isPriv = 1'b1;
                else
                    isPriv = 1'b0;
            end

        default:   isPriv = 1'b0;
        endcase
    end


endmodule

// bin to one-hot, 4 bits to 16-bit bitmap
module onehotEncoder4
(
    input       [3:0] bin,
    output reg [15:0] bitMap
);

    always_comb begin
        case (bin)
            4'h0:   bitMap = 16'b0000000000000001;
            4'h1:   bitMap = 16'b0000000000000010;
            4'h2:   bitMap = 16'b0000000000000100;
            4'h3:   bitMap = 16'b0000000000001000;
            4'h4:   bitMap = 16'b0000000000010000;
            4'h5:   bitMap = 16'b0000000000100000;
            4'h6:   bitMap = 16'b0000000001000000;
            4'h7:   bitMap = 16'b0000000010000000;
            4'h8:   bitMap = 16'b0000000100000000;
            4'h9:   bitMap = 16'b0000001000000000;
            4'hA:   bitMap = 16'b0000010000000000;
            4'hB:   bitMap = 16'b0000100000000000;
            4'hC:   bitMap = 16'b0001000000000000;
            4'hD:   bitMap = 16'b0010000000000000;
            4'hE:   bitMap = 16'b0100000000000000;
            4'hF:   bitMap = 16'b1000000000000000;
        endcase
    end

endmodule

// priority encoder
// used by MOVEM regmask
// this might benefit from device specific features
// MOVEM doesn't need speed, will read the result 2 CPU cycles after each update.
module pren( mask, hbit);
   parameter size = 16;
   parameter outbits = 4;

   input [size-1:0] mask;
   output reg [outbits-1:0] hbit;
   // output reg idle;

   always @( mask) begin
      integer i;
      hbit = 0;
      // idle = 1;
      for( i = size-1; i >= 0; i = i - 1) begin
          if (mask[i]) begin
             hbit = i[outbits-1:0];
             // idle = 0;
         end
      end
   end

endmodule

// Microcode sequencer

module sequencer
(
    input                   clk,
    input            s_clks Clks,
    input                   enT3,
    input  [UROM_WIDTH-1:0] microLatch,
    input                   A0Err,
    input                   BerrA,
    input                   busAddrErr,
    input                   Spuria,
    input                   Avia,
    input                   Tpend,
    input                   intPend,
    input                   isIllegal,
    input                   isPriv,
    input                   excRst,
    input                   isLineA,
    input                   isLineF,
    input            [15:0] psw,
    input                   prenEmpty,
    input                   au05z,
    input                   dcr4,
    input                   ze,
    input                   i11,
    input             [1:0] alue01,
    input            [15:0] Ird,
    input [UADDR_WIDTH-1:0] a1,
    input [UADDR_WIDTH-1:0] a2,
    input [UADDR_WIDTH-1:0] a3,
    
    output logic             [3:0] tvn,
    output logic [UADDR_WIDTH-1:0] nma
);

    logic [UADDR_WIDTH-1:0] uNma;
    logic [UADDR_WIDTH-1:0] grp1Nma;
    logic [1:0] c0c1;
    reg a0Rst;
    wire A0Sel;
    wire inGrp0Exc;

    // assign nma = Clks.extReset ? RSTP0_NMA : (A0Err ? BSER1_NMA : uNma);
    // assign nma = A0Err ? (a0Rst ? RSTP0_NMA : BSER1_NMA) : uNma;

    // word type I: 16 15 14 13 12 11 10 09 08 07 06 05 04 03 02 01 00
    // NMA :        .. .. 09 08 01 00 05 04 03 02 07 06 .. .. .. .. ..

    wire [UADDR_WIDTH-1:0] dbNma = { microLatch[ 14:13], microLatch[ 6:5], microLatch[ 10:7], microLatch[ 12:11]};

    // Group 0 exception.
    // Separated block from regular NMA. Otherwise simulation might depend on order of assigments.
    always_comb begin
        if (A0Err) begin
            if (a0Rst)                  // Reset
                nma = RSTP0_NMA[UADDR_WIDTH-1:0];
            else if (inGrp0Exc)         // Double fault
                nma = HALT1_NMA[UADDR_WIDTH-1:0];
            else                        // Bus or address error
                nma = BSER1_NMA[UADDR_WIDTH-1:0];
        end
        else
            nma = uNma;
    end

    always_comb begin
        // Format II (conditional) or I (direct branch)
        if (microLatch[1])
            uNma = { microLatch[ 14:13], c0c1, microLatch[ 10:7], microLatch[ 12:11]};
        else
            case (microLatch[ 3:2])
            0:   uNma = dbNma;   // DB
            1:   uNma = A0Sel ? grp1Nma : a1;
            2:   uNma = a2;
            3:   uNma = a3;
            endcase
    end

    // Format II, conditional, NMA decoding
    wire [1:0] enl = { Ird[6], prenEmpty};      // Updated on T3

    wire [1:0] ms0 = { Ird[8], alue01[0]};
    wire [3:0] m01 = { au05z, Ird[8], alue01};
    wire [1:0] nz1 = { psw[ NF], psw[ ZF]};
    wire [1:0] nv  = { psw[ NF], psw[ VF]};

    logic ccTest;
    wire [4:0] cbc = microLatch[ 6:2];          // CBC bits

    always_comb begin
        unique case (cbc)
        'h0:    c0c1 = {i11, i11};                      // W/L offset EA, from IRC

        'h1:    c0c1 = (au05z) ? 2'b01 : 2'b11;         // Updated on T3
        'h11:   c0c1 = (au05z) ? 2'b00 : 2'b11;

        'h02:   c0c1 = { 1'b0, ~psw[ CF]};              // C used in DIV
        'h12:   c0c1 = { 1'b1, ~psw[ CF]};

        'h03:   c0c1 = {psw[ ZF], psw[ ZF]};            // Z used in DIVU

        'h04:                                           // nz1, used in DIVS
            case (nz1)
               'b00:         c0c1 = 2'b10;
               'b10:         c0c1 = 2'b01;
               'b01,'b11:    c0c1 = 2'b11;
            endcase

        'h05:   c0c1 = {psw[ NF], 1'b1};                // N used in CHK and DIV
        'h15:   c0c1 = {1'b1, psw[ NF]};

        // nz2, used in DIVS (same combination as nz1)
        'h06:   c0c1 = { ~nz1[1] & ~nz1[0], 1'b1};

        'h07:                                           // ms0 used in MUL
        case (ms0)
         'b10, 'b00: c0c1 = 2'b11;
         'b01: c0c1 = 2'b01;
         'b11: c0c1 = 2'b10;
        endcase

        'h08:                                           // m01 used in MUL
        case (m01)
        'b0000,'b0001,'b0100,'b0111:  c0c1 = 2'b11;
        'b0010,'b0011,'b0101:         c0c1 = 2'b01;
        'b0110:                       c0c1 = 2'b10;
        default:                      c0c1 = 2'b00;
        endcase

        // Conditional
        'h09:   c0c1 = (ccTest) ? 2'b11 : 2'b01;
        'h19:   c0c1 = (ccTest) ? 2'b11 : 2'b10;

        // DCR bit 4 (high or low word)
        'h0c:   c0c1 = dcr4 ? 2'b01: 2'b11;
        'h1c:   c0c1 = dcr4 ? 2'b10: 2'b11;

        // DBcc done
        'h0a:   c0c1 = ze ? 2'b11 : 2'b00;

        // nv, used in CHK
        'h0b:   c0c1 = (nv == 2'b00) ? 2'b00 : 2'b11;

        // V, used in trapv
        'h0d:   c0c1 = { ~psw[ VF], ~psw[VF]};

        // enl, combination of pren idle and word/long on IRD
        'h0e,'h1e:
            case (enl)
            2'b00:  c0c1 = 'b10;
            2'b10:  c0c1 = 'b11;
            // 'hx1 result 00/01 depending on condition 0e/1e
            2'b01,2'b11:
                    c0c1 = { 1'b0, microLatch[ 6]};
            endcase

        default:                c0c1 = 'X;
        endcase
    end

    // CCR conditional
    always_comb begin
        unique case (Ird[ 11:8])
        'h0: ccTest = 1'b1;                     // T
        'h1: ccTest = 1'b0;                     // F
        'h2: ccTest = ~psw[ CF] & ~psw[ ZF];    // HI
        'h3: ccTest = psw[ CF] | psw[ZF];       // LS
        'h4: ccTest = ~psw[ CF];                // CC (HS)
        'h5: ccTest = psw[ CF];                 // CS (LO)
        'h6: ccTest = ~psw[ ZF];                // NE
        'h7: ccTest = psw[ ZF];                 // EQ
        'h8: ccTest = ~psw[ VF];                // VC
        'h9: ccTest = psw[ VF];                 // VS
        'ha: ccTest = ~psw[ NF];                // PL
        'hb: ccTest = psw[ NF];                 // MI
        'hc: ccTest = (psw[ NF] & psw[ VF]) | (~psw[ NF] & ~psw[ VF]);              // GE
        'hd: ccTest = (psw[ NF] & ~psw[ VF]) | (~psw[ NF] & psw[ VF]);              // LT
        'he: ccTest = (psw[ NF] & psw[ VF] & ~psw[ ZF]) |
                 (~psw[ NF] & ~psw[ VF] & ~psw[ ZF]);                               // GT
        'hf: ccTest = psw[ ZF] | (psw[ NF] & ~psw[VF]) | (~psw[ NF] & psw[VF]);     // LE
        endcase
    end

    // Exception logic
    logic rTrace, rInterrupt;
    logic rIllegal, rPriv, rLineA, rLineF;
    logic rExcRst, rExcAdrErr, rExcBusErr;
    logic rSpurious, rAutovec;
    wire grp1LatchEn, grp0LatchEn;

    // Originally control signals latched on T4. Then exception latches updated on T3
    assign grp1LatchEn = microLatch[0] & (microLatch[1] | !microLatch[4]);
    assign grp0LatchEn = microLatch[4] & !microLatch[1];

    assign inGrp0Exc = rExcRst | rExcBusErr | rExcAdrErr;

    always_ff @(posedge clk) begin
        if (grp0LatchEn & enT3) begin
            rExcRst <= excRst;
            rExcBusErr <= BerrA;
            rExcAdrErr <= busAddrErr;
            rSpurious <= Spuria;
            rAutovec <= Avia;
        end

        // Update group 1 exception latches
        // Inputs from IR decoder updated on T1 as soon as IR loaded
        // Trace pending updated on T3 at the start of the instruction
        // Interrupt pending on T2
        if (grp1LatchEn & enT3) begin
            rTrace <= Tpend;
            rInterrupt <= intPend;
            rIllegal <= isIllegal & ~isLineA & ~isLineF;
            rLineA <= isLineA;
            rLineF <= isLineF;
            rPriv <= isPriv & !psw[ SF];
        end
    end

    // exception priority
    always_comb begin
        grp1Nma = TRAC1_NMA[UADDR_WIDTH-1:0];
        if (rExcRst)
            tvn = 4'h0;                         // Might need to change that to signal in exception
        else if (rExcBusErr | rExcAdrErr)
            tvn = { 3'b001, rExcAdrErr};

        // Seudo group 0 exceptions. Just for updating TVN
        else if (rSpurious | rAutovec)
            tvn = rSpurious ? TVN_SPURIOUS : TVN_AUTOVEC;

        else if (rTrace)
            tvn = 4'h9;
        else if (rInterrupt) begin
            tvn = TVN_INTERRUPT;
            grp1Nma = ITLX1_NMA[UADDR_WIDTH-1:0];
        end
        else begin
            unique case (1'b1)                  // Can't happen more than one of these
            rIllegal:           tvn = 4'h4;
            rPriv:              tvn = 4'h8;
            rLineA:             tvn = 4'hA;
            rLineF:             tvn = 4'hB;
            default:            tvn = 4'h1;     // Signal no group 0/1 exception
            endcase
        end
    end

    assign A0Sel = rIllegal | rLineF | rLineA | rPriv | rTrace | rInterrupt;

    always_ff @(posedge clk) begin
        if (Clks.extReset)
            a0Rst <= 1'b1;
        else if (enT3)
            a0Rst <= 1'b0;
    end

endmodule


//
// DMA/BUS Arbitration
//

module busArbiter
(
    input        clk,
    input s_clks Clks,
    input        BRi,
    input        BgackI,
    input        Halti,
    input        bgBlock,
    output       busAvail,
    output logic BGn
);

    enum int unsigned { DRESET = 0, DIDLE, D1, D_BR, D_BA, D_BRA, D3, D2} dmaPhase, next;

    always_comb begin
        case(dmaPhase)
        DRESET: next = DIDLE;
        DIDLE:  begin
                if (bgBlock)
                    next = DIDLE;
                else if (~BgackI)
                    next = D_BA;
                else if (~BRi)
                    next = D1;
                else
                    next = DIDLE;
                end

        D_BA:   begin                           // Loop while only BGACK asserted, BG negated here
                if (~BRi & !bgBlock)
                    next = D3;
                else if (~BgackI & !bgBlock)
                    next = D_BA;
                else
                    next = DIDLE;
                end

        D1:     next = D_BR;                            // Loop while only BR asserted
        D_BR:   next = ~BRi & BgackI ? D_BR : D_BA;     // No direct path to IDLE !

        D3:     next = D_BRA;
        D_BRA:  begin                       // Loop while both BR and BGACK asserted
                case ({BgackI, BRi} )
                2'b11:  next = DIDLE;       // Both deasserted
                2'b10:  next = D_BR;        // BR asserted only
                2'b01:  next = D2;          // BGACK asserted only
                2'b00:  next = D_BRA;       // Stay here while both asserted
                endcase
                end

        // Might loop here if both deasserted, should normally don't arrive here anyway?
        // D2:      next = (BgackI & BRi) | bgBlock ? D2: D_BA;

        D2:     next = D_BA;

        default:    next = DIDLE;           // Should not reach here normally
        endcase
    end

    logic granting;
    always_comb begin
        unique case (next)
        D1, D3, D_BR, D_BRA:    granting = 1'b1;
        default:                granting = 1'b0;
        endcase
    end

    reg rGranted;
    assign busAvail = Halti & BRi & BgackI & ~rGranted;

    always_ff @(posedge clk) begin

        if (Clks.extReset) begin
            dmaPhase <= DRESET;
            rGranted <= 1'b0;
        end
        else if (Clks.enPhi2) begin
            dmaPhase <= next;
            // Internal signal changed on PHI2
            rGranted <= granting;
        end

        // External Output changed on PHI1
        if (Clks.extReset)
            BGn <= 1'b1;
        else if (Clks.enPhi1)
            BGn <= ~rGranted;

    end

endmodule

module busControl
(
    input         clk,
    input  s_clks Clks,
    input         enT1,
    input         enT4,
    input         permStart,
    input         permStop,
    input         iStop,
    input         aob0,
    input         isWrite,
    input         isByte,
    input         isRmc,
    input         busAvail,
    output        bgBlock,
    output        busAddrErr,
    output        waitBusCycle,
    output        busStarting,  // Asserted during S0
    output logic  addrOe,       // Asserted from S1 to the end, whole bus cycle except S0
    output        bciWrite,     // Used for SSW on bus/addr error

    input         rDtack,
    input         BeDebounced,
    input         Vpai,
    output        ASn,
    output        LDSn,
    output        UDSn,
    output        eRWn
);

    reg rAS, rLDS, rUDS, rRWn;
    assign ASn = rAS;
    assign LDSn = rLDS;
    assign UDSn = rUDS;
    assign eRWn = rRWn;

    reg dataOe;

    reg bcPend;
    reg isWriteReg, bciByte, isRmcReg, wendReg;
    assign bciWrite = isWriteReg;
    reg addrOeDelay;
    reg isByteT4;

    wire canStart, busEnd;
    wire bcComplete, bcReset;

    wire isRcmReset = bcComplete & bcReset & isRmcReg;

    assign busAddrErr = aob0 & ~bciByte;

    // Bus retry not really supported.
    // It's BERR and HALT and not address error, and not read-modify cycle.
    wire busRetry = ~busAddrErr & 1'b0;

    enum int unsigned { SRESET = 0, SIDLE, S0, S2, S4, S6, SRMC_RES} busPhase, next;

    always_ff @(posedge clk) begin
        if (Clks.extReset)
            busPhase <= SRESET;
        else if (Clks.enPhi1)
            busPhase <= next;
    end

    always_comb begin
        case (busPhase)
            SRESET:   next = SIDLE;
            SRMC_RES: next = SIDLE;           // Single cycle special state when read phase of RMC reset
            S0:       next = S2;
            S2:       next = S4;
            S4:       next = busEnd ? S6 : S4;
            S6:       next = isRcmReset ? SRMC_RES : (canStart ? S0 : SIDLE);
            SIDLE:    next = canStart ? S0 : SIDLE;
            default:  next = SIDLE;
        endcase
    end

    // Idle phase of RMC bus cycle. Might be better to just add a new state
    wire rmcIdle = (busPhase == SIDLE) & ~ASn & isRmcReg;

    assign canStart = (busAvail | rmcIdle) & (bcPend | permStart) & !busRetry & !bcReset;

    wire busEnding = (next == SIDLE) | (next == S0);

    assign busStarting = (busPhase == S0);

    // term signal (DTACK, BERR, VPA, adress error)
    assign busEnd = ~rDtack | iStop;

    // bcComplete asserted on raising edge of S6 (together with SNC).
    assign bcComplete = (busPhase == S6);

    // Clear bus info latch on completion (regular or aborted) and no bus retry (and not PHI1).
    // bciClear asserted half clock later on PHI2, and bci latches cleared async concurrently
    wire bciClear = bcComplete & ~busRetry;

    // Reset on reset or (berr & berrDelay & (not halt or rmc) & not 6800 & in bus cycle) (and not PHI1)
    assign bcReset = Clks.extReset | (addrOeDelay & BeDebounced & Vpai);

    // Enable uclock only on S6 (S8 on Bus Error) or not bciPermStop
    assign waitBusCycle = wendReg & !bcComplete;

    // Block Bus Grant when starting new bus cycle. But No need if AS already asserted (read phase of RMC)
    // Except that when that RMC phase aborted on bus error, it's asserted one cycle later!
    assign bgBlock = ((busPhase == S0) & ASn) | (busPhase == SRMC_RES);

    always_ff @(posedge clk) begin
    
        if (Clks.extReset) begin
            addrOe <= 1'b0;
        end
        // S0 (enPHi2, S0) -> S1 (enPhi1, S0)
        else if (Clks.enPhi2 & ( busPhase == S0))           // From S1, whole bus cycle except S0
            addrOe <= 1'b1;
        else if (Clks.enPhi1 & (busPhase == SRMC_RES))
            addrOe <= 1'b0;
        else if (Clks.enPhi1 & ~isRmcReg & busEnding)
            addrOe <= 1'b0;

        if (Clks.enPhi1)
            addrOeDelay <= addrOe;

        if (Clks.extReset) begin
            rAS    <= 1'b1;
            rUDS   <= 1'b1;
            rLDS   <= 1'b1;
            rRWn   <= 1'b1;
            dataOe <= 1'b0;
        end
        else begin

            if (Clks.enPhi2 & isWriteReg & (busPhase == S2))
                dataOe <= 1'b1;
            else if (Clks.enPhi1 & (busEnding | (busPhase == SIDLE)) )
                dataOe <= 1'b0;

            if (Clks.enPhi1 & busEnding)
                rRWn <= 1'b1;
            else if (Clks.enPhi1 & isWriteReg) begin
                // Unlike LDS/UDS Asserted even in address error
                if ((busPhase == S0) & isWriteReg)
                    rRWn <= 1'b0;
            end

            // AS. Actually follows addrOe half cycle later!
            // S1 (enPhi1, S0) -> S2 (enPHi2, S2)
            if (Clks.enPhi1 & (busPhase == S0))
                rAS <= 1'b0;
            else if (Clks.enPhi2 & (busPhase == SRMC_RES))      // Bus error on read phase of RMC. Deasserted one cycle later
                rAS <= 1'b1;
            //else if (Clks.enPhi2 & bcComplete & ~SRMC_RES) ???
            else if (Clks.enPhi2 & bcComplete)
                if (~isRmcReg)                                  // Keep AS asserted on the IDLE phase of RMC
                    rAS <= 1'b1;

            if (Clks.enPhi1 & (busPhase == S0)) begin
                if (~isWriteReg & !busAddrErr) begin
                    rUDS <= ~(~bciByte | ~aob0);
                    rLDS <= ~(~bciByte |  aob0);
                end
            end
            else if (Clks.enPhi1 & isWriteReg & (busPhase == S2) & !busAddrErr) begin
                rUDS <= ~(~bciByte | ~aob0);
                rLDS <= ~(~bciByte |  aob0);
            end
            else if (Clks.enPhi2 & bcComplete) begin
                rUDS <= 1'b1;
                rLDS <= 1'b1;
            end
        end
    end

    // Bus cycle info latch. Needed because uinstr might change if the bus is busy and we must wait.
    // Note that urom advances even on wait states. It waits *after* updating urom and nanorom latches.
    // Even without wait states, ublocks of type ir (init reading) will not wait for bus completion.
    // Originally latched on (permStart AND T1).

    // Bus cycle info latch: isRead, isByte, read-modify-cycle, and permStart (bus cycle pending). Some previously latched on T4?
    // permStop also latched, but unconditionally on T1

    // Might make more sense to register this outside this module
    always_ff @(posedge clk) begin

        if (enT4) begin
            isByteT4 <= isByte;
        end
    end

    // Bus Cycle Info Latch
    always_ff @(posedge clk) begin

        if (Clks.pwrUp) begin
            bcPend     <= 1'b0;
            wendReg    <= 1'b0;
            isWriteReg <= 1'b0;
            bciByte    <= 1'b0;
            isRmcReg   <= 1'b0;
        end
        else if (Clks.enPhi2 & (bciClear | bcReset)) begin
            bcPend     <= 1'b0;
            wendReg    <= 1'b0;
        end
        else begin
            if (enT1 & permStart) begin
                isWriteReg <= isWrite;
                bciByte    <= isByteT4;
                isRmcReg   <= isRmc & ~isWrite;   // We need special case the end of the read phase only.
                bcPend     <= 1'b1;
            end
            if (enT1) begin
                wendReg    <= permStop;
            end
        end
    end

endmodule

//
// microrom and nanorom instantiation
//
// There is bit of wasting of resources here. An extra registering pipeline happens that is not needed.
// This is just for the purpose of helping inferring block RAM using pure generic code. Inferring RAM is important for performance.
// Might be more efficient to use vendor specific features such as clock enable.
//

module uRom
(
    input                          clk,
    input        [UADDR_WIDTH-1:0] microAddr,
    output logic  [UROM_WIDTH-1:0] microOutput
);

    reg [UROM_WIDTH-1:0] uRam[0:UROM_DEPTH-1];

    initial begin
        $readmemb("microrom.mem", uRam);
    end

    always_ff @(posedge clk) begin
        microOutput <= uRam[microAddr];
    end

endmodule


module nanoRom
(
    input                         clk,
    input       [NADDR_WIDTH-1:0] nanoAddr,
    output logic [NANO_WIDTH-1:0] nanoOutput
);

    reg [NANO_WIDTH-1:0] nRam[0:NANO_DEPTH-1];

    initial begin
        $readmemb("nanorom.mem", nRam);
    end

    always_ff @(posedge clk) begin
        nanoOutput <= nRam[nanoAddr];
    end

endmodule

// Translate uaddr to nanoaddr
module microToNanoAddr(
    input [UADDR_WIDTH-1:0] uAddr,
    output [NADDR_WIDTH-1:0] orgAddr);

    wire [UADDR_WIDTH-1:2] baseAddr = uAddr[UADDR_WIDTH-1:2];
    logic [NADDR_WIDTH-1:2] orgBase;
    assign orgAddr = { orgBase, uAddr[1:0]};

    always @( baseAddr)
    begin
        // nano ROM (136 addresses)
        case (baseAddr)

'h00: orgBase = 7'h0 ;
'h01: orgBase = 7'h1 ;
'h02: orgBase = 7'h2 ;
'h03: orgBase = 7'h2 ;
'h08: orgBase = 7'h3 ;
'h09: orgBase = 7'h4 ;
'h0A: orgBase = 7'h5 ;
'h0B: orgBase = 7'h5 ;
'h10: orgBase = 7'h6 ;
'h11: orgBase = 7'h7 ;
'h12: orgBase = 7'h8 ;
'h13: orgBase = 7'h8 ;
'h18: orgBase = 7'h9 ;
'h19: orgBase = 7'hA ;
'h1A: orgBase = 7'hB ;
'h1B: orgBase = 7'hB ;
'h20: orgBase = 7'hC ;
'h21: orgBase = 7'hD ;
'h22: orgBase = 7'hE ;
'h23: orgBase = 7'hD ;
'h28: orgBase = 7'hF ;
'h29: orgBase = 7'h10 ;
'h2A: orgBase = 7'h11 ;
'h2B: orgBase = 7'h10 ;
'h30: orgBase = 7'h12 ;
'h31: orgBase = 7'h13 ;
'h32: orgBase = 7'h14 ;
'h33: orgBase = 7'h14 ;
'h38: orgBase = 7'h15 ;
'h39: orgBase = 7'h16 ;
'h3A: orgBase = 7'h17 ;
'h3B: orgBase = 7'h17 ;
'h40: orgBase = 7'h18 ;
'h41: orgBase = 7'h18 ;
'h42: orgBase = 7'h18 ;
'h43: orgBase = 7'h18 ;
'h44: orgBase = 7'h19 ;
'h45: orgBase = 7'h19 ;
'h46: orgBase = 7'h19 ;
'h47: orgBase = 7'h19 ;
'h48: orgBase = 7'h1A ;
'h49: orgBase = 7'h1A ;
'h4A: orgBase = 7'h1A ;
'h4B: orgBase = 7'h1A ;
'h4C: orgBase = 7'h1B ;
'h4D: orgBase = 7'h1B ;
'h4E: orgBase = 7'h1B ;
'h4F: orgBase = 7'h1B ;
'h54: orgBase = 7'h1C ;
'h55: orgBase = 7'h1D ;
'h56: orgBase = 7'h1E ;
'h57: orgBase = 7'h1F ;
'h5C: orgBase = 7'h20 ;
'h5D: orgBase = 7'h21 ;
'h5E: orgBase = 7'h22 ;
'h5F: orgBase = 7'h23 ;
'h70: orgBase = 7'h24 ;
'h71: orgBase = 7'h24 ;
'h72: orgBase = 7'h24 ;
'h73: orgBase = 7'h24 ;
'h74: orgBase = 7'h24 ;
'h75: orgBase = 7'h24 ;
'h76: orgBase = 7'h24 ;
'h77: orgBase = 7'h24 ;
'h78: orgBase = 7'h25 ;
'h79: orgBase = 7'h25 ;
'h7A: orgBase = 7'h25 ;
'h7B: orgBase = 7'h25 ;
'h7C: orgBase = 7'h25 ;
'h7D: orgBase = 7'h25 ;
'h7E: orgBase = 7'h25 ;
'h7F: orgBase = 7'h25 ;
'h84: orgBase = 7'h26 ;
'h85: orgBase = 7'h27 ;
'h86: orgBase = 7'h28 ;
'h87: orgBase = 7'h29 ;
'h8C: orgBase = 7'h2A ;
'h8D: orgBase = 7'h2B ;
'h8E: orgBase = 7'h2C ;
'h8F: orgBase = 7'h2D ;
'h94: orgBase = 7'h2E ;
'h95: orgBase = 7'h2F ;
'h96: orgBase = 7'h30 ;
'h97: orgBase = 7'h31 ;
'h9C: orgBase = 7'h32 ;
'h9D: orgBase = 7'h33 ;
'h9E: orgBase = 7'h34 ;
'h9F: orgBase = 7'h35 ;
'hA4: orgBase = 7'h36 ;
'hA5: orgBase = 7'h36 ;
'hA6: orgBase = 7'h37 ;
'hA7: orgBase = 7'h37 ;
'hAC: orgBase = 7'h38 ;
'hAD: orgBase = 7'h38 ;
'hAE: orgBase = 7'h39 ;
'hAF: orgBase = 7'h39 ;
'hB4: orgBase = 7'h3A ;
'hB5: orgBase = 7'h3A ;
'hB6: orgBase = 7'h3B ;
'hB7: orgBase = 7'h3B ;
'hBC: orgBase = 7'h3C ;
'hBD: orgBase = 7'h3C ;
'hBE: orgBase = 7'h3D ;
'hBF: orgBase = 7'h3D ;
'hC0: orgBase = 7'h3E ;
'hC1: orgBase = 7'h3F ;
'hC2: orgBase = 7'h40 ;
'hC3: orgBase = 7'h41 ;
'hC8: orgBase = 7'h42 ;
'hC9: orgBase = 7'h43 ;
'hCA: orgBase = 7'h44 ;
'hCB: orgBase = 7'h45 ;
'hD0: orgBase = 7'h46 ;
'hD1: orgBase = 7'h47 ;
'hD2: orgBase = 7'h48 ;
'hD3: orgBase = 7'h49 ;
'hD8: orgBase = 7'h4A ;
'hD9: orgBase = 7'h4B ;
'hDA: orgBase = 7'h4C ;
'hDB: orgBase = 7'h4D ;
'hE0: orgBase = 7'h4E ;
'hE1: orgBase = 7'h4E ;
'hE2: orgBase = 7'h4F ;
'hE3: orgBase = 7'h4F ;
'hE8: orgBase = 7'h50 ;
'hE9: orgBase = 7'h50 ;
'hEA: orgBase = 7'h51 ;
'hEB: orgBase = 7'h51 ;
'hF0: orgBase = 7'h52 ;
'hF1: orgBase = 7'h52 ;
'hF2: orgBase = 7'h52 ;
'hF3: orgBase = 7'h52 ;
'hF8: orgBase = 7'h53 ;
'hF9: orgBase = 7'h53 ;
'hFA: orgBase = 7'h53 ;
'hFB: orgBase = 7'h53 ;

            default:
                orgBase = 'X;
        endcase
    end

endmodule

//
// For compilation test only
//

`ifdef FX68K_TEST
module fx68kTop
(
    input         clk32,
    input         extReset,
    output        oRESETn,
    output        oHALTEDn,
    //
    output        E,
    output        E_rise,
    output        E_fall,
    input         VPAn,
    output        VMAn,
    //
    output        ASn,
    output        eRWn,
    output        LDSn,
    output        UDSn,
    output        FC2,
    output        FC1,
    output        FC0,
    input         DTACKn,
    input         BERRn,
    //
    input         BRn,
    output        BGn,
    input         BGACKn,
    //
    input         IPL2n,
    input         IPL1n,
    input         IPL0n,
    //
    input  [15:0] iEdb,
    output [15:0] oEdb,
    output [31:1] eab
);

    // Clock must be at least twice the desired frequency. A 32 MHz clock means a maximum 16 MHz effective frequency.
    // In this example we divide the clock by 4. Resulting on an effective processor running at 8 MHz.

    reg [1:0] clkDivisor = 2'd0;
    always @( posedge clk32) begin
        clkDivisor <= clkDivisor + 2'd1;
    end

    /*
    These two signals must be a single cycle pulse. They don't need to be registered.
    Same signal can't be asserted twice in a row. Other than that there are no restrictions.
    There can be any number of cycles, or none, even variable non constant cycles, between each pulse.
    */

    wire enPhi1 = (clkDivisor == 2'd3) ? 1'b1 : 1'b0;
    wire enPhi2 = (clkDivisor == 2'd1) ? 1'b1 : 1'b0;


    fx68k fx68k
    (
        .clk (clk32),
        .enPhi1,
        .enPhi2,
        
        .extReset,
        .pwrUp (extReset),
        .oRESETn, .oHALTEDn,

        .E, .E_rise, .E_fall,
        .VPAn, .VMAn,
        
        .ASn, .eRWn, .LDSn, .UDSn,
        .FC2, .FC1, .FC0,
        .DTACKn, .BERRn,
        
        .BRn, .BGn, .BGACKn,
        .IPL0n, .IPL1n, .IPL2n,
        
        .iEdb,
        .oEdb,
        .eab
    );

endmodule
`endif
