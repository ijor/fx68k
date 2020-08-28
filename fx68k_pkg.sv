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
    logic        isPcRel;
    logic        isTas;
    logic        implicitSp;
    logic        toCcr;
    logic        rxIsDt;
    logic        ryIsDt;
    logic        rxIsUsp;
    logic        rxIsMovem;
    logic        movemPreDecr;
    logic        isByte;
    logic        isMovep;
    logic  [2:0] rx;
    logic  [2:0] ry;
    logic        rxIsAreg;
    logic        ryIsAreg;
    logic [15:0] ftuConst;
    logic  [5:0] macroTvn;
    logic        inhibitCcr;
} s_irdecod;

// Nano code decoded signals
typedef struct packed
{
    logic       isRmc;         // r

    logic       auClkEn;       // r
    logic       noSpAlign;     // r
    logic [2:0] auCntrl;       // r
    logic       todbin;        // r
    logic       toIrc;         // r
    logic       dbl2Atl;       // r
    logic       abl2Atl;       // r
    logic       atl2Abl;       // r
    logic       atl2Dbl;       // r
    logic       abh2Ath;       // r
    logic       dbh2Ath;       // r
    logic       ath2Dbh;       // r
    logic       ath2Abh;       // r

    logic       aob2Ab;        // r
    // logic adb2Dob;             // r
    // logic dbd2Dob;             // r
    // logic alu2Dob;             // r
    logic [1:0] dobCtrl;       // r

    logic       rxh2dbh;       // r
    logic       rxh2abh;       // r
    logic       dbl2rxl;       // r
    logic       dbh2rxh;       // r
    logic       rxl2db;        // r
    logic       rxl2ab;        // r
    logic       abl2rxl;       // r
    logic       abh2rxh;       // r
    logic       dbh2ryh;       // r
    logic       abh2ryh;       // r
    logic       ryl2db;        // r
    logic       ryl2ab;        // r
    logic       ryh2dbh;       // r
    logic       ryh2abh;       // r
    logic       dbl2ryl;       // r
    logic       abl2ryl;       // r

    logic       abd2Dcr;       // r
    logic       dcr2Dbd;       // r
    logic       dbd2Alue;      // r
    logic       alue2Dbd;      // r
    logic       dbd2Alub;      // r
    logic       abd2Alub;      // r

    logic       alu2Dbd;       // r
    logic       alu2Abd;       // r
    logic       extDbh;        // r
    logic       extAbh;        // r
    logic       ablAbd;        // r
    logic       ablAbh;        // r
    logic       dblDbd;        // r
    logic       dblDbh;        // r
} s_nanod_r;

typedef struct packed
{
    logic       permStart;     // w
    logic       waitBusFinish; // w
    logic       isWrite;       // w
    logic       busByte;       // w
    logic       noLowByte;     // w
    logic       noHighByte;    // w

    logic       updTpend;      // w
    logic       clrTpend;      // w
    logic       tvn2Ftu;       // w
    logic       const2Ftu;     // w
    logic       ftu2Dbl;       // w
    logic       ftu2Abl;       // w
    logic       abl2Pren;      // w
    logic       updPren;       // w
    logic       inl2psw;       // w
    logic       ftu2Sr;        // w
    logic       sr2Ftu;        // w
    logic       ftu2Ccr;       // w
    logic       pswIToFtu;     // w
    logic       ird2Ftu;       // w
    logic       ssw2Ftu;       // w
    logic       initST;        // w
    logic       Ir2Ird;        // w

    logic       db2Aob;        // w
    logic       ab2Aob;        // w
    logic       au2Aob;        // w
    logic       updSsw;        // w

    logic       abh2reg;       // w
    logic       abl2reg;       // w
    logic       reg2abl;       // w
    logic       reg2abh;       // w
    logic       dbh2reg;       // w
    logic       dbl2reg;       // w
    logic       reg2dbl;       // w
    logic       reg2dbh;       // w
    logic       ssp;           // w
    logic       pchdbh;        // w
    logic       pcldbl;        // w
    logic       pclabl;        // w
    logic       pchabh;        // w

    logic       rz;            // w
    logic       rxlDbl;        // w

    logic [2:0] aluColumn;     // w
    logic [1:0] aluDctrl;      // w
    logic       aluActrl;      // w
    logic       aluInit;       // w
    logic       aluFinish;     // w

    logic       au2Db;         // w
    logic       au2Ab;         // w
    logic       au2Pc;         // w
    logic       dbin2Abd;      // w
    logic       dbin2Dbd;      // w
    logic       abdIsByte;     // w
} s_nanod_w;

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
