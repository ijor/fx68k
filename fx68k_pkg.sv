`ifdef _FX68K_PKG_
/* already included !! */
`else
`define _FX68K_PKG_

package fx68k_pkg;

localparam CF = 0, VF = 1, ZF = 2, NF = 3, XF = 4, SF = 13;

localparam UADDR_WIDTH = 10;
localparam UROM_WIDTH = 17;
localparam UROM_DEPTH = 1024;

localparam NADDR_WIDTH = 9;
localparam NANO_WIDTH = 68;
localparam NANO_DEPTH = 336;

localparam
    HALT1_NMA = 'h001,
    RSTP0_NMA = 'h002,
    BSER1_NMA = 'h003,
    TRAC1_NMA = 'h1C0,
    ITLX1_NMA = 'h1C4;

localparam [3:0]
    TVN_SPURIOUS  = 4'hC,
    TVN_AUTOVEC   = 4'hD,
    TVN_INTERRUPT = 4'hF;

localparam NANO_DOB_DBD = 2'b01;
localparam NANO_DOB_ADB = 2'b10;
localparam NANO_DOB_ALU = 2'b11;

localparam [3:0]
    EA_Dn     = 4'h0, // Dn
    EA_An     = 4'h1, // An
    EA_Ind    = 4'h2, // (An)
    EA_Post   = 4'h3, // (An)+
    EA_Pre    = 4'h4, // -(An)
    EA_Rel_An = 4'h5, // d16(An)
    EA_Idx_An = 4'h6, // d8(An,Xn)
    EA_Abs_W  = 4'h7, // xxxx.W
    EA_Abs_L  = 4'h8, // xxxxxxxx.W
    EA_Rel_PC = 4'h9, // d16(PC)
    EA_Idx_PC = 4'hA, // d8(PC,Xn)
    EA_Imm    = 4'hB, // #xx / #xxxx / #xxxxxxxx
    EA_Inv    = 4'hC; // Invalid

// Clocks, phases and resets
typedef struct packed
{
    //logic clk;
    logic extReset;         // External sync reset on emulated system
    logic pwrUp;            // Asserted together with reset on emulated system coldstart
    logic enPhi1, enPhi2;   // Clock enables. Next cycle is PHI1 or PHI2
} s_clks;

// IRD decoded signals
typedef struct packed
{
    logic isPcRel;
    logic isTas;
    logic implicitSp;
    logic toCcr;
    logic rxIsDt, ryIsDt;
    logic rxIsUsp, rxIsMovem, movemPreDecr;
    logic isByte;
    logic isMovep;
    logic [2:0] rx, ry;
    logic rxIsAreg, ryIsAreg;
    logic [15:0] ftuConst;
    logic [5:0] macroTvn;
    logic inhibitCcr;
} s_irdecod;

// Nano code decoded signals
typedef struct packed
{
    logic permStart;
    logic waitBusFinish;
    logic isWrite;
    logic busByte;
    logic isRmc;
    logic noLowByte, noHighByte;
    
    logic updTpend, clrTpend;
    logic tvn2Ftu, const2Ftu;
    logic ftu2Dbl, ftu2Abl;
    logic abl2Pren, updPren;
    logic inl2psw, ftu2Sr, sr2Ftu, ftu2Ccr, pswIToFtu;
    logic ird2Ftu, ssw2Ftu;
    logic initST;
    logic Ir2Ird;
    
    logic auClkEn, noSpAlign;
    logic [2:0] auCntrl;
    logic todbin, toIrc;
    logic dbl2Atl, abl2Atl, atl2Abl, atl2Dbl;
    logic abh2Ath, dbh2Ath;
    logic ath2Dbh, ath2Abh;
    
    logic db2Aob, ab2Aob, au2Aob;
    logic aob2Ab, updSsw;
    // logic adb2Dob, dbd2Dob, alu2Dob;
    logic [1:0] dobCtrl;
    
    logic abh2reg, abl2reg;
    logic reg2abl, reg2abh;
    logic dbh2reg, dbl2reg;
    logic reg2dbl, reg2dbh;
    logic ssp, pchdbh, pcldbl, pclabl, pchabh;
    
    logic rxh2dbh, rxh2abh;
    logic dbl2rxl, dbh2rxh;
    logic rxl2db, rxl2ab;
    logic abl2rxl, abh2rxh;
    logic dbh2ryh, abh2ryh;
    logic ryl2db, ryl2ab;
    logic ryh2dbh, ryh2abh;
    logic dbl2ryl, abl2ryl;
    logic rz;
    logic rxlDbl;
    
    logic [2:0] aluColumn;
    logic [1:0] aluDctrl;
    logic aluActrl;
    logic aluInit, aluFinish;
    logic abd2Dcr, dcr2Dbd;
    logic dbd2Alue, alue2Dbd;
    logic dbd2Alub, abd2Alub;
    
    logic alu2Dbd, alu2Abd;
    logic au2Db, au2Ab, au2Pc;
    logic dbin2Abd, dbin2Dbd;
    logic extDbh, extAbh;
    logic ablAbd, ablAbh;
    logic dblDbd, dblDbh;
    logic abdIsByte;
} s_nanod;

// EA decode
function [3:0] eaDecode;
    input [5:0] eaBits;
    begin
        unique casez (eaBits)
            6'b111_000: eaDecode = EA_Abs_W;  // Absolute short
            6'b111_001: eaDecode = EA_Abs_L;  // Absolute long
            6'b111_010: eaDecode = EA_Rel_PC; // PC relative
            6'b111_011: eaDecode = EA_Idx_PC; // PC indexed
            6'b111_100: eaDecode = EA_Imm;    // Immediate
            6'b111_101: eaDecode = EA_Inv;    // Invalid
            6'b111_11?: eaDecode = EA_Inv;    // Invalid
            default:    eaDecode = { 1'b0, eaBits[5:3] }; // Register based EAs
        endcase
    end
endfunction

endpackage

`endif /* _FX68K_PKG_ */
