//
// FX68K
//
// M68000 cycle accurate, fully synchronous
// Copyright (c) 2018 by Jorge Cwik
//
// TODO:
// - Everything except bus retry already implemented.

`timescale 1 ns / 1 ns

//`define _FX68K_FPGA_STRATIX_
//`define _FX68K_FPGA_STRATIX_II_
//`define _FX68K_FPGA_STRATIX_III_
//`define _FX68K_FPGA_CYCLONE_
//`define _FX68K_FPGA_CYCLONE_II_
//`define _FX68K_FPGA_CYCLONE_III_
//`define _FX68K_FPGA_CYCLONE_IV_
//`define _FX68K_FPGA_CYCLONE_V_

`ifdef _VLINT_

    `include "fx68k_pkg.sv"
    `include "uaddrPla.sv"
    `include "fx68kAlu.sv"
    `include "bram/fx68kRom_generic.sv"
    `include "bram/fx68kRegs_generic.sv"
    
`else /* _VLINT_ */

    `ifdef _FX68K_FPGA_STRATIX_
    `define _FX68K_FPGA_VENDOR_ALTERA_
    `define _FX68K_FPGA_DEVICE_ "Stratix"
    `define _FX68K_BRAM_TYPE_   "M4K"
    `endif /* _FX68K_FPGA_STRATIX_ */
    
    `ifdef _FX68K_FPGA_STRATIX_II_
    `define _FX68K_FPGA_VENDOR_ALTERA_
    `define _FX68K_FPGA_DEVICE_ "Stratix II"
    `define _FX68K_BRAM_TYPE_   "M4K"
    `endif /* _FX68K_FPGA_STRATIX_II_ */
    
    `ifdef _FX68K_FPGA_STRATIX_III_
    `define _FX68K_FPGA_VENDOR_ALTERA_
    `define _FX68K_FPGA_DEVICE_ "Stratix III"
    `define _FX68K_BRAM_TYPE_   "M9K"
    `endif /* _FX68K_FPGA_STRATIX_III_ */
    
    `ifdef _FX68K_FPGA_CYCLONE_
    `define _FX68K_FPGA_VENDOR_ALTERA_
    `define _FX68K_FPGA_DEVICE_ "Cyclone"
    `define _FX68K_BRAM_TYPE_   "M4K"
    `endif /* _FX68K_FPGA_CYCLONE_ */
    
    `ifdef _FX68K_FPGA_CYCLONE_II_
    `define _FX68K_FPGA_VENDOR_ALTERA_
    `define _FX68K_FPGA_DEVICE_ "Cyclone II"
    `define _FX68K_BRAM_TYPE_   "M4K"
    `endif /* _FX68K_FPGA_CYCLONE_II_ */
    
    `ifdef _FX68K_FPGA_CYCLONE_III_
    `define _FX68K_FPGA_VENDOR_ALTERA_
    `define _FX68K_FPGA_DEVICE_ "Cyclone III"
    `define _FX68K_BRAM_TYPE_   "M9K"
    `endif /* _FX68K_FPGA_CYCLONE_III_ */
    
    `ifdef _FX68K_FPGA_CYCLONE_IV_
    `define _FX68K_FPGA_VENDOR_ALTERA_
    `define _FX68K_FPGA_DEVICE_ "Cyclone IV"
    `define _FX68K_BRAM_TYPE_   "M9K"
    `endif /* _FX68K_FPGA_CYCLONE_IV_ */
    
    `ifdef _FX68K_FPGA_CYCLONE_V_
    `define _FX68K_FPGA_VENDOR_ALTERA_
    `define _FX68K_FPGA_DEVICE_ "Cyclone V"
    `define _FX68K_BRAM_TYPE_   "M10K"
    `endif /* _FX68K_FPGA_CYCLONE_V_ */

`endif /* _VLINT_ */

// Define this to run a self contained compilation test build
// `define FX68K_TEST

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
    wire  [NANO_WIDTH-1:0] wNanoLatch_t3;
    wire  [UROM_WIDTH-1:0] wMicroLatch_t3;

    reg  [UADDR_WIDTH-1:0] rMicroAddr_t1;
    wire [UADDR_WIDTH-1:0] wMicroAddr;
    reg  [NADDR_WIDTH-1:0] rNanoAddr_t1;
    wire [NADDR_WIDTH-1:0] wNanoAddr;
    
    // For the time being, address translation is done for nanorom only.
    microToNanoAddr microToNanoAddr
    (
        .uAddr   (wMicroAddr),
        .orgAddr (wNanoAddr)
    );

    always_ff @(posedge clk) begin : ROM_ADDR_T1
        // uaddr originally latched on T1, except bits 6 & 7, the conditional bits, on T2
        // Seems we can latch whole address at either T1 or T2

        // Originally it's invalid on hardware reset, and forced later when coming out of reset
        if (Clks.pwrUp) begin
            rMicroAddr_t1 <= RSTP0_NMA[UADDR_WIDTH-1:0];
            rNanoAddr_t1  <= RSTP0_NMA[NADDR_WIDTH-1:0];
        end
        else if (enT1) begin
            rMicroAddr_t1 <= wMicroAddr;
            rNanoAddr_t1  <= wNanoAddr;                // Register translated uaddr to naddr
        end
    end

    // Reset micro/nano latch after T4 of the current ublock.
    wire wRstUrom = Clks.extReset | Clks.enPhi1 & enErrClk;

    // Output of these modules will be updated at T3
    fx68kRom
    #(
       .OUTPUT_REG  (1),
       .ADDR_WIDTH  (NADDR_WIDTH),
       .DATA_WIDTH  (NANO_WIDTH),
`ifdef _FX68K_FPGA_VENDOR_ALTERA_
       .INIT_FILE   ("nanorom.mif"),
       .FPGA_DEVICE (`_FX68K_FPGA_DEVICE_),
       .BRAM_TYPE   (`_FX68K_BRAM_TYPE_)
`else
       .INIT_FILE   ("nanorom.mem")
`endif
    )
    U_nanoRom_t3
    (
        .rst        (wRstUrom),
        .clk        (clk),
        .clk_ena    (enT3), // ROM output available at T3
        .addr       (rNanoAddr_t1),
        .q          (wNanoLatch_t3)
    );
    
    fx68kRom
    #(
       .OUTPUT_REG  (1),
       .ADDR_WIDTH  (UADDR_WIDTH),
       .DATA_WIDTH  (UROM_WIDTH),
`ifdef _FX68K_FPGA_VENDOR_ALTERA_
       .INIT_FILE   ("microrom.mif"),
       .FPGA_DEVICE (`_FX68K_FPGA_DEVICE_),
       .BRAM_TYPE   (`_FX68K_BRAM_TYPE_)
`else
       .INIT_FILE   ("microrom.mem")
`endif
    )
    U_microRom_t3
    (
        .rst        (wRstUrom),
        .clk        (clk),
        .clk_ena    (enT3), // ROM output available at T3
        .addr       (rMicroAddr_t1),
        .q          (wMicroLatch_t3)
    );

    // Decoded nanocode signals
    s_nanod_r wNanoDec_t4;
    s_nanod_w wNanoDec_t3;
    // IRD decoded control signals
    s_irdecod wIrdDecode_t1;

    //
    reg         Tpend;
    reg         intPend; // Interrupt pending
    reg         pswT;
    reg         pswS;
    reg   [2:0] pswI;
    wire  [7:0] ccr;

    wire [15:0] psw = { pswT, 1'b0, pswS, 2'b00, pswI, ccr };

    reg  [15:0] rFtu_t3;
    
    wire [15:0] wIrc_t4;
    wire [15:0] wIrcL_t4;
    
    reg  [15:0] rIr_t1;
    reg  [15:0] rIrL_t1;
    reg   [3:0] rIrEA1_t1;
    reg   [3:0] rIrEA2_t1;
    
    reg  [15:0] rIrd_t1;
    reg  [15:0] rIrdL_t1;

    wire [15:0] alue;
    wire [15:0] wAbl_t2;
    wire prenEmpty, au05z, dcr4, ze;

    onehotEncoder4 U_IrcLine_T4(wIrc_t4[15:12], wIrcL_t4);

    // IR & IRD forwarding
    // and some IR pre-decoding
    always_ff @(posedge clk) begin : IR_IRD_T1

        if (enT1) begin
            if (wNanoDec_t3.Ir2Ird) begin
                rIrd_t1   <= rIr_t1;
                rIrdL_t1  <= rIrL_t1;
            end
            else if (wMicroLatch_t3[0]) begin
                // prevented by IR => IRD !
                rIr_t1    <= wIrc_t4;
                // Instruction groups pre-decoding
                rIrL_t1   <= wIrcL_t4;
                // Effective address pre-decoding
                rIrEA1_t1 <= eaDecode(wIrc_t4[5:0]);
                rIrEA2_t1 <= eaDecode({ wIrc_t4[8:6], wIrc_t4[11:9] });
            end
        end
    end
    
    wire [UADDR_WIDTH-1:0] wPlaA1_t1;
    wire [UADDR_WIDTH-1:0] wPlaA2_t1;
    wire [UADDR_WIDTH-1:0] wPlaA3_t1;
    wire                   wIsPriv_t1;
    wire                   wIsIllegal_t1;
    wire                   wIsLineA_t1 = rIrL_t1[4'hA];
    wire                   wIsLineF_t1 = rIrL_t1[4'hF];

    uaddrDecode U_uaddrDecode_T1
    (
        .iOpCode_t1    (rIr_t1),
        .iOpLine_t1    (rIrL_t1),
        .iEA1_t1       (rIrEA1_t1),
        .iEA2_t1       (rIrEA2_t1),
        .oPlaA1_t1     (wPlaA1_t1),
        .oPlaA2_t1     (wPlaA2_t1),
        .oPlaA3_t1     (wPlaA3_t1),
        .oIsPriv_t1    (wIsPriv_t1),
        .oIsIllegal_t1 (wIsIllegal_t1)
    );

    wire [3:0] tvn;
    wire waitBusCycle, busStarting;
    wire BusRetry = 1'b0;
    wire busAddrErr;
    wire bciWrite;                      // Last bus cycle was write
    wire bgBlock, busAvail;
    wire addrOe;

    wire busIsByte = wNanoDec_t3.busByte & (wIrdDecode_t1.isByte | wIrdDecode_t1.isMovep);
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

    sequencer sequencer
    (
        .clk,
        .Clks,
        .enT3,
        .iMicroLatch_t3 (wMicroLatch_t3),
        .Ird        (rIrd_t1),
        .A0Err, .excRst, .BerrA, .busAddrErr, .Spuria, .Avia,
        .Tpend, .intPend,
        .isIllegal (wIsIllegal_t1),
        .isPriv    (wIsPriv_t1),
        .isLineA   (wIsLineA_t1),
        .isLineF   (wIsLineF_t1),
        .nma       (wMicroAddr),
        .a1        (wPlaA1_t1),
        .a2        (wPlaA2_t1),
        .a3        (wPlaA3_t1),
        .tvn,
        .psw, .prenEmpty, .au05z, .dcr4, .ze, .alue01( alue[1:0]), .i11(wIrc_t4[11])
    );

    excUnit excUnit
    (
        .clk,
        .Clks,
        .enT1, .enT2, .enT3, .enT4,
        .iNanoDec_t4   (wNanoDec_t4),
        .iNanoDec_t3   (wNanoDec_t3),
        .iIrdDecode_t1 (wIrdDecode_t1),
        .Ird           (rIrd_t1),
        .iFtu_t3       (rFtu_t3), 
        .iEdb, .pswS,
        .prenEmpty, .au05z, .dcr4, .ze,
        .oAbl_t2     (wAbl_t2),
        .eab, .aob0,
        .oIrc_t4 (wIrc_t4),
        .oEdb,
        .alue, .ccr);

    nDecoder3 nDecoder
    (
        .clk,
        .enT2,
        .enT4,
        .iNanoLatch_t3 (wNanoLatch_t3),
        .iIrdDecode_t1 (wIrdDecode_t1),
        .oNanoDec_t4   (wNanoDec_t4),
        .oNanoDec_t3   (wNanoDec_t3)
    );

    irdDecode U_irdDecode_T1
    (
        .iIrd_t1       (rIrd_t1),
        .iIrdL_t1      (rIrdL_t1),
        .oIrdDecode_t1 (wIrdDecode_t1)
    );

    busControl busControl( .clk, .Clks, .enT1, .enT4, .permStart(wNanoDec_t3.permStart), .permStop(wNanoDec_t3.waitBusFinish), .iStop,
        .aob0, .isWrite(wNanoDec_t3.isWrite), .isRmc(wNanoDec_t4.isRmc), .isByte(busIsByte), .busAvail,
        .bciWrite, .addrOe, .bgBlock, .waitBusCycle, .busStarting, .busAddrErr,
        .rDtack, .BeDebounced, .Vpai,
        .ASn, .LDSn, .UDSn, .eRWn);

    busArbiter busArbiter( .clk, .Clks, .BRi, .BgackI, .Halti, .bgBlock, .busAvail, .BGn);


    // Output reset & halt control
    wire [1:0] uFc = wMicroLatch_t3[16:15];
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
            oReset  <= (uFc == 2'b01) ? ~wNanoDec_t3.permStart : 1'b0;
            oHalted <= (uFc == 2'b10) ? ~wNanoDec_t3.permStart : 1'b0;
        end
    end

    logic [2:0] rFC;
    assign { FC2, FC1, FC0} = rFC;                  // ~rFC;
    assign Iac = {rFC == 3'b111};                   // & Control output enable !!

    always_ff @(posedge clk) begin

        if (Clks.extReset) begin
            rFC <= 3'b000;
        end
        else if (enT1 & wNanoDec_t3.permStart) begin      // S0 phase of bus cycle
            rFC[2] <= pswS;
            // If FC is type 'n' (0) at ucode, access type depends on PC relative mode
            // We don't care about RZ in this case. Those uinstructions with RZ don't start a bus cycle.
            rFC[1] <= wMicroLatch_t3[ 16] | ( ~wMicroLatch_t3[ 15] &  wIrdDecode_t1.isPcRel);
            rFC[0] <= wMicroLatch_t3[ 15] | ( ~wMicroLatch_t3[ 16] & ~wIrdDecode_t1.isPcRel);
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
            updIll <= wMicroLatch_t3[0];        // Update on any IRC->IR
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
        else if (enT2 & wNanoDec_t3.permStart)
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
            irdToCcr_t4 <= wIrdDecode_t1.toCcr;
        end

        else if (enT3) begin

            // UNIQUE IF !!
            if (wNanoDec_t4.updTpend)
                Tpend <= pswT;
            else if (wNanoDec_t4.clrTpend)
                Tpend <= 1'b0;

            // UNIQUE IF !!
            if (wNanoDec_t4.ftu2Sr & !irdToCcr_t4) begin
                { pswT, pswS, pswI } <= { rFtu_t3[15], rFtu_t3[13], rFtu_t3[10:8]};
            end
            else begin
                if (wNanoDec_t4.initST) begin
                    pswS <= 1'b1;
                    pswT <= 1'b0;
                end
                if (wNanoDec_t4.inl2psw) begin
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
        if (wNanoDec_t3.updSsw & enT3) begin
            ssw <= { ~bciWrite, inExcept01, rFC};
        end

        // Update TVN on T1 & IR=>IRD
        if (enT1 & wNanoDec_t3.Ir2Ird) begin
            tvnLatch <= tvn;
            inExcept01 <= (tvn != 4'h1);
        end

        if (Clks.pwrUp) begin
            rFtu_t3 <= 16'h0000;
        end
        else if (enT3) begin
            unique case (1'b1)
                wNanoDec_t4.tvn2Ftu:   rFtu_t3 <= tvnMux;

                // 0 on unused bits seem to come from ftuConst PLA previously clearing FBUS
                wNanoDec_t4.sr2Ftu:    rFtu_t3 <= {pswT, 1'b0, pswS, 2'b00, pswI, 3'b000, ccr[4:0] };

                wNanoDec_t4.ird2Ftu:   rFtu_t3 <= rIrd_t1;
                wNanoDec_t4.ssw2Ftu:   rFtu_t3[4:0] <= ssw;               // Undoc. Other bits must be preserved from IRD saved above!
                wNanoDec_t4.pswIToFtu: rFtu_t3 <= { 12'hFFF, pswI, 1'b0}; // Interrupt level shifted
                wNanoDec_t4.const2Ftu: rFtu_t3 <= wIrdDecode_t1.ftuConst;
                wNanoDec_t4.abl2Pren:  rFtu_t3 <= wAbl_t2;                    // From ALU or datareg. Used for SR modify
                default:               rFtu_t3 <= rFtu_t3;
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
                tvnMux = { 6'b0, rIrd_t1[7:0], 2'b0 };               // Interrupt vector was read and transferred to IRD
            else
                tvnMux = { 10'b0, tvnLatch, 2'b0 };
        end
        else begin
            tvnMux = { 8'h0, wIrdDecode_t1.macroTvn, 2'b0 };
        end
    end

endmodule

// Nanorom (plus) decoder for die nanocode
module nDecoder3
(
    input                   clk,
    input                   enT2,
    input                   enT4,
    input  [NANO_WIDTH-1:0] iNanoLatch_t3,
    input         s_irdecod iIrdDecode_t1,
    output        s_nanod_r oNanoDec_t4,
    output        s_nanod_w oNanoDec_t3
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

    wire [3:0] ftuCtrl = iNanoLatch_t3[NANO_FTUCONTROL +: 4];
    wire [2:0] athCtrl = iNanoLatch_t3[NANO_ATHCTRL +: 3];
    wire [2:0] atlCtrl = iNanoLatch_t3[NANO_ATLCTRL +: 3];
    wire [1:0] aobCtrl = iNanoLatch_t3[NANO_AOBCTRL +: 2];
    wire [1:0] dobCtrl = { iNanoLatch_t3[NANO_DOBCTRL_1], iNanoLatch_t3[NANO_DOBCTRL_0] };

    always_ff @(posedge clk) begin

        if (enT4) begin

            oNanoDec_t4.updTpend  <= (ftuCtrl == NANO_FTU_UPDTPEND) ? 1'b1 : 1'b0;
            oNanoDec_t4.clrTpend  <= (ftuCtrl == NANO_FTU_CLRTPEND) ? 1'b1 : 1'b0;
            oNanoDec_t4.tvn2Ftu   <= (ftuCtrl == NANO_FTU_TVN)      ? 1'b1 : 1'b0;
            oNanoDec_t4.const2Ftu <= (ftuCtrl == NANO_FTU_CONST)    ? 1'b1 : 1'b0;
            oNanoDec_t4.ftu2Dbl   <= (ftuCtrl == NANO_FTU_DBL)
                                  || (ftuCtrl == NANO_FTU_INL)      ? 1'b1 : 1'b0;
            oNanoDec_t4.ftu2Abl   <= (ftuCtrl == NANO_FTU_2ABL)     ? 1'b1 : 1'b0;
            oNanoDec_t4.abl2Pren  <= (ftuCtrl == NANO_FTU_ABL2PREN) ? 1'b1 : 1'b0;
            oNanoDec_t4.updPren   <= (ftuCtrl == NANO_FTU_RSTPREN)  ? 1'b1 : 1'b0;
            oNanoDec_t4.inl2psw   <= (ftuCtrl == NANO_FTU_INL)      ? 1'b1 : 1'b0;
            oNanoDec_t4.ftu2Sr    <= (ftuCtrl == NANO_FTU_2SR)      ? 1'b1 : 1'b0;
            oNanoDec_t4.sr2Ftu    <= (ftuCtrl == NANO_FTU_RDSR)     ? 1'b1 : 1'b0;
            oNanoDec_t4.pswIToFtu <= (ftuCtrl == NANO_FTU_PSWI)     ? 1'b1 : 1'b0;
            oNanoDec_t4.ird2Ftu   <= (ftuCtrl == NANO_FTU_IRD)      ? 1'b1 : 1'b0; // Used on bus/addr error
            oNanoDec_t4.ssw2Ftu   <= (ftuCtrl == NANO_FTU_SSW)      ? 1'b1 : 1'b0;
            oNanoDec_t4.initST    <= (ftuCtrl == NANO_FTU_INL)
                                  || (ftuCtrl == NANO_FTU_CLRTPEND)
                                  || (ftuCtrl == NANO_FTU_INIT_ST)  ? 1'b1 : 1'b0;

            oNanoDec_t4.auClkEn   <= ~iNanoLatch_t3[NANO_AUCLKEN];
            oNanoDec_t4.auCntrl   <=  iNanoLatch_t3[NANO_AUCTRL +: 3];
            oNanoDec_t4.noSpAlign <= &iNanoLatch_t3[NANO_NO_SP_ALGN +: 2];
            oNanoDec_t4.extDbh    <=  iNanoLatch_t3[NANO_EXT_DBH];
            oNanoDec_t4.extAbh    <=  iNanoLatch_t3[NANO_EXT_ABH];
            oNanoDec_t4.todbin    <=  iNanoLatch_t3[NANO_TODBIN];
            oNanoDec_t4.toIrc     <=  iNanoLatch_t3[NANO_TOIRC];

            // ablAbd is disabled on byte transfers (adbhCharge plus irdIsByte). Not sure the combination makes much sense.
            // It happens in a few cases but I don't see anything enabled on abL (or abH) section anyway.

            oNanoDec_t4.ablAbd    <= iNanoLatch_t3[NANO_ABLABD];
            oNanoDec_t4.ablAbh    <= iNanoLatch_t3[NANO_ABLABH];
            oNanoDec_t4.dblDbd    <= iNanoLatch_t3[NANO_DBLDBD];
            oNanoDec_t4.dblDbh    <= iNanoLatch_t3[NANO_DBLDBH];

            oNanoDec_t4.dbl2Atl   <= (atlCtrl[2:0] == 3'b010) ? 1'b1 : 1'b0;
            oNanoDec_t4.atl2Dbl   <= (atlCtrl[2:0] == 3'b011) ? 1'b1 : 1'b0;
            oNanoDec_t4.abl2Atl   <= (atlCtrl[2:0] == 3'b100) ? 1'b1 : 1'b0;
            oNanoDec_t4.atl2Abl   <= (atlCtrl[2:0] == 3'b101) ? 1'b1 : 1'b0;

            oNanoDec_t4.aob2Ab    <= (athCtrl[2:0] == 3'b101) ? 1'b1 : 1'b0; // Used on BSER1 only

            oNanoDec_t4.abh2Ath   <= (athCtrl[1:0] == 2'b01 ) ? 1'b1 : 1'b0;
            oNanoDec_t4.dbh2Ath   <= (athCtrl[2:0] == 3'b100) ? 1'b1 : 1'b0;
            oNanoDec_t4.ath2Dbh   <= (athCtrl[2:0] == 3'b110) ? 1'b1 : 1'b0;
            oNanoDec_t4.ath2Abh   <= (athCtrl[2:0] == 3'b011) ? 1'b1 : 1'b0;

            oNanoDec_t4.alu2Dbd   <= iNanoLatch_t3[NANO_ALU2DBD];
            oNanoDec_t4.alu2Abd   <= iNanoLatch_t3[NANO_ALU2ABD];
            oNanoDec_t4.dbin2Dbd  <= iNanoLatch_t3[NANO_DBIN2DBD];
            oNanoDec_t4.dbin2Abd  <= iNanoLatch_t3[NANO_DBIN2ABD];
            oNanoDec_t4.au2Db     <= oNanoDec_t3.au2Db;
            oNanoDec_t4.au2Ab     <= oNanoDec_t3.au2Ab;

            oNanoDec_t4.abd2Dcr   <= (iNanoLatch_t3[NANO_DCR+0 +: 2]  == 2'b11) ? 1'b1 : 1'b0;
            oNanoDec_t4.dcr2Dbd   <= (iNanoLatch_t3[NANO_DCR+1 +: 2]  == 2'b11) ? 1'b1 : 1'b0;
            oNanoDec_t4.dbd2Alue  <= (iNanoLatch_t3[NANO_ALUE+1 +: 2] == 2'b10) ? 1'b1 : 1'b0;
            oNanoDec_t4.alue2Dbd  <= (iNanoLatch_t3[NANO_ALUE+0 +: 2] == 2'b01) ? 1'b1 : 1'b0;

            oNanoDec_t4.dbd2Alub  <= iNanoLatch_t3[NANO_DBD2ALUB];
            oNanoDec_t4.abd2Alub  <= iNanoLatch_t3[NANO_ABD2ALUB];

            // Originally not latched. We better should because we transfer one cycle later, T3 instead of T1.
            oNanoDec_t4.dobCtrl   <= dobCtrl;
            // oNanoDec_t4.adb2Dob <= (dobCtrl == 2'b10);
            // oNanoDec_t4.dbd2Dob <= (dobCtrl == 2'b01);
            // oNanoDec_t4.alu2Dob <= (dobCtrl == 2'b11);

            // Might be better not to register these signals to allow latching RX/RY mux earlier!
            // But then must latch iIrdDecode_t1.isPcRel on T3!

            oNanoDec_t4.rxl2db  <= oNanoDec_t3.reg2dbl & ~dblSpecial &  iNanoLatch_t3[NANO_RXL_DBL];
            oNanoDec_t4.rxl2ab  <= oNanoDec_t3.reg2abl & ~ablSpecial & ~iNanoLatch_t3[NANO_RXL_DBL];

            oNanoDec_t4.dbl2rxl <= oNanoDec_t3.dbl2reg & ~dblSpecial &  iNanoLatch_t3[NANO_RXL_DBL];
            oNanoDec_t4.abl2rxl <= oNanoDec_t3.abl2reg & ~ablSpecial & ~iNanoLatch_t3[NANO_RXL_DBL];

            oNanoDec_t4.rxh2dbh <= oNanoDec_t3.reg2dbh & ~dbhSpecial &  iNanoLatch_t3[NANO_RXH_DBH];
            oNanoDec_t4.rxh2abh <= oNanoDec_t3.reg2abh & ~abhSpecial & ~iNanoLatch_t3[NANO_RXH_DBH];

            oNanoDec_t4.dbh2rxh <= oNanoDec_t3.dbh2reg & ~dbhSpecial &  iNanoLatch_t3[NANO_RXH_DBH];
            oNanoDec_t4.abh2rxh <= oNanoDec_t3.abh2reg & ~abhSpecial & ~iNanoLatch_t3[NANO_RXH_DBH];

            oNanoDec_t4.dbh2ryh <= oNanoDec_t3.dbh2reg & ~dbhSpecial & ~iNanoLatch_t3[NANO_RXH_DBH];
            oNanoDec_t4.abh2ryh <= oNanoDec_t3.abh2reg & ~abhSpecial &  iNanoLatch_t3[NANO_RXH_DBH];

            oNanoDec_t4.dbl2ryl <= oNanoDec_t3.dbl2reg & ~dblSpecial & ~iNanoLatch_t3[NANO_RXL_DBL];
            oNanoDec_t4.abl2ryl <= oNanoDec_t3.abl2reg & ~ablSpecial &  iNanoLatch_t3[NANO_RXL_DBL];

            oNanoDec_t4.ryl2db  <= oNanoDec_t3.reg2dbl & ~dblSpecial & ~iNanoLatch_t3[NANO_RXL_DBL];
            oNanoDec_t4.ryl2ab  <= oNanoDec_t3.reg2abl & ~ablSpecial &  iNanoLatch_t3[NANO_RXL_DBL];

            oNanoDec_t4.ryh2dbh <= oNanoDec_t3.reg2dbh & ~dbhSpecial & ~iNanoLatch_t3[NANO_RXH_DBH];
            oNanoDec_t4.ryh2abh <= oNanoDec_t3.reg2abh & ~abhSpecial &  iNanoLatch_t3[NANO_RXH_DBH];

            // Originally isTas only delayed on T2 (and seems only a late mask rev fix)
            // Better latch the combination on T4
            oNanoDec_t4.isRmc   <= iIrdDecode_t1.isTas & iNanoLatch_t3[NANO_BUSBYTE];
        end
    end

    // Update SSW at the start of Bus/Addr error ucode
    assign oNanoDec_t3.updSsw    = oNanoDec_t4.aob2Ab;


    assign oNanoDec_t3.Ir2Ird    = iNanoLatch_t3[NANO_IR2IRD];

    // ALU control better latched later after combining with IRD decoding

    wire [1:0] aluFinInit = iNanoLatch_t3[NANO_ALU_FI +: 2];

    assign oNanoDec_t3.aluDctrl      = iNanoLatch_t3[NANO_ALU_DCTRL +: 2];
    assign oNanoDec_t3.aluActrl      = iNanoLatch_t3[NANO_ALU_ACTRL];
    assign oNanoDec_t3.aluColumn     = { iNanoLatch_t3[ NANO_ALU_COL], iNanoLatch_t3[ NANO_ALU_COL+1], iNanoLatch_t3[ NANO_ALU_COL+2]};
    assign oNanoDec_t3.aluFinish     = (aluFinInit == 2'b10) ? 1'b1 : 1'b0;
    assign oNanoDec_t3.aluInit       = (aluFinInit == 2'b01) ? 1'b1 : 1'b0;

    // FTU 2 CCR encoded as both ALU Init and ALU Finish set.
    // In theory this encoding allows writes to CCR without writing to SR
    // But FTU 2 CCR and to SR are both set together at nanorom.
    assign oNanoDec_t3.ftu2Ccr       = (aluFinInit == 2'b11) ? 1'b1 : 1'b0;

    assign oNanoDec_t3.abdIsByte     = iNanoLatch_t3[NANO_ABDHRECHARGE];

    // Not being latched on T4 creates non unique case warning!
    assign oNanoDec_t3.au2Db         = (iNanoLatch_t3[NANO_AUOUT +: 2] == 2'b01) ? 1'b1 : 1'b0;
    assign oNanoDec_t3.au2Ab         = (iNanoLatch_t3[NANO_AUOUT +: 2] == 2'b10) ? 1'b1 : 1'b0;
    assign oNanoDec_t3.au2Pc         = (iNanoLatch_t3[NANO_AUOUT +: 2] == 2'b11) ? 1'b1 : 1'b0;

    assign oNanoDec_t3.db2Aob        = (aobCtrl == 2'b10) ? 1'b1 : 1'b0;
    assign oNanoDec_t3.ab2Aob        = (aobCtrl == 2'b01) ? 1'b1 : 1'b0;
    assign oNanoDec_t3.au2Aob        = (aobCtrl == 2'b11) ? 1'b1 : 1'b0;

    //assign oNanoDec_t3.dbin2Abd      = iNanoLatch_t3[NANO_DBIN2ABD];
    //assign oNanoDec_t3.dbin2Dbd      = iNanoLatch_t3[NANO_DBIN2DBD];

    assign oNanoDec_t3.permStart     = (aobCtrl != 2'b00) ? 1'b1 : 1'b0;
    assign oNanoDec_t3.isWrite       = iNanoLatch_t3[NANO_DOBCTRL_1]
                                     | iNanoLatch_t3[NANO_DOBCTRL_0];
    assign oNanoDec_t3.waitBusFinish = iNanoLatch_t3[NANO_DOBCTRL_1]
                                     | iNanoLatch_t3[NANO_DOBCTRL_0]
                                     | iNanoLatch_t3[NANO_TOIRC]
                                     | iNanoLatch_t3[NANO_TODBIN];
    assign oNanoDec_t3.busByte       = iNanoLatch_t3[NANO_BUSBYTE];

    assign oNanoDec_t3.noLowByte     = iNanoLatch_t3[NANO_LOWBYTE];
    assign oNanoDec_t3.noHighByte    = iNanoLatch_t3[NANO_HIGHBYTE];

    // Not registered. Register at T4 after combining
    // Might be better to remove all those and combine here instead of at execution unit !!
    assign oNanoDec_t3.abl2reg       = iNanoLatch_t3[NANO_ABL2REG];
    assign oNanoDec_t3.abh2reg       = iNanoLatch_t3[NANO_ABH2REG];
    assign oNanoDec_t3.dbl2reg       = iNanoLatch_t3[NANO_DBL2REG];
    assign oNanoDec_t3.dbh2reg       = iNanoLatch_t3[NANO_DBH2REG];
    assign oNanoDec_t3.reg2dbl       = iNanoLatch_t3[NANO_REG2DBL];
    assign oNanoDec_t3.reg2dbh       = iNanoLatch_t3[NANO_REG2DBH];
    assign oNanoDec_t3.reg2abl       = iNanoLatch_t3[NANO_REG2ABL];
    assign oNanoDec_t3.reg2abh       = iNanoLatch_t3[NANO_REG2ABH];

    assign oNanoDec_t3.ssp           = iNanoLatch_t3[NANO_SSP];

    assign oNanoDec_t3.rz            = iNanoLatch_t3[NANO_RZ];

    // Actually DTL can't happen on PC relative mode. See IR decoder.

    wire dtldbd = 1'b0;
    wire dthdbh = 1'b0;
    wire dtlabd = 1'b0;
    wire dthabh = 1'b0;

    wire dblSpecial = oNanoDec_t3.pcldbl | dtldbd;
    wire dbhSpecial = oNanoDec_t3.pchdbh | dthdbh;
    wire ablSpecial = oNanoDec_t3.pclabl | dtlabd;
    wire abhSpecial = oNanoDec_t3.pchabh | dthabh;

    //
    // Combine with IRD decoding
    // Careful that IRD is updated only on T1! All output depending on IRD must be latched on T4!
    //

    // PC used instead of RY on PC relative instuctions

    assign oNanoDec_t3.rxlDbl = iNanoLatch_t3[NANO_RXL_DBL];
    wire isPcRel  = iIrdDecode_t1.isPcRel & ~iNanoLatch_t3[NANO_RZ];
    wire pcRelDbl = isPcRel & ~iNanoLatch_t3[NANO_RXL_DBL];
    wire pcRelDbh = isPcRel & ~iNanoLatch_t3[NANO_RXH_DBH];
    wire pcRelAbl = isPcRel &  iNanoLatch_t3[NANO_RXL_DBL];
    wire pcRelAbh = isPcRel &  iNanoLatch_t3[NANO_RXH_DBH];

    assign oNanoDec_t3.pcldbl = iNanoLatch_t3[NANO_PCLDBL] | pcRelDbl;
    assign oNanoDec_t3.pchdbh = (iNanoLatch_t3[NANO_PCH +: 2] == 2'b01) ? 1'b1 : pcRelDbh;

    assign oNanoDec_t3.pclabl = iNanoLatch_t3[NANO_PCLABL] | pcRelAbl;
    assign oNanoDec_t3.pchabh = (iNanoLatch_t3[NANO_PCH +: 2] == 2'b10) ? 1'b1 : pcRelAbh;

endmodule

//
// IRD execution decoder. Complements nano code decoder
//
// IRD updated on T1, while ncode still executing. To avoid using the next IRD,
// decoded signals must be registered on T3, or T4 before using them.
//
module irdDecode
(
    input     [15:0] iIrd_t1,
    input     [15:0] iIrdL_t1,
    output s_irdecod oIrdDecode_t1
);

    reg  implicitSp;
    wire isRegShift = (iIrdL_t1[4'hE]) & (iIrd_t1[7:6] != 2'b11);
    wire isDynShift = isRegShift & iIrd_t1[5];
    wire isTas      = (iIrd_t1[11:6] == 6'b101011) ? iIrdL_t1[4'h4] : 1'b0;

    assign oIrdDecode_t1.isPcRel = (&iIrd_t1[5:3]) & ~isDynShift & !iIrd_t1[2] & iIrd_t1[1];
    assign oIrdDecode_t1.isTas   = isTas;

    assign oIrdDecode_t1.rx = iIrd_t1[11:9];
    assign oIrdDecode_t1.ry = iIrd_t1[ 2:0];

    wire isPreDecr = (iIrd_t1[5:3] == 3'b100) ? 1'b1 : 1'b0;
    wire eaAreg    = (iIrd_t1[5:3] == 3'b001) ? 1'b1 : 1'b0;

    // rx is A or D
    // movem
    always_comb begin
        unique case (1'b1)
            iIrdL_t1[4'h1],
            iIrdL_t1[4'h2],
            iIrdL_t1[4'h3]:
                // MOVE: RX always Areg except if dest mode is Dn 000
                oIrdDecode_t1.rxIsAreg = (|iIrd_t1[8:6]);

            iIrdL_t1[4'h4]:
                // not CHK (LEA)
                oIrdDecode_t1.rxIsAreg = (&iIrd_t1[8:6]);

            iIrdL_t1[4'h8]:
                // SBCD
                oIrdDecode_t1.rxIsAreg = eaAreg & iIrd_t1[8] & ~iIrd_t1[7];

            iIrdL_t1[4'hC]:
                // ABCD/EXG An,An
                oIrdDecode_t1.rxIsAreg = eaAreg & iIrd_t1[8] & ~iIrd_t1[7];

            iIrdL_t1[4'h9],
            iIrdL_t1[4'hB],
            iIrdL_t1[4'hD]:
                oIrdDecode_t1.rxIsAreg =
                    (iIrd_t1[7] & iIrd_t1[6]) |                      // SUBA/CMPA/ADDA
                    (eaAreg & iIrd_t1[8] & (iIrd_t1[7:6] != 2'b11)); // SUBX/CMPM/ADDX
            default:
                oIrdDecode_t1.rxIsAreg = implicitSp;
        endcase
    end

    // RX is movem
    assign oIrdDecode_t1.rxIsMovem    = iIrdL_t1[4'h4] & ~iIrd_t1[8] & ~implicitSp;
    assign oIrdDecode_t1.movemPreDecr = iIrdL_t1[4'h4] & ~iIrd_t1[8] & ~implicitSp & isPreDecr;

    // RX is DT.
    // but SSP explicit or pc explicit has higher priority!
    // addq/subq (scc & dbcc also, but don't use rx)
    // Immediate including static bit
    assign oIrdDecode_t1.rxIsDt = iIrdL_t1[4'h5] | (iIrdL_t1[4'h0] & ~iIrd_t1[8]);

    // RX is USP (16'h4E6x)
    assign oIrdDecode_t1.rxIsUsp = iIrdL_t1[4'h4] & (iIrd_t1[11:4] == 8'hE6);

    // RY is DT
    // rz or PC explicit has higher priority

    wire eaImmOrAbs = (iIrd_t1[5:3] == 3'b111) & ~iIrd_t1[1];
    assign oIrdDecode_t1.ryIsDt = eaImmOrAbs & ~isRegShift;

    // RY is Address register
    always_comb begin
        logic eaIsAreg;

        // On most cases RY is Areg expect if mode is 000 (DATA REG) or 111 (IMM, ABS,PC REL)
        eaIsAreg = (iIrd_t1[5:3] != 3'b000) & (iIrd_t1[5:3] != 3'b111);

        unique case (1'b1)
            // MOVE: RY always Areg expect if mode is 000 (DATA REG) or 111 (IMM, ABS,PC REL)
            // Most lines, including misc line 4, also.
            default:
                oIrdDecode_t1.ryIsAreg = eaIsAreg;

            iIrdL_t1[4'h5]:
                // DBcc is an exception
                oIrdDecode_t1.ryIsAreg = eaIsAreg & (iIrd_t1[7:3] != 5'b11001);

            iIrdL_t1[4'h6],
            iIrdL_t1[4'h7]:
                oIrdDecode_t1.ryIsAreg = 1'b0;

            iIrdL_t1[4'hE]:
                oIrdDecode_t1.ryIsAreg = ~isRegShift;
        endcase
    end

    // Byte sized instruction

    // Original implementation sets this for some instructions that aren't really byte size
    // but doesn't matter because they don't have a byte transfer enabled at nanocode, such as MOVEQ

    wire xIsScc     = (iIrd_t1[7:6] == 2'b11) & (iIrd_t1[5:3] != 3'b001);
    wire xStaticMem = (iIrd_t1[11:8] == 4'b1000) & (iIrd_t1[5:4] == 2'b00);     // Static bit to mem
    always_comb begin
        unique case (1'b1)
            iIrdL_t1[4'h0]:
                oIrdDecode_t1.isByte =
                ( iIrd_t1[8] & (iIrd_t1[5:4] != 2'b00)                  ) | // Dynamic bit to mem
                ( (iIrd_t1[11:8] == 4'b1000) & (iIrd_t1[5:4] != 2'b00)  ) | // Static bit to mem
                ( (iIrd_t1[8:7] == 2'b10) & (iIrd_t1[5:3] == 3'b001)    ) | // Movep from mem only! For byte mux
                ( (iIrd_t1[8:6] == 3'b000) & !xStaticMem );             // Immediate byte

            iIrdL_t1[4'h1]:
                oIrdDecode_t1.isByte = 1'b1;      // MOVE.B


            iIrdL_t1[4'h4]:
                oIrdDecode_t1.isByte = (iIrd_t1[7:6] == 2'b00) ? 1'b1 : isTas;

            iIrdL_t1[4'h5]:
                oIrdDecode_t1.isByte = (iIrd_t1[7:6] == 2'b00) ? 1'b1 : xIsScc;

            iIrdL_t1[4'h8],
            iIrdL_t1[4'h9],
            iIrdL_t1[4'hB],
            iIrdL_t1[4'hC],
            iIrdL_t1[4'hD],
            iIrdL_t1[4'hE]:
                oIrdDecode_t1.isByte = (iIrd_t1[7:6] == 2'b00) ? 1'b1 : 1'b0;

            default:
                oIrdDecode_t1.isByte = 1'b0;
        endcase
    end

    // Need it for special byte size. Bus is byte, but whole register word is modified.
    assign oIrdDecode_t1.isMovep = iIrdL_t1[4'h0] & iIrd_t1[8] & eaAreg;


    // rxIsSP implicit use of RX for actual SP transfer
    //
    // This logic is simple and will include some instructions that don't actually reference SP.
    // But doesn't matter as long as they don't perform any RX transfer.

    always_comb begin
        unique case (1'b1)
            iIrdL_t1[4'h6]:
                // BSR
                implicitSp = (iIrd_t1[11:8] == 4'b0001) ? 1'b1 : 1'b0;
            iIrdL_t1[4'h4]:
                // Misc like RTS, JSR, etc
                implicitSp = (iIrd_t1[11:8] == 4'b1110) | (iIrd_t1[11:6] == 6'b1000_01);
            default:
                implicitSp = 1'b0;
        endcase
    end
    assign oIrdDecode_t1.implicitSp = implicitSp;

    // Modify CCR (and not SR)
    // Probably overkill !! Only needs to distinguish SR vs CCR
    // RTR, MOVE to CCR, xxxI to CCR
    assign oIrdDecode_t1.toCcr =  ( iIrdL_t1[4'h4] & ((iIrd_t1[11:0] == 12'he77) | (iIrd_t1[11:6] == 6'b010011)) ) |
                            ( iIrdL_t1[4'h0] & (iIrd_t1[8:6] == 3'b000));

    // FTU constants
    // This should not be latched on T3/T4. Latch on T2 or not at all. FTU needs it on next T3.
    // Note: Reset instruction gets constant from ALU not from FTU!
    logic [15:0] ftuConst;
    wire [3:0] zero28 = (iIrd_t1[11:9] == 0) ? 4'h8 : { 1'b0, iIrd_t1[11:9]};       // xltate 0,1-7 into 8,1-7

    always_comb begin
        unique case (1'b1)
            iIrdL_t1[4'h6], // Bcc short
            iIrdL_t1[4'h7]: // MOVEQ
                ftuConst = { {8{iIrd_t1[7]}}, iIrd_t1[7:0] };

            // ADDQ/SUBQ/static shift double check this
            iIrdL_t1[4'h5],
            iIrdL_t1[4'hE]:
                ftuConst = { 12'h000, zero28};

            // MULU/MULS DIVU/DIVS
            iIrdL_t1[4'h8],
            iIrdL_t1[4'hC]:
                ftuConst = 16'h000F;

            // TAS
            iIrdL_t1[4'h4]:
                ftuConst = 16'h0080;

            default:
                ftuConst = 16'h0000;
        endcase
    end
    assign oIrdDecode_t1.ftuConst = ftuConst;

    //
    // TRAP Vector # for group 2 exceptions
    //

    always_comb begin
        if (iIrdL_t1[4'h4]) begin
            case (iIrd_t1[6:5])
                2'b00,
                2'b01:
                    oIrdDecode_t1.macroTvn = 6'h6;                // CHK
                2'b11:
                    oIrdDecode_t1.macroTvn = 6'h7;                // TRAPV
                2'b10:
                    oIrdDecode_t1.macroTvn = { 2'b10, iIrd_t1[3:0] }; // TRAP
            endcase
        end
        else begin
            oIrdDecode_t1.macroTvn = 6'h5; // Division by zero
        end
    end


    wire eaAdir = (iIrd_t1[ 5:3] == 3'b001);
    wire size11 = iIrd_t1[7] & iIrd_t1[6];

    // Opcodes variants that don't affect flags
    // ADDA/SUBA ADDQ/SUBQ MOVEA

    assign oIrdDecode_t1.inhibitCcr =
        ( (iIrdL_t1[4'h9] | iIrdL_t1[4'hD]) & size11) |                // ADDA/SUBA
        ( iIrdL_t1[4'h5] & eaAdir) |                                   // ADDQ/SUBQ to An (originally checks for line[4] as well !?)
        ( (iIrdL_t1[4'h2] | iIrdL_t1[4'h3]) & iIrd_t1[8:6] == 3'b001); // MOVEA

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
    input s_nanod_r iNanoDec_t4,
    input s_nanod_w iNanoDec_t3,
    input s_irdecod iIrdDecode_t1,
    input [15:0] Ird,           // ALU row (and others) decoder needs it
    input pswS,
    input [15:0] iFtu_t3,
    input [15:0] iEdb,

    output logic [7:0] ccr,
    output [15:0] alue,

    output prenEmpty, au05z,
    output logic dcr4, ze,
    output logic aob0,
    output [15:0] oAbl_t2,
    output logic [15:0] oIrc_t4,
    output logic [15:0] oEdb,
    output logic [31:1] eab
);

localparam
    REG_USP = 15,
    REG_SSP = 16,
    REG_DT  = 17;

`ifdef verilator3
    // For simulation display only
    wire [31:0] dbg_D0 =  { U_fx68kRegs.ram_L[0],       U_fx68kRegs.ram_W[0],       U_fx68kRegs.ram_B[0]       };
    wire [31:0] dbg_D1 =  { U_fx68kRegs.ram_L[1],       U_fx68kRegs.ram_W[1],       U_fx68kRegs.ram_B[1]       };
    wire [31:0] dbg_D2 =  { U_fx68kRegs.ram_L[2],       U_fx68kRegs.ram_W[2],       U_fx68kRegs.ram_B[2]       };
    wire [31:0] dbg_D3 =  { U_fx68kRegs.ram_L[3],       U_fx68kRegs.ram_W[3],       U_fx68kRegs.ram_B[3]       };
    wire [31:0] dbg_D4 =  { U_fx68kRegs.ram_L[4],       U_fx68kRegs.ram_W[4],       U_fx68kRegs.ram_B[4]       };
    wire [31:0] dbg_D5 =  { U_fx68kRegs.ram_L[5],       U_fx68kRegs.ram_W[5],       U_fx68kRegs.ram_B[5]       };
    wire [31:0] dbg_D6 =  { U_fx68kRegs.ram_L[6],       U_fx68kRegs.ram_W[6],       U_fx68kRegs.ram_B[6]       };
    wire [31:0] dbg_D7 =  { U_fx68kRegs.ram_L[7],       U_fx68kRegs.ram_W[7],       U_fx68kRegs.ram_B[7]       };
    wire [31:0] dbg_A0 =  { U_fx68kRegs.ram_L[8],       U_fx68kRegs.ram_W[8],       U_fx68kRegs.ram_B[8]       };
    wire [31:0] dbg_A1 =  { U_fx68kRegs.ram_L[9],       U_fx68kRegs.ram_W[9],       U_fx68kRegs.ram_B[9]       };
    wire [31:0] dbg_A2 =  { U_fx68kRegs.ram_L[10],      U_fx68kRegs.ram_W[10],      U_fx68kRegs.ram_B[10]      };
    wire [31:0] dbg_A3 =  { U_fx68kRegs.ram_L[11],      U_fx68kRegs.ram_W[11],      U_fx68kRegs.ram_B[11]      };
    wire [31:0] dbg_A4 =  { U_fx68kRegs.ram_L[12],      U_fx68kRegs.ram_W[12],      U_fx68kRegs.ram_B[12]      };
    wire [31:0] dbg_A5 =  { U_fx68kRegs.ram_L[13],      U_fx68kRegs.ram_W[13],      U_fx68kRegs.ram_B[13]      };
    wire [31:0] dbg_A6 =  { U_fx68kRegs.ram_L[14],      U_fx68kRegs.ram_W[14],      U_fx68kRegs.ram_B[14]      };
    wire [31:0] dbg_USP = { U_fx68kRegs.ram_L[REG_USP], U_fx68kRegs.ram_W[REG_USP], U_fx68kRegs.ram_B[REG_USP] };
    wire [31:0] dbg_SSP = { U_fx68kRegs.ram_L[REG_SSP], U_fx68kRegs.ram_W[REG_SSP], U_fx68kRegs.ram_B[REG_SSP] };
    wire [31:0] dbg_DT  = { U_fx68kRegs.ram_L[REG_DT],  U_fx68kRegs.ram_W[REG_DT],  U_fx68kRegs.ram_B[REG_DT]  };
    wire [31:0] dbg_PC =  { PcH, PcL };
`endif


    wire [15:0] aluOut;
    wire [15:0] wDbin_t4;
    logic [15:0] dcrOutput;

    reg [15:0] PcL, PcH;

    reg [31:0] rAuReg_t3, aob;

    reg [15:0] rAth_t3;
    reg [15:0] rAtl_t3;

    // Bus execution
    reg [15:0] rDbl_t2, rDbh_t2;
    reg [15:0] rAbh_t2, rAbl_t2;
    reg [15:0] rAbd_t2, rDbd_t2;

    assign oAbl_t2 = rAbl_t2;
    assign au05z = (~| rAuReg_t3[5:0]);

    // RX RY muxes
    // RX and RY actual registers
    reg  [3:0] rMovemRx_t3;
    reg        rRxIsMovem_t3;
    reg        rMovemRxIsSp_t3;
    logic byteNotSpAlign;           // Byte instruction and no sp word align

    // IRD decoded signals must be latched. See comments on decoder
    // But nanostore decoding can't be latched before T4.
    //
    // If we need this earlier we can register IRD decode on T3 and use nano async

    reg   [4:0] rRxMux_t3;
    reg         rRxIsSp_t3;

    reg   [4:0] rRyMux_t3;
    reg         rRyIsSp_t3;
    
    // Pre-computation for wRxMux_t3 and wRyMux_t3
    always_ff @(posedge clk) begin
        reg [3:0] vTmp;
    
        if (enT3) begin
            if (iIrdDecode_t1.rxIsUsp) begin
                rRxMux_t3  <= REG_USP[4:0];
                rRxIsSp_t3 <= 1'b1;
            end
            else if (iIrdDecode_t1.implicitSp) begin
                rRxMux_t3  <= (pswS) ? REG_SSP[4:0] : REG_USP[4:0];
                rRxIsSp_t3 <= 1'b1;
            end
            else if (iIrdDecode_t1.rxIsDt) begin
                rRxMux_t3  <= REG_DT[4:0];
                rRxIsSp_t3 <= 1'b0;
            end
            else if (!iIrdDecode_t1.rxIsMovem) begin
                vTmp = { iIrdDecode_t1.rxIsAreg, iIrdDecode_t1.rx};
                if (&vTmp) begin
                    rRxMux_t3  <= (pswS) ? REG_SSP[4:0] : { 1'b0, vTmp };
                    rRxIsSp_t3 <= 1'b1;
                end
                else begin
                    rRxMux_t3  <= { 1'b0, vTmp };
                    rRxIsSp_t3 <= 1'b0;
                end
            end
            
            if (iIrdDecode_t1.ryIsDt) begin
                rRyMux_t3  <= REG_DT[4:0];
                rRyIsSp_t3 <= 1'b0;
            end
            else begin
                vTmp = { iIrdDecode_t1.ryIsAreg, iIrdDecode_t1.ry };
                if (&vTmp) begin
                    rRyMux_t3  <= (pswS) ? REG_SSP[4:0] : { 1'b0, vTmp };
                    rRyIsSp_t3 <= 1'b1;
                end
                else begin
                    rRyMux_t3  <= { 1'b0, vTmp };
                    rRyIsSp_t3 <= 1'b0;
                end
            end
        end
    end
    
    logic [4:0] wRxMux_t3;
    logic       wRxIsSp_t3;

    logic [4:0] wRyMux_t3;
    logic       wRyIsSp_t3;

    always_comb begin : RX_IDX_T3
        if (iNanoDec_t3.ssp) begin
            wRxMux_t3  = REG_SSP[4:0];
            wRxIsSp_t3 = 1'b1;
        end
        else if (rRxIsMovem_t3) begin
            wRxMux_t3  = (pswS & rMovemRxIsSp_t3) ? REG_SSP[4:0] : { 1'b0, rMovemRx_t3 };
            wRxIsSp_t3 = rMovemRxIsSp_t3;
        end
        else begin
            wRxMux_t3  = rRxMux_t3;
            wRxIsSp_t3 = rRxIsSp_t3;
        end
    end

    always_comb begin : RY_IDX_T3
        if (iNanoDec_t3.rz) begin
            wRyIsSp_t3 = &oIrc_t4[15:12];
            if (wRyIsSp_t3 & pswS)
                wRyMux_t3 = REG_SSP[4:0];
            else
                wRyMux_t3 = { 1'b0, oIrc_t4[15:12] };
        end
        else begin
            wRyMux_t3  = rRyMux_t3;
            wRyIsSp_t3 = rRyIsSp_t3;
        end
    end

    wire [31:0] wRx_t4;
    wire [31:0] wRy_t4;
    reg         rRxIsAreg_t4;
    reg         rRyIsAreg_t4;
    
    reg         rAbdIsByte_t4;

    always_ff @(posedge clk) begin
    
        if (enT4) begin
            byteNotSpAlign <= iIrdDecode_t1.isByte & ~(iNanoDec_t3.rxlDbl ? wRxIsSp_t3 : wRyIsSp_t3);

            rRxIsAreg_t4 <= wRxIsSp_t3 | wRxMux_t3[3];
            rRyIsAreg_t4 <= wRyIsSp_t3 | wRyMux_t3[3];

            rAbdIsByte_t4 <= iNanoDec_t3.abdIsByte & iIrdDecode_t1.isByte;
        end
    end

    // Set RX/RY low word to which bus segment is connected.

    wire wRyl2Abl_t4 = iNanoDec_t4.ryl2ab & ( rRyIsAreg_t4 | iNanoDec_t4.ablAbd);
    wire wRyl2Abd_t4 = iNanoDec_t4.ryl2ab & (~rRyIsAreg_t4 | iNanoDec_t4.ablAbd);
    wire wRyl2Dbl_t4 = iNanoDec_t4.ryl2db & ( rRyIsAreg_t4 | iNanoDec_t4.dblDbd);
    wire wRyl2Dbd_t4 = iNanoDec_t4.ryl2db & (~rRyIsAreg_t4 | iNanoDec_t4.dblDbd);

    wire wRxl2Abl_t4 = iNanoDec_t4.rxl2ab & ( rRxIsAreg_t4 | iNanoDec_t4.ablAbd);
    wire wRxl2Abd_t4 = iNanoDec_t4.rxl2ab & (~rRxIsAreg_t4 | iNanoDec_t4.ablAbd);
    wire wRxl2Dbl_t4 = iNanoDec_t4.rxl2db & ( rRxIsAreg_t4 | iNanoDec_t4.dblDbd);
    wire wRxl2Dbd_t4 = iNanoDec_t4.rxl2db & (~rRxIsAreg_t4 | iNanoDec_t4.dblDbd);

    // Buses. Main mux

    
    logic        wDbdIdle_t4;
    logic [15:0] wDbdMux_t4;
    logic        wDblIdle_t4;
    logic [15:0] wDblMux_t4;
    logic        wDbhIdle_t4;
    logic [15:0] wDbhMux_t4;
    
    logic        wAbdIdle_t4;
    logic [15:0] wAbdMux_t4;
    logic        wAblIdle_t4;
    logic [15:0] wAblMux_t4;
    logic        wAbhIdle_t4;
    logic [15:0] wAbhMux_t4;

    always_comb begin : BUS_MUXES_T4
        unique case (1'b1)
            wRxl2Dbd_t4:          { wDbdIdle_t4, wDbdMux_t4 } = { 1'b0, wRx_t4[15:0] };
            wRyl2Dbd_t4:          { wDbdIdle_t4, wDbdMux_t4 } = { 1'b0, wRy_t4[15:0] };
            iNanoDec_t4.alue2Dbd: { wDbdIdle_t4, wDbdMux_t4 } = { 1'b0, alue };
            iNanoDec_t4.dbin2Dbd: { wDbdIdle_t4, wDbdMux_t4 } = { 1'b0, wDbin_t4 };
            iNanoDec_t4.alu2Dbd:  { wDbdIdle_t4, wDbdMux_t4 } = { 1'b0, aluOut };
            iNanoDec_t4.dcr2Dbd:  { wDbdIdle_t4, wDbdMux_t4 } = { 1'b0, dcrOutput };
            default:              { wDbdIdle_t4, wDbdMux_t4 } = { 1'b1, 16'h0000 };
        endcase

        unique case (1'b1)
            wRxl2Dbl_t4:          { wDblIdle_t4, wDblMux_t4 } = { 1'b0, wRx_t4[15:0] };
            wRyl2Dbl_t4:          { wDblIdle_t4, wDblMux_t4 } = { 1'b0, wRy_t4[15:0] };
            iNanoDec_t4.ftu2Dbl:  { wDblIdle_t4, wDblMux_t4 } = { 1'b0, iFtu_t3 };
            iNanoDec_t4.au2Db:    { wDblIdle_t4, wDblMux_t4 } = { 1'b0, rAuReg_t3[15:0] };
            iNanoDec_t4.atl2Dbl:  { wDblIdle_t4, wDblMux_t4 } = { 1'b0, rAtl_t3 };
            rPcl2Dbl_t4:          { wDblIdle_t4, wDblMux_t4 } = { 1'b0, PcL };
            default:              { wDblIdle_t4, wDblMux_t4 } = { 1'b1, 16'h0000 };
        endcase

        unique case (1'b1)
            iNanoDec_t4.rxh2dbh:  { wDbhIdle_t4, wDbhMux_t4 } = { 1'b0, wRx_t4[31:16] };
            iNanoDec_t4.ryh2dbh:  { wDbhIdle_t4, wDbhMux_t4 } = { 1'b0, wRy_t4[31:16] };
            iNanoDec_t4.au2Db:    { wDbhIdle_t4, wDbhMux_t4 } = { 1'b0, rAuReg_t3[31:16] };
            iNanoDec_t4.ath2Dbh:  { wDbhIdle_t4, wDbhMux_t4 } = { 1'b0, rAth_t3 };
            rPch2Dbh_t4:          { wDbhIdle_t4, wDbhMux_t4 } = { 1'b0, PcH };
            default:              { wDbhIdle_t4, wDbhMux_t4 } = { 1'b1, 16'h0000 };
        endcase

        unique case (1'b1)
            wRxl2Abd_t4:          { wAbdIdle_t4, wAbdMux_t4 } = { 1'b0, wRx_t4[15:0] };
            wRyl2Abd_t4:          { wAbdIdle_t4, wAbdMux_t4 } = { 1'b0, wRy_t4[15:0] };
            iNanoDec_t4.dbin2Abd: { wAbdIdle_t4, wAbdMux_t4 } = { 1'b0, wDbin_t4 };
            iNanoDec_t4.alu2Abd:  { wAbdIdle_t4, wAbdMux_t4 } = { 1'b0, aluOut };
            default:              { wAbdIdle_t4, wAbdMux_t4 } = { 1'b1, 16'h0000 };
        endcase

        unique case (1'b1)
            rPcl2Abl_t4:          { wAblIdle_t4, wAblMux_t4 } = { 1'b0, PcL };
            wRxl2Abl_t4:          { wAblIdle_t4, wAblMux_t4 } = { 1'b0, wRx_t4[15:0] };
            wRyl2Abl_t4:          { wAblIdle_t4, wAblMux_t4 } = { 1'b0, wRy_t4[15:0] };
            iNanoDec_t4.ftu2Abl:  { wAblIdle_t4, wAblMux_t4 } = { 1'b0, iFtu_t3 };
            iNanoDec_t4.au2Ab:    { wAblIdle_t4, wAblMux_t4 } = { 1'b0, rAuReg_t3[15:0] };
            iNanoDec_t4.aob2Ab:   { wAblIdle_t4, wAblMux_t4 } = { 1'b0, aob[15:0] };
            iNanoDec_t4.atl2Abl:  { wAblIdle_t4, wAblMux_t4 } = { 1'b0, rAtl_t3 };
            default:              { wAblIdle_t4, wAblMux_t4 } = { 1'b1, 16'h0000 };
        endcase

        unique case (1'b1)
            rPch2Abh_t4:          { wAbhIdle_t4, wAbhMux_t4 } = { 1'b0, PcH };
            iNanoDec_t4.rxh2abh:  { wAbhIdle_t4, wAbhMux_t4 } = { 1'b0, wRx_t4[31:16] };
            iNanoDec_t4.ryh2abh:  { wAbhIdle_t4, wAbhMux_t4 } = { 1'b0, wRy_t4[31:16] };
            iNanoDec_t4.au2Ab:    { wAbhIdle_t4, wAbhMux_t4 } = { 1'b0, rAuReg_t3[31:16] };
            iNanoDec_t4.aob2Ab:   { wAbhIdle_t4, wAbhMux_t4 } = { 1'b0, aob[31:16] };
            iNanoDec_t4.ath2Abh:  { wAbhIdle_t4, wAbhMux_t4 } = { 1'b0, rAth_t3 };
            default:              { wAbhIdle_t4, wAbhMux_t4 } = { 1'b1, 16'h0000 };
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
            {preAbh, preAbl, preAbd} <= { wAbhMux_t4, wAblMux_t4, wAbdMux_t4};
            {preDbh, preDbl, preDbd} <= { wDbhMux_t4, wDblMux_t4, wDbdMux_t4};
        end

        // Process bus interconnection at T2. Many combinations only used on DIV
        // We use a simple method. If a specific bus segment is not driven we know that it should get data from a neighbour segment.
        // In some cases this is not true and the segment is really idle without any destination. But then it doesn't matter.

        if (enT2) begin
            if (iNanoDec_t4.extAbh)
                rAbh_t2 <= { 16{ wAblIdle_t4 ? preAbd[15] : preAbl[15] }};
            else if (wAbhIdle_t4)
                rAbh_t2 <= wAblIdle_t4 ? preAbd : preAbl;
            else
                rAbh_t2 <= preAbh;

            if (~wAblIdle_t4)
                rAbl_t2 <= preAbl;
            else
                rAbl_t2 <= iNanoDec_t4.ablAbh ? preAbh : preAbd;

            rAbd_t2 <= ~wAbdIdle_t4 ? preAbd : wAblIdle_t4 ? preAbh : preAbl;

            if (iNanoDec_t4.extDbh)
                rDbh_t2 <= { 16{ wDblIdle_t4 ? preDbd[15] : preDbl[15] }};
            else if (wDbhIdle_t4)
                rDbh_t2 <= wDblIdle_t4 ? preDbd : preDbl;
            else
                rDbh_t2 <= preDbh;

            if (~wDblIdle_t4)
                rDbl_t2 <= preDbl;
            else
                rDbl_t2 <= iNanoDec_t4.dblDbh ? preDbh : preDbd;

            rDbd_t2 <= ~wDbdIdle_t4 ? preDbd: wDblIdle_t4 ? preDbh : preDbl;

            /*
            rDbl_t2 <= wDblMux_t4;
            rDbh_t2 <= wDbhMux_t4;
            rAbd_t2 <= wAbdMux_t4;
            rDbd_t2 <= wDbdMux_t4;
            rAbh_t2 <= wAbhMux_t4;
            rAbl_t2 <= wAblMux_t4;
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

    wire au2Aob = iNanoDec_t3.au2Aob | (iNanoDec_t3.au2Db & iNanoDec_t3.db2Aob);

    always_ff @(posedge clk) begin
        // UNIQUE IF !

        if (enT1 & au2Aob)      // From AU we do can on T1
            aob <= rAuReg_t3;
        else if (enT2) begin
            if (iNanoDec_t3.db2Aob)
                aob <= { preDbh, ~wDblIdle_t4 ? preDbl : preDbd};
            else if (iNanoDec_t3.ab2Aob)
                aob <= { preAbh, ~wAblIdle_t4 ? preAbl : preAbd};
        end
    end

    assign eab  = aob[31:1];
    assign aob0 = aob[0];

    // AU
    logic [31:0] auInpMux;

    // `ifdef ALW_COMB_BUG
    // Old Modelsim bug. Doesn't update ouput always. Need excplicit sensitivity list !?
    // always @( iNanoDec_t4.auCntrl) begin

    always_comb begin
        unique case (iNanoDec_t4.auCntrl)
            3'b000:  auInpMux = 32'h00000000;
            3'b001:  auInpMux = byteNotSpAlign | iNanoDec_t4.noSpAlign ? 32'h00000001 : 32'h00000002; // +1/+2
            3'b010:  auInpMux = 32'hFFFFFFFC;
            3'b011:  auInpMux = { rAbh_t2, rAbl_t2};
            3'b100:  auInpMux = 32'h00000002;
            3'b101:  auInpMux = 32'h00000004;
            3'b110:  auInpMux = 32'hFFFFFFFE;
            3'b111:  auInpMux = byteNotSpAlign | iNanoDec_t4.noSpAlign ? 32'hFFFFFFFF : 32'hFFFFFFFE; // -1/-2
            default: auInpMux = 32'h00000000;
        endcase
    end

    // Simulation problem
    // Sometimes (like in MULM1) DBH is not set. AU is used in these cases just as a 6 bits counter testing if bits 5-0 are zero.
    // But when adding something like 32'hXXXX0000, the simulator (incorrectly) will set *all the 32 bits* of the result as X.

// synthesis translate_off
    `define SIMULBUGX32 1
    wire [16:0] aulow = rDbl_t2 + auInpMux[15:0];
    wire [31:0] auResult = {rDbh_t2 + auInpMux[31:16] + {15'b0, aulow[16]}, aulow[15:0]};
// synthesis translate_on

    always_ff @(posedge clk) begin

        if (Clks.pwrUp)
            rAuReg_t3 <= 32'h00000000;
        else if (enT3 & iNanoDec_t4.auClkEn)
            `ifdef SIMULBUGX32
                rAuReg_t3 <= auResult;
            `else
                rAuReg_t3 <= { rDbh_t2, rDbl_t2 } + auInpMux;
            `endif
    end


    // Main A/D registers
    
    wire [15:0] wRxh_t2 = (iNanoDec_t4.dbh2rxh) ? rDbh_t2 : rAbh_t2;
    wire [15:0] wRxl_t2 = (rRyIsAreg_t4)
                        ? ((iNanoDec_t4.dbl2rxl) ? rDbl_t2 : rAbl_t2)
                        : ((iNanoDec_t4.dbl2rxl) ? rDbd_t2 : rAbd_t2);
    
    wire [15:0] wRyh_t2 = (iNanoDec_t4.dbh2ryh) ? rDbh_t2 : rAbh_t2;
    wire [15:0] wRyl_t2 = (rRyIsAreg_t4)
                        ? ((iNanoDec_t4.dbl2ryl) ? rDbl_t2 : rAbl_t2)
                        : ((iNanoDec_t4.dbl2ryl) ? rDbd_t2 : rAbd_t2);

    reg   [3:0] rRxWEna_t2;
    reg   [3:0] rRyWEna_t2;
        
    always_ff @(posedge clk) begin : REGS_WRENA_T2
        
        if (enT2) begin
            rRxWEna_t2[3] <= iNanoDec_t4.dbh2rxh | iNanoDec_t4.abh2rxh;
            rRxWEna_t2[2] <= iNanoDec_t4.dbh2rxh | iNanoDec_t4.abh2rxh;
            rRxWEna_t2[1] <= iNanoDec_t4.dbl2rxl | iNanoDec_t4.abl2rxl & (~rAbdIsByte_t4 | rRxIsAreg_t4);
            rRxWEna_t2[0] <= iNanoDec_t4.dbl2rxl | iNanoDec_t4.abl2rxl;
            
            rRyWEna_t2[3] <= iNanoDec_t4.dbh2ryh | iNanoDec_t4.abh2ryh;
            rRyWEna_t2[2] <= iNanoDec_t4.dbh2ryh | iNanoDec_t4.abh2ryh;
            rRyWEna_t2[1] <= iNanoDec_t4.dbl2ryl | iNanoDec_t4.abl2ryl & (~rAbdIsByte_t4 | rRyIsAreg_t4);
            rRyWEna_t2[0] <= iNanoDec_t4.dbl2ryl | iNanoDec_t4.abl2ryl;
        end
    end
    
    // Registers file
    fx68kRegs
`ifdef _FX68K_FPGA_VENDOR_ALTERA_
    #(
       .FPGA_DEVICE (`_FX68K_FPGA_DEVICE_),
       .BRAM_TYPE   (`_FX68K_BRAM_TYPE_)
    )
`endif
    U_fx68kRegs
    (
        .clk        (clk),
        .clk_ena    (enT3 | enT4),
        
        .address_a  (wRxMux_t3),
        .wren_a     (enT3),
        .byteena_a  (rRxWEna_t2),
        .data_a     ({ wRxh_t2[15:0], wRxl_t2[15:0] }),
        .q_a        (wRx_t4),
        
        .address_b  (wRyMux_t3),
        .wren_b     (enT3),
        .byteena_b  (rRyWEna_t2),
        .data_b     ({ wRyh_t2[15:0], wRyl_t2[15:0] }),
        .q_b        (wRy_t4)
    );

    // PC & AT
    reg  rDbl2Pcl_t4;
    reg  rDbh2Pch_t4;
    reg  rAbh2Pch_t4;
    reg  rAbl2Pcl_t4;

    reg  rPcl2Dbl_t4;
    reg  rPch2Dbh_t4;
    reg  rPcl2Abl_t4;
    reg  rPch2Abh_t4;
    
    always_ff @(posedge clk) begin
    
        if (Clks.extReset) begin
            rDbl2Pcl_t4 <= 1'b0;
            rDbh2Pch_t4 <= 1'b0;
            rAbl2Pcl_t4 <= 1'b0;
            rAbh2Pch_t4 <= 1'b0;

            rPcl2Dbl_t4 <= 1'b0;
            rPch2Dbh_t4 <= 1'b0;
            rPcl2Abl_t4 <= 1'b0;
            rPch2Abh_t4 <= 1'b0;
        end
        else if (enT4) begin // Must latch on T4 !
            rDbl2Pcl_t4 <= iNanoDec_t3.dbl2reg & iNanoDec_t3.pcldbl;
            rDbh2Pch_t4 <= iNanoDec_t3.dbh2reg & iNanoDec_t3.pchdbh;
            rAbh2Pch_t4 <= iNanoDec_t3.abh2reg & iNanoDec_t3.pchabh;
            rAbl2Pcl_t4 <= iNanoDec_t3.abl2reg & iNanoDec_t3.pclabl;

            rPcl2Dbl_t4 <= iNanoDec_t3.reg2dbl & iNanoDec_t3.pcldbl;
            rPch2Dbh_t4 <= iNanoDec_t3.reg2dbh & iNanoDec_t3.pchdbh;
            rPcl2Abl_t4 <= iNanoDec_t3.reg2abl & iNanoDec_t3.pclabl;
            rPch2Abh_t4 <= iNanoDec_t3.reg2abh & iNanoDec_t3.pchabh;
        end

        // Unique IF !!!
        if (enT1 & iNanoDec_t3.au2Pc)
            PcL <= rAuReg_t3[15:0];
        else if (enT3) begin
            if (rDbl2Pcl_t4)
                PcL <= rDbl_t2;
            else if (rAbl2Pcl_t4)
                PcL <= rAbl_t2;
        end

        // Unique IF !!!
        if (enT1 & iNanoDec_t3.au2Pc)
            PcH <= rAuReg_t3[31:16];
        else if (enT3) begin
            if (rDbh2Pch_t4)
                PcH <= rDbh_t2;
            else if (rAbh2Pch_t4)
                PcH <= rAbh_t2;
        end

        // Unique IF !!!
        if (enT3) begin
            if (iNanoDec_t4.dbl2Atl)
                rAtl_t3 <= rDbl_t2;
            else if (iNanoDec_t4.abl2Atl)
                rAtl_t3 <= rAbl_t2;
        end

        // Unique IF !!!
        if (enT3) begin
            if (iNanoDec_t4.abh2Ath)
                rAth_t3 <= rAbh_t2;
            else if (iNanoDec_t4.dbh2Ath)
                rAth_t3 <= rDbh_t2;
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
        if (enT1 & iNanoDec_t4.abl2Pren)
            prenLatch <= wDbin_t4;
        else if (enT3 & iNanoDec_t4.updPren) begin
            prenLatch [prHbit] <= 1'b0;
            rMovemRx_t3     <= prHbit ^ {4{iIrdDecode_t1.movemPreDecr}};
            rMovemRxIsSp_t3 <= (prHbit == {4{~iIrdDecode_t1.movemPreDecr}}) ? 1'b1 : 1'b0;
        end
        
        if (enT3) begin
            rRxIsMovem_t3 <= iIrdDecode_t1.rxIsMovem;
        end
    end

    // DCR
    wire [15:0] dcrCode;

    wire [3:0] dcrInput = rAbdIsByte_t4 ? { 1'b0, rAbd_t2[ 2:0]} : rAbd_t2[ 3:0];
    onehotEncoder4 dcrDecoder( .bin( dcrInput), .bitMap( dcrCode));

    always_ff @(posedge clk) begin

        if (Clks.pwrUp)
            dcr4 <= '0;
        else if (enT3 & iNanoDec_t4.abd2Dcr) begin
            dcrOutput <= dcrCode;
            dcr4 <= rAbd_t2[4];
        end
    end

    // ALUB
    reg [15:0] rAlub_t3;

    always_ff @(posedge clk) begin

        if (enT3) begin
            // UNIQUE IF !!
            if (iNanoDec_t4.dbd2Alub)
                rAlub_t3 <= rDbd_t2;
            else if (iNanoDec_t4.abd2Alub)
                rAlub_t3 <= rAbd_t2;                // rAbdIsByte_t4 affects this !!??
        end
    end

    wire alueClkEn = enT3 & iNanoDec_t4.dbd2Alue;

    // DOB/DBIN/IRC

    logic [15:0] dobInput;
    wire dobIdle = (~| iNanoDec_t4.dobCtrl);

    always_comb begin
        unique case (iNanoDec_t4.dobCtrl)
        NANO_DOB_ADB:       dobInput = rAbd_t2;
        NANO_DOB_DBD:       dobInput = rDbd_t2;
        NANO_DOB_ALU:       dobInput = aluOut;
        default:            dobInput = 'X;
        endcase
    end

    dataIo U_dataIo
    (
        .clk, .Clks, .enT1, .enT2, .enT3, .enT4,
        .iNanoDec_t4 (iNanoDec_t4),
        .iNanoDec_t3 (iNanoDec_t3),
        .iIsByte_t1  (iIrdDecode_t1.isByte),
        .iEdb, .dobIdle, .dobInput, .aob0,
        .oIrc_t4     (oIrc_t4),
        .oDbin_t4    (wDbin_t4),
        .oEdb
    );

    fx68kAlu U_fx68kAlu
    (
        .clk, .pwrUp( Clks.pwrUp), .enT1, .enT3, .enT4,
        .ird         (Ird),
        .aluColumn   (iNanoDec_t3.aluColumn),
        .aluDataCtrl (iNanoDec_t3.aluDctrl),
        .aluAddrCtrl (iNanoDec_t3.aluActrl),
        .ftu2Ccr     (iNanoDec_t3.ftu2Ccr),
        .init        (iNanoDec_t3.aluInit),
        .finish      (iNanoDec_t3.aluFinish),
        .aluIsByte   (iIrdDecode_t1.isByte),
        .alub        (rAlub_t3),
        .ftu         (iFtu_t3), 
        .alueClkEn,
        .iDataBus    (rDbd_t2),
        .iAddrBus    (rAbd_t2),
        .ze          (ze),
        .alue        (alue),
        .oAluOut     (aluOut),
        .oCcr        (ccr)
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
    input     s_nanod_r iNanoDec_t4,
    input     s_nanod_w iNanoDec_t3,
    input               iIsByte_t1,
    input        [15:0] iEdb,
    input               aob0,

    input               dobIdle,
    input        [15:0] dobInput,

    output       [15:0] oIrc_t4,
    output       [15:0] oDbin_t4,
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
    
    // Instruction register (IRC)
    reg [15:0] rIrc_t4;
    // Data register (DBIN)
    reg [15:0] rDbin_t4;

    always_ff @(posedge clk) begin

        // Byte mux control. Can't latch at T1. AOB might be not ready yet.
        // Must latch IRD decode at T1 (or T4). Then combine and latch only at T3.

        // Can't latch at T3, a new IRD might be loaded already at T1.
        // Ok to latch at T4 if combination latched then at T3
        if (enT4)
            isByte_T4 <= iIsByte_t1;    // Includes MOVEP from mem, we could OR it here

        if (enT3) begin
            dbinNoHigh <= iNanoDec_t3.noHighByte;
            dbinNoLow  <= iNanoDec_t3.noLowByte;
            byteMux    <= iNanoDec_t3.busByte & isByte_T4 & ~aob0;
        end

        if (enT1) begin
            // If on wait states, we continue latching until next T1
            xToDbin <= 1'b0;
            xToIrc  <= 1'b0;
        end
        else if (enT3) begin
            xToDbin <= iNanoDec_t4.todbin;
            xToIrc  <= iNanoDec_t4.toIrc;
        end

        // Capture on T4 of the next ucycle
        // If there are wait states, we keep capturing every PHI2 until the next T1

        if (xToIrc & Clks.enPhi2)
            rIrc_t4 <= iEdb;
        if (xToDbin & Clks.enPhi2) begin
            // Original connects both halves of EDB.
            if (~dbinNoLow)
                rDbin_t4[ 7:0] <= byteMux ? iEdb[ 15:8] : iEdb[7:0];
            if (~dbinNoHigh)
                rDbin_t4[15:8] <= ~byteMux & dbinNoLow ? iEdb[ 7:0] : iEdb[ 15:8];
        end
    end
    
    assign oIrc_t4  = rIrc_t4;
    assign oDbin_t4 = rDbin_t4;

    // DOB
    logic byteCycle;

    always_ff @(posedge clk) begin
        // Originaly on T1. Transfer to internal EDB also on T1 (stays enabled upto the next T1). But only on T4 (S3) output enables.
        // It is safe to do on T3, then, but control signals if derived from IRD must be registered.
        // Originally control signals are not registered.

        // Wait states don't affect DOB operation that is done at the start of the bus cycle.

        if (enT4)
            byteCycle <= iNanoDec_t3.busByte & iIsByte_t1;        // busIsByte but not MOVEP

        // Originally byte low/high interconnect is done at EDB, not at DOB.
        if (enT3 & ~dobIdle) begin
            dob[7:0] <= iNanoDec_t3.noLowByte ? dobInput[15:8] : dobInput[ 7:0];
            dob[15:8] <= (byteCycle | iNanoDec_t3.noHighByte) ? dobInput[ 7:0] : dobInput[15:8];
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
    input             [15:0] iOpCode_t1,
    input             [15:0] iOpLine_t1,
    input              [3:0] iEA1_t1,
    input              [3:0] iEA2_t1,
    output [UADDR_WIDTH-1:0] oPlaA1_t1,
    output [UADDR_WIDTH-1:0] oPlaA2_t1,
    output [UADDR_WIDTH-1:0] oPlaA3_t1,
    output logic             oIsPriv_t1,
    output logic             oIsIllegal_t1
);

    uaddrPla U_uaddrPla
    (
        .movEa    (iEA2_t1),
        .col      (iEA1_t1),
        .opcode   (iOpCode_t1),
        .lineBmap (iOpLine_t1),
        .plaIll   (oIsIllegal_t1),
        .plaA1    (oPlaA1_t1),
        .plaA2    (oPlaA2_t1),
        .plaA3    (oPlaA3_t1)
    );

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
        unique case (1'b1)

            // ANDI/EORI/ORI SR
            iOpLine_t1[0]:
                oIsPriv_t1 = ((iOpCode_t1[11:0] & 12'h5FF) == 12'h07C) ? 1'b1 : 1'b0;

            iOpLine_t1[4]:
                oIsPriv_t1 = ((iOpCode_t1[11:0] & 12'hFC0) == 12'h6C0) // MOVE to SR
                          || ((iOpCode_t1[11:0] & 12'hFF0) == 12'hE60) // MOVE to/from USP
                          || ((iOpCode_t1[11:0] & 12'hFFF) == 12'hE70) // RESET
                          || ((iOpCode_t1[11:0] & 12'hFFF) == 12'hE72) // STOP
                          || ((iOpCode_t1[11:0] & 12'hFFF) == 12'hE73) // RTE
                          ? 1'b1 : 1'b0;

            default:
                oIsPriv_t1 = 1'b0;
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
    input  [UROM_WIDTH-1:0] iMicroLatch_t3,
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

    wire [UADDR_WIDTH-1:0] dbNma = { iMicroLatch_t3[ 14:13], iMicroLatch_t3[ 6:5], iMicroLatch_t3[ 10:7], iMicroLatch_t3[ 12:11]};

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
        if (iMicroLatch_t3[1])
            uNma = { iMicroLatch_t3[ 14:13], c0c1, iMicroLatch_t3[ 10:7], iMicroLatch_t3[ 12:11]};
        else
            case (iMicroLatch_t3[ 3:2])
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
    wire [4:0] cbc = iMicroLatch_t3[ 6:2];          // CBC bits

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
                    c0c1 = { 1'b0, iMicroLatch_t3[ 6]};
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
    assign grp1LatchEn = iMicroLatch_t3[0] & (iMicroLatch_t3[1] | !iMicroLatch_t3[4]);
    assign grp0LatchEn = iMicroLatch_t3[4] & !iMicroLatch_t3[1];

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
            rTrace     <= Tpend;
            rInterrupt <= intPend;
            rIllegal   <= isIllegal & ~isLineA & ~isLineF;
            rLineA     <= isLineA;
            rLineF     <= isLineF;
            rPriv      <= isPriv & ~psw[SF];
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
