//
// FX68K
//
// Opcode to uaddr entry routines (A2-A2-A3) PLA
//

`timescale 1 ns / 1 ns

`ifdef _VLINT_
`include "fx68k_pkg.sv"
`endif /* _VLINT_ */

import fx68k_pkg::*;

module uaddrPla
(
    input                    [3:0] movEa,
    input                    [3:0] col,
    
    input                   [15:0] opcode,
    input                   [15:0] lineBmap,
    
    output                         palIll,
    output logic [UADDR_WIDTH-1:0] plaA1,
    output logic [UADDR_WIDTH-1:0] plaA2,
    output logic [UADDR_WIDTH-1:0] plaA3
);

    wire [3:0] line  = opcode[15:12];
    wire [2:0] row86 = opcode[8:6];
    
    logic            [15:0] arIll;
    logic [UADDR_WIDTH-1:0] arA1[15:0];
    logic [UADDR_WIDTH-1:0] arA23[15:0];
    logic [UADDR_WIDTH-1:0] scA3;
    
    logic                   illMisc;
    logic [UADDR_WIDTH-1:0] a1Misc;
   
    assign palIll = (| (arIll & lineBmap));
   
    // Only line 0 has 3 subs
    assign plaA1 = arA1[ line];
    assign plaA2 = arA23[ line];
    assign plaA3 = lineBmap[0] ? scA3 : arA23[ line];
   
`define SFTM1 10'h3C7
`define SRRW1 10'h382
`define SRIW1 10'h381
`define SRRL1 10'h386
`define SRIL1 10'h385
`define BSRI1 10'h089
`define BSRW1 10'h0A9
`define BBCI1 10'h308
`define BBCW1 10'h068
`define RLQL1 10'h23B
`define ADRW1 10'h006
`define PINW1 10'h21C
`define PDCW1 10'h103
`define ADSW1 10'h1C2
`define AIXW0 10'h1E3
`define ABWW1 10'h00A
`define ABLW1 10'h1E2
`define TRAP1 10'h1D0
`define LINK1 10'h30B
`define UNLK1 10'h119
`define LUSP1 10'h2F5
`define SUSP1 10'h230
`define TRPV1 10'h06D
`define RSET1 10'h3A6
`define B     10'h363
`define STOP1 10'h3A2
`define RTR1  10'h12A
`define RTS1  10'h126
`define UNDF  10'hXXX
   
    // Simple lines
    always_comb begin
        // Line 6: Branch
        arIll[ 'h6] = 1'b0;
        arA23[ 'h6] = `UNDF;
        if (opcode[ 11:8] == 4'b0001)
            arA1[ 'h6] = (|opcode[7:0]) ? `BSRI1 : `BSRW1;
        else
            arA1[ 'h6] = (|opcode[7:0]) ? `BBCI1 : `BBCW1;
        
        // Line 7: moveq
        arIll[ 'h7] = opcode[ 8];
        arA23[ 'h7] = `UNDF;
        arA1[ 'h7] = `RLQL1;
        
        // Line A & F      
        arIll[ 'ha] = 1'b1;  arIll[ 'hf] = 1'b1;
        arA1[ 'ha]  = `UNDF; arA1[ 'hf]  = `UNDF;
        arA23[ 'ha] = `UNDF; arA23[ 'hf] = `UNDF;
       
    end   

   // Special lines

   // Line E: shifts
   always_comb begin
      if( ~opcode[11] & opcode[7] & opcode[6])
      begin
         arA23[ 'he] = `SFTM1;
         unique case( col)
            EA_Ind:    begin arIll[ 'he] = 1'b0; arA1[ 'he] = `ADRW1; end
            EA_Post:   begin arIll[ 'he] = 1'b0; arA1[ 'he] = `PINW1; end
            EA_Pre:    begin arIll[ 'he] = 1'b0; arA1[ 'he] = `PDCW1; end
            EA_Rel_An: begin arIll[ 'he] = 1'b0; arA1[ 'he] = `ADSW1; end
            EA_Idx_An: begin arIll[ 'he] = 1'b0; arA1[ 'he] = `AIXW0; end
            EA_Abs_W:  begin arIll[ 'he] = 1'b0; arA1[ 'he] = `ABWW1; end
            EA_Abs_L:  begin arIll[ 'he] = 1'b0; arA1[ 'he] = `ABLW1; end
            default:   begin arIll[ 'he] = 1'b1; arA1[ 'he] = `UNDF;  end
         endcase
      end
      else
      begin
         arA23[ 'he] = `UNDF;
         unique case( opcode[ 7:6])
         2'b00,
         2'b01: begin
                  arIll[ 'he] = 1'b0;
                  arA1[ 'he]  = opcode[ 5] ? `SRRW1 : `SRIW1;
               end
         2'b10: begin
                  arIll[ 'he] = 1'b0;
                  arA1[ 'he]  = opcode[ 5] ? `SRRL1 : `SRIL1;
              end
         2'b11: begin arIll[ 'he] = 1'b1; arA1[ 'he]  = `UNDF; end
         endcase
      end
   end

   // Misc. line 4 row
   always_comb begin
      illMisc = 1'b0;
      case( opcode[ 5:3])
      3'b000,
      3'b001:      a1Misc = `TRAP1;
      3'b010:      a1Misc = `LINK1;
      3'b011:      a1Misc = `UNLK1;
      3'b100:      a1Misc = `LUSP1;
      3'b101:      a1Misc = `SUSP1;
      
      3'b110:   
         case( opcode[ 2:0])
         3'b110:   a1Misc = `TRPV1;
         3'b000:   a1Misc = `RSET1;
         3'b001:   a1Misc = `B;
         3'b010:   a1Misc = `STOP1;
         3'b011:   a1Misc = `RTR1;
         3'b111:   a1Misc = `RTR1;
         3'b101:   a1Misc = `RTS1;
         default:  begin  illMisc = 1'b1; a1Misc = `UNDF; end
         endcase
         
      default:  begin  illMisc = 1'b1; a1Misc = `UNDF; end
      endcase
   end

//
// Past here
//


//
// Line: 0
//
always_comb begin

if( (opcode[11:6] & 'h1F) == 'h8) begin
    unique case ( col)
    EA_Dn:     begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h100; scA3 = `UNDF; end
    EA_An:     begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_Ind:    begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h006; scA3 = 'h299; end
    EA_Post:   begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h21C; scA3 = 'h299; end
    EA_Pre:    begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h103; scA3 = 'h299; end
    EA_Rel_An: begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h1C2; scA3 = 'h299; end
    EA_Idx_An: begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h1E3; scA3 = 'h299; end
    EA_Abs_W:  begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h00A; scA3 = 'h299; end
    EA_Abs_L:  begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h1E2; scA3 = 'h299; end
    EA_Rel_PC: begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_Idx_PC: begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_Imm:    begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h1CC; scA3 = `UNDF; end
    default:   begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    endcase
end

else if( (opcode[11:6] & 'h37) == 'h0) begin
    unique case ( col)
    EA_Dn:     begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h100; scA3 = `UNDF; end
    EA_An:     begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_Ind:    begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h006; scA3 = 'h299; end
    EA_Post:   begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h21C; scA3 = 'h299; end
    EA_Pre:    begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h103; scA3 = 'h299; end
    EA_Rel_An: begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h1C2; scA3 = 'h299; end
    EA_Idx_An: begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h1E3; scA3 = 'h299; end
    EA_Abs_W:  begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h00A; scA3 = 'h299; end
    EA_Abs_L:  begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h1E2; scA3 = 'h299; end
    EA_Rel_PC: begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_Idx_PC: begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_Imm:    begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h1CC; scA3 = `UNDF; end
    default:   begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    endcase
end

else if( (opcode[11:6] & 'h1F) == 'h9) begin
    unique case ( col)
    EA_Dn:     begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h100; scA3 = `UNDF; end
    EA_An:     begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_Ind:    begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h006; scA3 = 'h299; end
    EA_Post:   begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h21C; scA3 = 'h299; end
    EA_Pre:    begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h103; scA3 = 'h299; end
    EA_Rel_An: begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h1C2; scA3 = 'h299; end
    EA_Idx_An: begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h1E3; scA3 = 'h299; end
    EA_Abs_W:  begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h00A; scA3 = 'h299; end
    EA_Abs_L:  begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h1E2; scA3 = 'h299; end
    EA_Rel_PC: begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_Idx_PC: begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_Imm:    begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h1CC; scA3 = `UNDF; end
    default:   begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    endcase
end

else if( (opcode[11:6] & 'h37) == 'h1) begin
    unique case ( col)
    EA_Dn:     begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h100; scA3 = `UNDF; end
    EA_An:     begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_Ind:    begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h006; scA3 = 'h299; end
    EA_Post:   begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h21C; scA3 = 'h299; end
    EA_Pre:    begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h103; scA3 = 'h299; end
    EA_Rel_An: begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h1C2; scA3 = 'h299; end
    EA_Idx_An: begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h1E3; scA3 = 'h299; end
    EA_Abs_W:  begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h00A; scA3 = 'h299; end
    EA_Abs_L:  begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h1E2; scA3 = 'h299; end
    EA_Rel_PC: begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_Idx_PC: begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_Imm:    begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h1CC; scA3 = `UNDF; end
    default:   begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    endcase
end

else if( (opcode[11:6] & 'h1F) == 'hA) begin
    unique case ( col)
    EA_Dn:     begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h3E0; arA23[ 'h0] = 'h10C; scA3 = `UNDF; end
    EA_An:     begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_Ind:    begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h3E0; arA23[ 'h0] = 'h00B; scA3 = 'h29D; end
    EA_Post:   begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h3E0; arA23[ 'h0] = 'h00F; scA3 = 'h29D; end
    EA_Pre:    begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h3E0; arA23[ 'h0] = 'h179; scA3 = 'h29D; end
    EA_Rel_An: begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h3E0; arA23[ 'h0] = 'h1C6; scA3 = 'h29D; end
    EA_Idx_An: begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h3E0; arA23[ 'h0] = 'h1E7; scA3 = 'h29D; end
    EA_Abs_W:  begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h3E0; arA23[ 'h0] = 'h00E; scA3 = 'h29D; end
    EA_Abs_L:  begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h3E0; arA23[ 'h0] = 'h1E6; scA3 = 'h29D; end
    EA_Rel_PC: begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_Idx_PC: begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_Imm:    begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    default:   begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    endcase
end

else if( (opcode[11:6] & 'h37) == 'h2) begin
    unique case ( col)
    EA_Dn:     begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h3E0; arA23[ 'h0] = 'h10C; scA3 = `UNDF; end
    EA_An:     begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_Ind:    begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h3E0; arA23[ 'h0] = 'h00B; scA3 = 'h29D; end
    EA_Post:   begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h3E0; arA23[ 'h0] = 'h00F; scA3 = 'h29D; end
    EA_Pre:    begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h3E0; arA23[ 'h0] = 'h179; scA3 = 'h29D; end
    EA_Rel_An: begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h3E0; arA23[ 'h0] = 'h1C6; scA3 = 'h29D; end
    EA_Idx_An: begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h3E0; arA23[ 'h0] = 'h1E7; scA3 = 'h29D; end
    EA_Abs_W:  begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h3E0; arA23[ 'h0] = 'h00E; scA3 = 'h29D; end
    EA_Abs_L:  begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h3E0; arA23[ 'h0] = 'h1E6; scA3 = 'h29D; end
    EA_Rel_PC: begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_Idx_PC: begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_Imm:    begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    default:   begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    endcase
end

else if( (opcode[11:6] & 'h37) == 'h10) begin
    unique case ( col)
    EA_Dn:     begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h100; scA3 = `UNDF; end
    EA_An:     begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_Ind:    begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h006; scA3 = 'h299; end
    EA_Post:   begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h21C; scA3 = 'h299; end
    EA_Pre:    begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h103; scA3 = 'h299; end
    EA_Rel_An: begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h1C2; scA3 = 'h299; end
    EA_Idx_An: begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h1E3; scA3 = 'h299; end
    EA_Abs_W:  begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h00A; scA3 = 'h299; end
    EA_Abs_L:  begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h1E2; scA3 = 'h299; end
    EA_Rel_PC: begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_Idx_PC: begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_Imm:    begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    default:   begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    endcase
end

else if( (opcode[11:6] & 'h37) == 'h11) begin
    unique case ( col)
    EA_Dn:     begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h100; scA3 = `UNDF; end
    EA_An:     begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_Ind:    begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h006; scA3 = 'h299; end
    EA_Post:   begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h21C; scA3 = 'h299; end
    EA_Pre:    begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h103; scA3 = 'h299; end
    EA_Rel_An: begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h1C2; scA3 = 'h299; end
    EA_Idx_An: begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h1E3; scA3 = 'h299; end
    EA_Abs_W:  begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h00A; scA3 = 'h299; end
    EA_Abs_L:  begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h1E2; scA3 = 'h299; end
    EA_Rel_PC: begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_Idx_PC: begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_Imm:    begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    default:   begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    endcase
end

else if( (opcode[11:6] & 'h37) == 'h12) begin
    unique case ( col)
    EA_Dn:     begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h3E0; arA23[ 'h0] = 'h10C; scA3 = `UNDF; end
    EA_An:     begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_Ind:    begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h3E0; arA23[ 'h0] = 'h00B; scA3 = 'h29D; end
    EA_Post:   begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h3E0; arA23[ 'h0] = 'h00F; scA3 = 'h29D; end
    EA_Pre:    begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h3E0; arA23[ 'h0] = 'h179; scA3 = 'h29D; end
    EA_Rel_An: begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h3E0; arA23[ 'h0] = 'h1C6; scA3 = 'h29D; end
    EA_Idx_An: begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h3E0; arA23[ 'h0] = 'h1E7; scA3 = 'h29D; end
    EA_Abs_W:  begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h3E0; arA23[ 'h0] = 'h00E; scA3 = 'h29D; end
    EA_Abs_L:  begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h3E0; arA23[ 'h0] = 'h1E6; scA3 = 'h29D; end
    EA_Rel_PC: begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_Idx_PC: begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_Imm:    begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    default:   begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    endcase
end

else if( (opcode[11:6] & 'h7) == 'h4) begin
    unique case ( col)
    EA_Dn:     begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h3E7; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_An:     begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h1D2; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_Ind:    begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h006; arA23[ 'h0] = `UNDF; scA3 = 'h215; end
    EA_Post:   begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h21C; arA23[ 'h0] = `UNDF; scA3 = 'h215; end
    EA_Pre:    begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h103; arA23[ 'h0] = `UNDF; scA3 = 'h215; end
    EA_Rel_An: begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h1C2; arA23[ 'h0] = `UNDF; scA3 = 'h215; end
    EA_Idx_An: begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h1E3; arA23[ 'h0] = `UNDF; scA3 = 'h215; end
    EA_Abs_W:  begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h00A; arA23[ 'h0] = `UNDF; scA3 = 'h215; end
    EA_Abs_L:  begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h1E2; arA23[ 'h0] = `UNDF; scA3 = 'h215; end
    EA_Rel_PC: begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h1C2; arA23[ 'h0] = `UNDF; scA3 = 'h215; end
    EA_Idx_PC: begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h1E3; arA23[ 'h0] = `UNDF; scA3 = 'h215; end
    EA_Imm:    begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h0EA; arA23[ 'h0] = 'h0AB; scA3 = `UNDF; end
    default:   begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    endcase
end

else if( (opcode[11:6] & 'h7) == 'h5) begin
    unique case ( col)
    EA_Dn:     begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h3EF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_An:     begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h1D6; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_Ind:    begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h006; arA23[ 'h0] = `UNDF; scA3 = 'h081; end
    EA_Post:   begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h21C; arA23[ 'h0] = `UNDF; scA3 = 'h081; end
    EA_Pre:    begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h103; arA23[ 'h0] = `UNDF; scA3 = 'h081; end
    EA_Rel_An: begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h1C2; arA23[ 'h0] = `UNDF; scA3 = 'h081; end
    EA_Idx_An: begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h1E3; arA23[ 'h0] = `UNDF; scA3 = 'h081; end
    EA_Abs_W:  begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h00A; arA23[ 'h0] = `UNDF; scA3 = 'h081; end
    EA_Abs_L:  begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h1E2; arA23[ 'h0] = `UNDF; scA3 = 'h081; end
    EA_Rel_PC: begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_Idx_PC: begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_Imm:    begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    default:   begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    endcase
end

else if( (opcode[11:6] & 'h7) == 'h7) begin
    unique case ( col)
    EA_Dn:     begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h3EF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_An:     begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h1CE; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_Ind:    begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h006; arA23[ 'h0] = `UNDF; scA3 = 'h081; end
    EA_Post:   begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h21C; arA23[ 'h0] = `UNDF; scA3 = 'h081; end
    EA_Pre:    begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h103; arA23[ 'h0] = `UNDF; scA3 = 'h081; end
    EA_Rel_An: begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h1C2; arA23[ 'h0] = `UNDF; scA3 = 'h081; end
    EA_Idx_An: begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h1E3; arA23[ 'h0] = `UNDF; scA3 = 'h081; end
    EA_Abs_W:  begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h00A; arA23[ 'h0] = `UNDF; scA3 = 'h081; end
    EA_Abs_L:  begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h1E2; arA23[ 'h0] = `UNDF; scA3 = 'h081; end
    EA_Rel_PC: begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_Idx_PC: begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_Imm:    begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    default:   begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    endcase
end

else if( (opcode[11:6] & 'h7) == 'h6) begin
    unique case ( col)
    EA_Dn:     begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h3EB; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_An:     begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h1CA; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_Ind:    begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h006; arA23[ 'h0] = `UNDF; scA3 = 'h069; end
    EA_Post:   begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h21C; arA23[ 'h0] = `UNDF; scA3 = 'h069; end
    EA_Pre:    begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h103; arA23[ 'h0] = `UNDF; scA3 = 'h069; end
    EA_Rel_An: begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h1C2; arA23[ 'h0] = `UNDF; scA3 = 'h069; end
    EA_Idx_An: begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h1E3; arA23[ 'h0] = `UNDF; scA3 = 'h069; end
    EA_Abs_W:  begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h00A; arA23[ 'h0] = `UNDF; scA3 = 'h069; end
    EA_Abs_L:  begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h1E2; arA23[ 'h0] = `UNDF; scA3 = 'h069; end
    EA_Rel_PC: begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_Idx_PC: begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_Imm:    begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    default:   begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    endcase
end

else if( opcode[11:6] == 'h20) begin
    unique case ( col)
    EA_Dn:     begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h3E7; scA3 = `UNDF; end
    EA_An:     begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_Ind:    begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h006; scA3 = 'h215; end
    EA_Post:   begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h21C; scA3 = 'h215; end
    EA_Pre:    begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h103; scA3 = 'h215; end
    EA_Rel_An: begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h1C2; scA3 = 'h215; end
    EA_Idx_An: begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h1E3; scA3 = 'h215; end
    EA_Abs_W:  begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h00A; scA3 = 'h215; end
    EA_Abs_L:  begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h1E2; scA3 = 'h215; end
    EA_Rel_PC: begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h1C2; scA3 = 'h215; end
    EA_Idx_PC: begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h1E3; scA3 = 'h215; end
    EA_Imm:    begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    default:   begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    endcase
end

else if( opcode[11:6] == 'h21) begin
    unique case ( col)
    EA_Dn:     begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h3EF; scA3 = `UNDF; end
    EA_An:     begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_Ind:    begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h006; scA3 = 'h081; end
    EA_Post:   begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h21C; scA3 = 'h081; end
    EA_Pre:    begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h103; scA3 = 'h081; end
    EA_Rel_An: begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h1C2; scA3 = 'h081; end
    EA_Idx_An: begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h1E3; scA3 = 'h081; end
    EA_Abs_W:  begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h00A; scA3 = 'h081; end
    EA_Abs_L:  begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h1E2; scA3 = 'h081; end
    EA_Rel_PC: begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_Idx_PC: begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_Imm:    begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    default:   begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    endcase
end

else if( opcode[11:6] == 'h23) begin
    unique case ( col)
    EA_Dn:     begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h3EF; scA3 = `UNDF; end
    EA_An:     begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_Ind:    begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h006; scA3 = 'h081; end
    EA_Post:   begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h21C; scA3 = 'h081; end
    EA_Pre:    begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h103; scA3 = 'h081; end
    EA_Rel_An: begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h1C2; scA3 = 'h081; end
    EA_Idx_An: begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h1E3; scA3 = 'h081; end
    EA_Abs_W:  begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h00A; scA3 = 'h081; end
    EA_Abs_L:  begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h1E2; scA3 = 'h081; end
    EA_Rel_PC: begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_Idx_PC: begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_Imm:    begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    default:   begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    endcase
end

else if( opcode[11:6] == 'h22) begin
    unique case ( col)
    EA_Dn:     begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h3EB; scA3 = `UNDF; end
    EA_An:     begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_Ind:    begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h006; scA3 = 'h069; end
    EA_Post:   begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h21C; scA3 = 'h069; end
    EA_Pre:    begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h103; scA3 = 'h069; end
    EA_Rel_An: begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h1C2; scA3 = 'h069; end
    EA_Idx_An: begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h1E3; scA3 = 'h069; end
    EA_Abs_W:  begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h00A; scA3 = 'h069; end
    EA_Abs_L:  begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h1E2; scA3 = 'h069; end
    EA_Rel_PC: begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_Idx_PC: begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_Imm:    begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    default:   begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    endcase
end

else if( opcode[11:6] == 'h30) begin
    unique case ( col)
    EA_Dn:     begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h108; scA3 = `UNDF; end
    EA_An:     begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_Ind:    begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h006; scA3 = 'h087; end
    EA_Post:   begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h21C; scA3 = 'h087; end
    EA_Pre:    begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h103; scA3 = 'h087; end
    EA_Rel_An: begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h1C2; scA3 = 'h087; end
    EA_Idx_An: begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h1E3; scA3 = 'h087; end
    EA_Abs_W:  begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h00A; scA3 = 'h087; end
    EA_Abs_L:  begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h1E2; scA3 = 'h087; end
    EA_Rel_PC: begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_Idx_PC: begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_Imm:    begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    default:   begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    endcase
end

else if( opcode[11:6] == 'h31) begin
    unique case ( col)
    EA_Dn:     begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h108; scA3 = `UNDF; end
    EA_An:     begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_Ind:    begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h006; scA3 = 'h087; end
    EA_Post:   begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h21C; scA3 = 'h087; end
    EA_Pre:    begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h103; scA3 = 'h087; end
    EA_Rel_An: begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h1C2; scA3 = 'h087; end
    EA_Idx_An: begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h1E3; scA3 = 'h087; end
    EA_Abs_W:  begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h00A; scA3 = 'h087; end
    EA_Abs_L:  begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h2B9; arA23[ 'h0] = 'h1E2; scA3 = 'h087; end
    EA_Rel_PC: begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_Idx_PC: begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_Imm:    begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    default:   begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    endcase
end

else if( opcode[11:6] == 'h32) begin
    unique case ( col)
    EA_Dn:     begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h3E0; arA23[ 'h0] = 'h104; scA3 = `UNDF; end
    EA_An:     begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_Ind:    begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h3E0; arA23[ 'h0] = 'h00B; scA3 = 'h08F; end
    EA_Post:   begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h3E0; arA23[ 'h0] = 'h00F; scA3 = 'h08F; end
    EA_Pre:    begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h3E0; arA23[ 'h0] = 'h179; scA3 = 'h08F; end
    EA_Rel_An: begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h3E0; arA23[ 'h0] = 'h1C6; scA3 = 'h08F; end
    EA_Idx_An: begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h3E0; arA23[ 'h0] = 'h1E7; scA3 = 'h08F; end
    EA_Abs_W:  begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h3E0; arA23[ 'h0] = 'h00E; scA3 = 'h08F; end
    EA_Abs_L:  begin arIll[ 'h0] = 1'b0; arA1[ 'h0] = 'h3E0; arA23[ 'h0] = 'h1E6; scA3 = 'h08F; end
    EA_Rel_PC: begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_Idx_PC: begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    EA_Imm:    begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    default:   begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end
    endcase
end

else begin arIll[ 'h0] = 1'b1; arA1[ 'h0] = `UNDF; arA23[ 'h0] = `UNDF; scA3 = `UNDF; end

end


//
// Line: 4
//
always_comb begin

if( (opcode[11:6] & 'h27) == 'h0) begin
    unique case ( col)
    EA_Dn:     begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h133; arA23[ 'h4] = `UNDF; end
    EA_An:     begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    EA_Ind:    begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h006; arA23[ 'h4] = 'h2B8; end
    EA_Post:   begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h21C; arA23[ 'h4] = 'h2B8; end
    EA_Pre:    begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h103; arA23[ 'h4] = 'h2B8; end
    EA_Rel_An: begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1C2; arA23[ 'h4] = 'h2B8; end
    EA_Idx_An: begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1E3; arA23[ 'h4] = 'h2B8; end
    EA_Abs_W:  begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h00A; arA23[ 'h4] = 'h2B8; end
    EA_Abs_L:  begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1E2; arA23[ 'h4] = 'h2B8; end
    EA_Rel_PC: begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    EA_Idx_PC: begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    EA_Imm:    begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    default:   begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    endcase
end

else if( (opcode[11:6] & 'h27) == 'h1) begin
    unique case ( col)
    EA_Dn:     begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h133; arA23[ 'h4] = `UNDF; end
    EA_An:     begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    EA_Ind:    begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h006; arA23[ 'h4] = 'h2B8; end
    EA_Post:   begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h21C; arA23[ 'h4] = 'h2B8; end
    EA_Pre:    begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h103; arA23[ 'h4] = 'h2B8; end
    EA_Rel_An: begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1C2; arA23[ 'h4] = 'h2B8; end
    EA_Idx_An: begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1E3; arA23[ 'h4] = 'h2B8; end
    EA_Abs_W:  begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h00A; arA23[ 'h4] = 'h2B8; end
    EA_Abs_L:  begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1E2; arA23[ 'h4] = 'h2B8; end
    EA_Rel_PC: begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    EA_Idx_PC: begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    EA_Imm:    begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    default:   begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    endcase
end

else if( (opcode[11:6] & 'h27) == 'h2) begin
    unique case ( col)
    EA_Dn:     begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h137; arA23[ 'h4] = `UNDF; end
    EA_An:     begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    EA_Ind:    begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h00B; arA23[ 'h4] = 'h2BC; end
    EA_Post:   begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h00F; arA23[ 'h4] = 'h2BC; end
    EA_Pre:    begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h179; arA23[ 'h4] = 'h2BC; end
    EA_Rel_An: begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1C6; arA23[ 'h4] = 'h2BC; end
    EA_Idx_An: begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1E7; arA23[ 'h4] = 'h2BC; end
    EA_Abs_W:  begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h00E; arA23[ 'h4] = 'h2BC; end
    EA_Abs_L:  begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1E6; arA23[ 'h4] = 'h2BC; end
    EA_Rel_PC: begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    EA_Idx_PC: begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    EA_Imm:    begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    default:   begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    endcase
end

else if( opcode[11:6] == 'h3) begin
    unique case ( col)
    EA_Dn:     begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h3A5; arA23[ 'h4] = `UNDF; end
    EA_An:     begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    EA_Ind:    begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h006; arA23[ 'h4] = 'h3A1; end
    EA_Post:   begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h21C; arA23[ 'h4] = 'h3A1; end
    EA_Pre:    begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h103; arA23[ 'h4] = 'h3A1; end
    EA_Rel_An: begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1C2; arA23[ 'h4] = 'h3A1; end
    EA_Idx_An: begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1E3; arA23[ 'h4] = 'h3A1; end
    EA_Abs_W:  begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h00A; arA23[ 'h4] = 'h3A1; end
    EA_Abs_L:  begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1E2; arA23[ 'h4] = 'h3A1; end
    EA_Rel_PC: begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    EA_Idx_PC: begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    EA_Imm:    begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    default:   begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    endcase
end

else if( opcode[11:6] == 'h13) begin
    unique case ( col)
    EA_Dn:     begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h301; arA23[ 'h4] = `UNDF; end
    EA_An:     begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    EA_Ind:    begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h006; arA23[ 'h4] = 'h159; end
    EA_Post:   begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h21C; arA23[ 'h4] = 'h159; end
    EA_Pre:    begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h103; arA23[ 'h4] = 'h159; end
    EA_Rel_An: begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1C2; arA23[ 'h4] = 'h159; end
    EA_Idx_An: begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1E3; arA23[ 'h4] = 'h159; end
    EA_Abs_W:  begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h00A; arA23[ 'h4] = 'h159; end
    EA_Abs_L:  begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1E2; arA23[ 'h4] = 'h159; end
    EA_Rel_PC: begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1C2; arA23[ 'h4] = 'h159; end
    EA_Idx_PC: begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1E3; arA23[ 'h4] = 'h159; end
    EA_Imm:    begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h0EA; arA23[ 'h4] = 'h301; end
    default:   begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    endcase
end

else if( opcode[11:6] == 'h1B) begin
    unique case ( col)
    EA_Dn:     begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h301; arA23[ 'h4] = `UNDF; end
    EA_An:     begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    EA_Ind:    begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h006; arA23[ 'h4] = 'h159; end
    EA_Post:   begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h21C; arA23[ 'h4] = 'h159; end
    EA_Pre:    begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h103; arA23[ 'h4] = 'h159; end
    EA_Rel_An: begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1C2; arA23[ 'h4] = 'h159; end
    EA_Idx_An: begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1E3; arA23[ 'h4] = 'h159; end
    EA_Abs_W:  begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h00A; arA23[ 'h4] = 'h159; end
    EA_Abs_L:  begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1E2; arA23[ 'h4] = 'h159; end
    EA_Rel_PC: begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1C2; arA23[ 'h4] = 'h159; end
    EA_Idx_PC: begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1E3; arA23[ 'h4] = 'h159; end
    EA_Imm:    begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h0EA; arA23[ 'h4] = 'h301; end
    default:   begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    endcase
end

else if( opcode[11:6] == 'h20) begin
    unique case ( col)
    EA_Dn:     begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h13B; arA23[ 'h4] = `UNDF; end
    EA_An:     begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    EA_Ind:    begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h006; arA23[ 'h4] = 'h15C; end
    EA_Post:   begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h21C; arA23[ 'h4] = 'h15C; end
    EA_Pre:    begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h103; arA23[ 'h4] = 'h15C; end
    EA_Rel_An: begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1C2; arA23[ 'h4] = 'h15C; end
    EA_Idx_An: begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1E3; arA23[ 'h4] = 'h15C; end
    EA_Abs_W:  begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h00A; arA23[ 'h4] = 'h15C; end
    EA_Abs_L:  begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1E2; arA23[ 'h4] = 'h15C; end
    EA_Rel_PC: begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    EA_Idx_PC: begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    EA_Imm:    begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    default:   begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    endcase
end

else if( opcode[11:6] == 'h21) begin
    unique case ( col)
    EA_Dn:     begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h341; arA23[ 'h4] = `UNDF; end
    EA_An:     begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    EA_Ind:    begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h17C; arA23[ 'h4] = `UNDF; end
    EA_Post:   begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    EA_Pre:    begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    EA_Rel_An: begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h17D; arA23[ 'h4] = `UNDF; end
    EA_Idx_An: begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1FF; arA23[ 'h4] = `UNDF; end
    EA_Abs_W:  begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h178; arA23[ 'h4] = `UNDF; end
    EA_Abs_L:  begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1FA; arA23[ 'h4] = `UNDF; end
    EA_Rel_PC: begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h17D; arA23[ 'h4] = `UNDF; end
    EA_Idx_PC: begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1FF; arA23[ 'h4] = `UNDF; end
    EA_Imm:    begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    default:   begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    endcase
end

else if( opcode[11:6] == 'h22) begin
    unique case ( col)
    EA_Dn:     begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h133; arA23[ 'h4] = `UNDF; end
    EA_An:     begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    EA_Ind:    begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h3A0; arA23[ 'h4] = `UNDF; end
    EA_Post:   begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    EA_Pre:    begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h3A4; arA23[ 'h4] = `UNDF; end
    EA_Rel_An: begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1F1; arA23[ 'h4] = `UNDF; end
    EA_Idx_An: begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h325; arA23[ 'h4] = `UNDF; end
    EA_Abs_W:  begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1ED; arA23[ 'h4] = `UNDF; end
    EA_Abs_L:  begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1E5; arA23[ 'h4] = `UNDF; end
    EA_Rel_PC: begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    EA_Idx_PC: begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    EA_Imm:    begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    default:   begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    endcase
end

else if( opcode[11:6] == 'h23) begin
    unique case ( col)
    EA_Dn:     begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h232; arA23[ 'h4] = `UNDF; end
    EA_An:     begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    EA_Ind:    begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h3A0; arA23[ 'h4] = `UNDF; end
    EA_Post:   begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    EA_Pre:    begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h3A4; arA23[ 'h4] = `UNDF; end
    EA_Rel_An: begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1F1; arA23[ 'h4] = `UNDF; end
    EA_Idx_An: begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h325; arA23[ 'h4] = `UNDF; end
    EA_Abs_W:  begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1ED; arA23[ 'h4] = `UNDF; end
    EA_Abs_L:  begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1E5; arA23[ 'h4] = `UNDF; end
    EA_Rel_PC: begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    EA_Idx_PC: begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    EA_Imm:    begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    default:   begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    endcase
end

else if( opcode[11:6] == 'h28) begin
    unique case ( col)
    EA_Dn:     begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h12D; arA23[ 'h4] = `UNDF; end
    EA_An:     begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    EA_Ind:    begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h006; arA23[ 'h4] = 'h3C3; end
    EA_Post:   begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h21C; arA23[ 'h4] = 'h3C3; end
    EA_Pre:    begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h103; arA23[ 'h4] = 'h3C3; end
    EA_Rel_An: begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1C2; arA23[ 'h4] = 'h3C3; end
    EA_Idx_An: begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1E3; arA23[ 'h4] = 'h3C3; end
    EA_Abs_W:  begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h00A; arA23[ 'h4] = 'h3C3; end
    EA_Abs_L:  begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1E2; arA23[ 'h4] = 'h3C3; end
    EA_Rel_PC: begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    EA_Idx_PC: begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    EA_Imm:    begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    default:   begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    endcase
end

else if( opcode[11:6] == 'h29) begin
    unique case ( col)
    EA_Dn:     begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h12D; arA23[ 'h4] = `UNDF; end
    EA_An:     begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    EA_Ind:    begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h006; arA23[ 'h4] = 'h3C3; end
    EA_Post:   begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h21C; arA23[ 'h4] = 'h3C3; end
    EA_Pre:    begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h103; arA23[ 'h4] = 'h3C3; end
    EA_Rel_An: begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1C2; arA23[ 'h4] = 'h3C3; end
    EA_Idx_An: begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1E3; arA23[ 'h4] = 'h3C3; end
    EA_Abs_W:  begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h00A; arA23[ 'h4] = 'h3C3; end
    EA_Abs_L:  begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1E2; arA23[ 'h4] = 'h3C3; end
    EA_Rel_PC: begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    EA_Idx_PC: begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    EA_Imm:    begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    default:   begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    endcase
end

else if( opcode[11:6] == 'h2A) begin
    unique case ( col)
    EA_Dn:     begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h125; arA23[ 'h4] = `UNDF; end
    EA_An:     begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    EA_Ind:    begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h00B; arA23[ 'h4] = 'h3CB; end
    EA_Post:   begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h00F; arA23[ 'h4] = 'h3CB; end
    EA_Pre:    begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h179; arA23[ 'h4] = 'h3CB; end
    EA_Rel_An: begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1C6; arA23[ 'h4] = 'h3CB; end
    EA_Idx_An: begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1E7; arA23[ 'h4] = 'h3CB; end
    EA_Abs_W:  begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h00E; arA23[ 'h4] = 'h3CB; end
    EA_Abs_L:  begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1E6; arA23[ 'h4] = 'h3CB; end
    EA_Rel_PC: begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    EA_Idx_PC: begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    EA_Imm:    begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    default:   begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    endcase
end

else if( opcode[11:6] == 'h2B) begin
    unique case ( col)
    EA_Dn:     begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h345; arA23[ 'h4] = `UNDF; end
    EA_An:     begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    EA_Ind:    begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h006; arA23[ 'h4] = 'h343; end
    EA_Post:   begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h21C; arA23[ 'h4] = 'h343; end
    EA_Pre:    begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h103; arA23[ 'h4] = 'h343; end
    EA_Rel_An: begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1C2; arA23[ 'h4] = 'h343; end
    EA_Idx_An: begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1E3; arA23[ 'h4] = 'h343; end
    EA_Abs_W:  begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h00A; arA23[ 'h4] = 'h343; end
    EA_Abs_L:  begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1E2; arA23[ 'h4] = 'h343; end
    EA_Rel_PC: begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    EA_Idx_PC: begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    EA_Imm:    begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    default:   begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    endcase
end

else if( (opcode[11:6] & 'h3E) == 'h32) begin
    unique case ( col)
    EA_Dn:     begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    EA_An:     begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    EA_Ind:    begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h127; arA23[ 'h4] = `UNDF; end
    EA_Post:   begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h123; arA23[ 'h4] = `UNDF; end
    EA_Pre:    begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    EA_Rel_An: begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1FD; arA23[ 'h4] = `UNDF; end
    EA_Idx_An: begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1F5; arA23[ 'h4] = `UNDF; end
    EA_Abs_W:  begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1F9; arA23[ 'h4] = `UNDF; end
    EA_Abs_L:  begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1E9; arA23[ 'h4] = `UNDF; end
    EA_Rel_PC: begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1FD; arA23[ 'h4] = `UNDF; end
    EA_Idx_PC: begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1F5; arA23[ 'h4] = `UNDF; end
    EA_Imm:    begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    default:   begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    endcase
end

else if( (opcode[11:6] & 'h7) == 'h6) begin
    unique case ( col)
    EA_Dn:     begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h152; arA23[ 'h4] = `UNDF; end
    EA_An:     begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    EA_Ind:    begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h006; arA23[ 'h4] = 'h151; end
    EA_Post:   begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h21C; arA23[ 'h4] = 'h151; end
    EA_Pre:    begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h103; arA23[ 'h4] = 'h151; end
    EA_Rel_An: begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1C2; arA23[ 'h4] = 'h151; end
    EA_Idx_An: begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1E3; arA23[ 'h4] = 'h151; end
    EA_Abs_W:  begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h00A; arA23[ 'h4] = 'h151; end
    EA_Abs_L:  begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1E2; arA23[ 'h4] = 'h151; end
    EA_Rel_PC: begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1C2; arA23[ 'h4] = 'h151; end
    EA_Idx_PC: begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1E3; arA23[ 'h4] = 'h151; end
    EA_Imm:    begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h0EA; arA23[ 'h4] = 'h152; end
    default:   begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    endcase
end

else if( (opcode[11:6] & 'h7) == 'h7) begin
    unique case ( col)
    EA_Dn:     begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    EA_An:     begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    EA_Ind:    begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h2F1; arA23[ 'h4] = `UNDF; end
    EA_Post:   begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    EA_Pre:    begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    EA_Rel_An: begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h2F2; arA23[ 'h4] = `UNDF; end
    EA_Idx_An: begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1FB; arA23[ 'h4] = `UNDF; end
    EA_Abs_W:  begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h275; arA23[ 'h4] = `UNDF; end
    EA_Abs_L:  begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h3E4; arA23[ 'h4] = `UNDF; end
    EA_Rel_PC: begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h2F2; arA23[ 'h4] = `UNDF; end
    EA_Idx_PC: begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1FB; arA23[ 'h4] = `UNDF; end
    EA_Imm:    begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    default:   begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    endcase
end

else if( opcode[11:6] == 'h3A) begin
    unique case ( col)
    EA_Dn:     begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    EA_An:     begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    EA_Ind:    begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h273; arA23[ 'h4] = `UNDF; end
    EA_Post:   begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    EA_Pre:    begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    EA_Rel_An: begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h2B0; arA23[ 'h4] = `UNDF; end
    EA_Idx_An: begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1F3; arA23[ 'h4] = `UNDF; end
    EA_Abs_W:  begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h293; arA23[ 'h4] = `UNDF; end
    EA_Abs_L:  begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1F2; arA23[ 'h4] = `UNDF; end
    EA_Rel_PC: begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h2B0; arA23[ 'h4] = `UNDF; end
    EA_Idx_PC: begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1F3; arA23[ 'h4] = `UNDF; end
    EA_Imm:    begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    default:   begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    endcase
end

else if( opcode[11:6] == 'h3B) begin
    unique case ( col)
    EA_Dn:     begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    EA_An:     begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    EA_Ind:    begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h255; arA23[ 'h4] = `UNDF; end
    EA_Post:   begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    EA_Pre:    begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    EA_Rel_An: begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h2B4; arA23[ 'h4] = `UNDF; end
    EA_Idx_An: begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1F7; arA23[ 'h4] = `UNDF; end
    EA_Abs_W:  begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h297; arA23[ 'h4] = `UNDF; end
    EA_Abs_L:  begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1F6; arA23[ 'h4] = `UNDF; end
    EA_Rel_PC: begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h2B4; arA23[ 'h4] = `UNDF; end
    EA_Idx_PC: begin arIll[ 'h4] = 1'b0; arA1[ 'h4] = 'h1F7; arA23[ 'h4] = `UNDF; end
    EA_Imm:    begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    default:   begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end
    endcase
end

else if( opcode[11:6] == 'h39) begin
     arIll[ 'h4] = illMisc; arA1[ 'h4] = a1Misc   ; arA23[ 'h4] = `UNDF;
end

else begin arIll[ 'h4] = 1'b1; arA1[ 'h4] = `UNDF; arA23[ 'h4] = `UNDF; end

end

always_comb begin

//
// Line: 1
//
unique case( movEa)

0: // Row: 0
    unique case ( col)
    EA_Dn:     begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h121; arA23[ 'h1] = `UNDF; end
    EA_An:     begin arIll[ 'h1] = 1'b1; arA1[ 'h1] = `UNDF; arA23[ 'h1] = `UNDF; end
    EA_Ind:    begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h006; arA23[ 'h1] = 'h29B; end
    EA_Post:   begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h21C; arA23[ 'h1] = 'h29B; end
    EA_Pre:    begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h103; arA23[ 'h1] = 'h29B; end
    EA_Rel_An: begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h1C2; arA23[ 'h1] = 'h29B; end
    EA_Idx_An: begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h1E3; arA23[ 'h1] = 'h29B; end
    EA_Abs_W:  begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h00A; arA23[ 'h1] = 'h29B; end
    EA_Abs_L:  begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h1E2; arA23[ 'h1] = 'h29B; end
    EA_Rel_PC: begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h1C2; arA23[ 'h1] = 'h29B; end
    EA_Idx_PC: begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h1E3; arA23[ 'h1] = 'h29B; end
    EA_Imm:    begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h0EA; arA23[ 'h1] = 'h121; end
    default:   begin arIll[ 'h1] = 1'b1; arA1[ 'h1] = `UNDF; arA23[ 'h1] = `UNDF; end
    endcase

2: // Row: 2
    unique case ( col)
    EA_Dn:     begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h2FA; arA23[ 'h1] = `UNDF; end
    EA_An:     begin arIll[ 'h1] = 1'b1; arA1[ 'h1] = `UNDF; arA23[ 'h1] = `UNDF; end
    EA_Ind:    begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h006; arA23[ 'h1] = 'h3AB; end
    EA_Post:   begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h21C; arA23[ 'h1] = 'h3AB; end
    EA_Pre:    begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h103; arA23[ 'h1] = 'h3AB; end
    EA_Rel_An: begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h1C2; arA23[ 'h1] = 'h3AB; end
    EA_Idx_An: begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h1E3; arA23[ 'h1] = 'h3AB; end
    EA_Abs_W:  begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h00A; arA23[ 'h1] = 'h3AB; end
    EA_Abs_L:  begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h1E2; arA23[ 'h1] = 'h3AB; end
    EA_Rel_PC: begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h1C2; arA23[ 'h1] = 'h3AB; end
    EA_Idx_PC: begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h1E3; arA23[ 'h1] = 'h3AB; end
    EA_Imm:    begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h0EA; arA23[ 'h1] = 'h2FA; end
    default:   begin arIll[ 'h1] = 1'b1; arA1[ 'h1] = `UNDF; arA23[ 'h1] = `UNDF; end
    endcase

3: // Row: 3
    unique case ( col)
    EA_Dn:     begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h2FE; arA23[ 'h1] = `UNDF; end
    EA_An:     begin arIll[ 'h1] = 1'b1; arA1[ 'h1] = `UNDF; arA23[ 'h1] = `UNDF; end
    EA_Ind:    begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h006; arA23[ 'h1] = 'h3AF; end
    EA_Post:   begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h21C; arA23[ 'h1] = 'h3AF; end
    EA_Pre:    begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h103; arA23[ 'h1] = 'h3AF; end
    EA_Rel_An: begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h1C2; arA23[ 'h1] = 'h3AF; end
    EA_Idx_An: begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h1E3; arA23[ 'h1] = 'h3AF; end
    EA_Abs_W:  begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h00A; arA23[ 'h1] = 'h3AF; end
    EA_Abs_L:  begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h1E2; arA23[ 'h1] = 'h3AF; end
    EA_Rel_PC: begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h1C2; arA23[ 'h1] = 'h3AF; end
    EA_Idx_PC: begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h1E3; arA23[ 'h1] = 'h3AF; end
    EA_Imm:    begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h0EA; arA23[ 'h1] = 'h2FE; end
    default:   begin arIll[ 'h1] = 1'b1; arA1[ 'h1] = `UNDF; arA23[ 'h1] = `UNDF; end
    endcase

4: // Row: 4
    unique case ( col)
    EA_Dn:     begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h2F8; arA23[ 'h1] = `UNDF; end
    EA_An:     begin arIll[ 'h1] = 1'b1; arA1[ 'h1] = `UNDF; arA23[ 'h1] = `UNDF; end
    EA_Ind:    begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h006; arA23[ 'h1] = 'h38B; end
    EA_Post:   begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h21C; arA23[ 'h1] = 'h38B; end
    EA_Pre:    begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h103; arA23[ 'h1] = 'h38B; end
    EA_Rel_An: begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h1C2; arA23[ 'h1] = 'h38B; end
    EA_Idx_An: begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h1E3; arA23[ 'h1] = 'h38B; end
    EA_Abs_W:  begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h00A; arA23[ 'h1] = 'h38B; end
    EA_Abs_L:  begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h1E2; arA23[ 'h1] = 'h38B; end
    EA_Rel_PC: begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h1C2; arA23[ 'h1] = 'h38B; end
    EA_Idx_PC: begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h1E3; arA23[ 'h1] = 'h38B; end
    EA_Imm:    begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h0EA; arA23[ 'h1] = 'h2F8; end
    default:   begin arIll[ 'h1] = 1'b1; arA1[ 'h1] = `UNDF; arA23[ 'h1] = `UNDF; end
    endcase

5: // Row: 5
    unique case ( col)
    EA_Dn:     begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h2DA; arA23[ 'h1] = `UNDF; end
    EA_An:     begin arIll[ 'h1] = 1'b1; arA1[ 'h1] = `UNDF; arA23[ 'h1] = `UNDF; end
    EA_Ind:    begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h006; arA23[ 'h1] = 'h38A; end
    EA_Post:   begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h21C; arA23[ 'h1] = 'h38A; end
    EA_Pre:    begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h103; arA23[ 'h1] = 'h38A; end
    EA_Rel_An: begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h1C2; arA23[ 'h1] = 'h38A; end
    EA_Idx_An: begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h1E3; arA23[ 'h1] = 'h38A; end
    EA_Abs_W:  begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h00A; arA23[ 'h1] = 'h38A; end
    EA_Abs_L:  begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h1E2; arA23[ 'h1] = 'h38A; end
    EA_Rel_PC: begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h1C2; arA23[ 'h1] = 'h38A; end
    EA_Idx_PC: begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h1E3; arA23[ 'h1] = 'h38A; end
    EA_Imm:    begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h0EA; arA23[ 'h1] = 'h2DA; end
    default:   begin arIll[ 'h1] = 1'b1; arA1[ 'h1] = `UNDF; arA23[ 'h1] = `UNDF; end
    endcase

6: // Row: 6
    unique case ( col)
    EA_Dn:     begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h1EB; arA23[ 'h1] = `UNDF; end
    EA_An:     begin arIll[ 'h1] = 1'b1; arA1[ 'h1] = `UNDF; arA23[ 'h1] = `UNDF; end
    EA_Ind:    begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h006; arA23[ 'h1] = 'h298; end
    EA_Post:   begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h21C; arA23[ 'h1] = 'h298; end
    EA_Pre:    begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h103; arA23[ 'h1] = 'h298; end
    EA_Rel_An: begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h1C2; arA23[ 'h1] = 'h298; end
    EA_Idx_An: begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h1E3; arA23[ 'h1] = 'h298; end
    EA_Abs_W:  begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h00A; arA23[ 'h1] = 'h298; end
    EA_Abs_L:  begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h1E2; arA23[ 'h1] = 'h298; end
    EA_Rel_PC: begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h1C2; arA23[ 'h1] = 'h298; end
    EA_Idx_PC: begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h1E3; arA23[ 'h1] = 'h298; end
    EA_Imm:    begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h0EA; arA23[ 'h1] = 'h1EB; end
    default:   begin arIll[ 'h1] = 1'b1; arA1[ 'h1] = `UNDF; arA23[ 'h1] = `UNDF; end
    endcase

7: // Row: 7
    unique case ( col)
    EA_Dn:     begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h2D9; arA23[ 'h1] = `UNDF; end
    EA_An:     begin arIll[ 'h1] = 1'b1; arA1[ 'h1] = `UNDF; arA23[ 'h1] = `UNDF; end
    EA_Ind:    begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h006; arA23[ 'h1] = 'h388; end
    EA_Post:   begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h21C; arA23[ 'h1] = 'h388; end
    EA_Pre:    begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h103; arA23[ 'h1] = 'h388; end
    EA_Rel_An: begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h1C2; arA23[ 'h1] = 'h388; end
    EA_Idx_An: begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h1E3; arA23[ 'h1] = 'h388; end
    EA_Abs_W:  begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h00A; arA23[ 'h1] = 'h388; end
    EA_Abs_L:  begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h1E2; arA23[ 'h1] = 'h388; end
    EA_Rel_PC: begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h1C2; arA23[ 'h1] = 'h388; end
    EA_Idx_PC: begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h1E3; arA23[ 'h1] = 'h388; end
    EA_Imm:    begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h0EA; arA23[ 'h1] = 'h2D9; end
    default:   begin arIll[ 'h1] = 1'b1; arA1[ 'h1] = `UNDF; arA23[ 'h1] = `UNDF; end
    endcase

8: // Row: 8
    unique case ( col)
    EA_Dn:     begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h1EA; arA23[ 'h1] = `UNDF; end
    EA_An:     begin arIll[ 'h1] = 1'b1; arA1[ 'h1] = `UNDF; arA23[ 'h1] = `UNDF; end
    EA_Ind:    begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h006; arA23[ 'h1] = 'h32B; end
    EA_Post:   begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h21C; arA23[ 'h1] = 'h32B; end
    EA_Pre:    begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h103; arA23[ 'h1] = 'h32B; end
    EA_Rel_An: begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h1C2; arA23[ 'h1] = 'h32B; end
    EA_Idx_An: begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h1E3; arA23[ 'h1] = 'h32B; end
    EA_Abs_W:  begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h00A; arA23[ 'h1] = 'h32B; end
    EA_Abs_L:  begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h1E2; arA23[ 'h1] = 'h32B; end
    EA_Rel_PC: begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h1C2; arA23[ 'h1] = 'h32B; end
    EA_Idx_PC: begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h1E3; arA23[ 'h1] = 'h32B; end
    EA_Imm:    begin arIll[ 'h1] = 1'b0; arA1[ 'h1] = 'h0EA; arA23[ 'h1] = 'h1EA; end
    default:   begin arIll[ 'h1] = 1'b1; arA1[ 'h1] = `UNDF; arA23[ 'h1] = `UNDF; end
    endcase
default:  begin arIll[ 'h1] = 1'b1; arA1[ 'h1] = `UNDF; arA23[ 'h1] = `UNDF; end
endcase

//
// Line: 2
//
unique case( movEa)

0: // Row: 0
    unique case ( col)
    EA_Dn:     begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h129; arA23[ 'h2] = `UNDF; end
    EA_An:     begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h129; arA23[ 'h2] = `UNDF; end
    EA_Ind:    begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h00B; arA23[ 'h2] = 'h29F; end
    EA_Post:   begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h00F; arA23[ 'h2] = 'h29F; end
    EA_Pre:    begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h179; arA23[ 'h2] = 'h29F; end
    EA_Rel_An: begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h1C6; arA23[ 'h2] = 'h29F; end
    EA_Idx_An: begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h1E7; arA23[ 'h2] = 'h29F; end
    EA_Abs_W:  begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h00E; arA23[ 'h2] = 'h29F; end
    EA_Abs_L:  begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h1E6; arA23[ 'h2] = 'h29F; end
    EA_Rel_PC: begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h1C6; arA23[ 'h2] = 'h29F; end
    EA_Idx_PC: begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h1E7; arA23[ 'h2] = 'h29F; end
    EA_Imm:    begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h0A7; arA23[ 'h2] = 'h129; end
    default:   begin arIll[ 'h2] = 1'b1; arA1[ 'h2] = `UNDF; arA23[ 'h2] = `UNDF; end
    endcase

1: // Row: 1
    unique case ( col)
    EA_Dn:     begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h129; arA23[ 'h2] = `UNDF; end
    EA_An:     begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h129; arA23[ 'h2] = `UNDF; end
    EA_Ind:    begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h00B; arA23[ 'h2] = 'h29F; end
    EA_Post:   begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h00F; arA23[ 'h2] = 'h29F; end
    EA_Pre:    begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h179; arA23[ 'h2] = 'h29F; end
    EA_Rel_An: begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h1C6; arA23[ 'h2] = 'h29F; end
    EA_Idx_An: begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h1E7; arA23[ 'h2] = 'h29F; end
    EA_Abs_W:  begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h00E; arA23[ 'h2] = 'h29F; end
    EA_Abs_L:  begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h1E6; arA23[ 'h2] = 'h29F; end
    EA_Rel_PC: begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h1C6; arA23[ 'h2] = 'h29F; end
    EA_Idx_PC: begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h1E7; arA23[ 'h2] = 'h29F; end
    EA_Imm:    begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h0A7; arA23[ 'h2] = 'h129; end
    default:   begin arIll[ 'h2] = 1'b1; arA1[ 'h2] = `UNDF; arA23[ 'h2] = `UNDF; end
    endcase

2: // Row: 2
    unique case ( col)
    EA_Dn:     begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h2F9; arA23[ 'h2] = `UNDF; end
    EA_An:     begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h2F9; arA23[ 'h2] = `UNDF; end
    EA_Ind:    begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h00B; arA23[ 'h2] = 'h3A9; end
    EA_Post:   begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h00F; arA23[ 'h2] = 'h3A9; end
    EA_Pre:    begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h179; arA23[ 'h2] = 'h3A9; end
    EA_Rel_An: begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h1C6; arA23[ 'h2] = 'h3A9; end
    EA_Idx_An: begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h1E7; arA23[ 'h2] = 'h3A9; end
    EA_Abs_W:  begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h00E; arA23[ 'h2] = 'h3A9; end
    EA_Abs_L:  begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h1E6; arA23[ 'h2] = 'h3A9; end
    EA_Rel_PC: begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h1C6; arA23[ 'h2] = 'h3A9; end
    EA_Idx_PC: begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h1E7; arA23[ 'h2] = 'h3A9; end
    EA_Imm:    begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h0A7; arA23[ 'h2] = 'h2F9; end
    default:   begin arIll[ 'h2] = 1'b1; arA1[ 'h2] = `UNDF; arA23[ 'h2] = `UNDF; end
    endcase

3: // Row: 3
    unique case ( col)
    EA_Dn:     begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h2FD; arA23[ 'h2] = `UNDF; end
    EA_An:     begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h2FD; arA23[ 'h2] = `UNDF; end
    EA_Ind:    begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h00B; arA23[ 'h2] = 'h3AD; end
    EA_Post:   begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h00F; arA23[ 'h2] = 'h3AD; end
    EA_Pre:    begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h179; arA23[ 'h2] = 'h3AD; end
    EA_Rel_An: begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h1C6; arA23[ 'h2] = 'h3AD; end
    EA_Idx_An: begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h1E7; arA23[ 'h2] = 'h3AD; end
    EA_Abs_W:  begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h00E; arA23[ 'h2] = 'h3AD; end
    EA_Abs_L:  begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h1E6; arA23[ 'h2] = 'h3AD; end
    EA_Rel_PC: begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h1C6; arA23[ 'h2] = 'h3AD; end
    EA_Idx_PC: begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h1E7; arA23[ 'h2] = 'h3AD; end
    EA_Imm:    begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h0A7; arA23[ 'h2] = 'h2FD; end
    default:   begin arIll[ 'h2] = 1'b1; arA1[ 'h2] = `UNDF; arA23[ 'h2] = `UNDF; end
    endcase

4: // Row: 4
    unique case ( col)
    EA_Dn:     begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h2FC; arA23[ 'h2] = `UNDF; end
    EA_An:     begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h2FC; arA23[ 'h2] = `UNDF; end
    EA_Ind:    begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h00B; arA23[ 'h2] = 'h38F; end
    EA_Post:   begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h00F; arA23[ 'h2] = 'h38F; end
    EA_Pre:    begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h179; arA23[ 'h2] = 'h38F; end
    EA_Rel_An: begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h1C6; arA23[ 'h2] = 'h38F; end
    EA_Idx_An: begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h1E7; arA23[ 'h2] = 'h38F; end
    EA_Abs_W:  begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h00E; arA23[ 'h2] = 'h38F; end
    EA_Abs_L:  begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h1E6; arA23[ 'h2] = 'h38F; end
    EA_Rel_PC: begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h1C6; arA23[ 'h2] = 'h38F; end
    EA_Idx_PC: begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h1E7; arA23[ 'h2] = 'h38F; end
    EA_Imm:    begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h0A7; arA23[ 'h2] = 'h2FC; end
    default:   begin arIll[ 'h2] = 1'b1; arA1[ 'h2] = `UNDF; arA23[ 'h2] = `UNDF; end
    endcase

5: // Row: 5
    unique case ( col)
    EA_Dn:     begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h2DE; arA23[ 'h2] = `UNDF; end
    EA_An:     begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h2DE; arA23[ 'h2] = `UNDF; end
    EA_Ind:    begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h00B; arA23[ 'h2] = 'h38E; end
    EA_Post:   begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h00F; arA23[ 'h2] = 'h38E; end
    EA_Pre:    begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h179; arA23[ 'h2] = 'h38E; end
    EA_Rel_An: begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h1C6; arA23[ 'h2] = 'h38E; end
    EA_Idx_An: begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h1E7; arA23[ 'h2] = 'h38E; end
    EA_Abs_W:  begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h00E; arA23[ 'h2] = 'h38E; end
    EA_Abs_L:  begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h1E6; arA23[ 'h2] = 'h38E; end
    EA_Rel_PC: begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h1C6; arA23[ 'h2] = 'h38E; end
    EA_Idx_PC: begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h1E7; arA23[ 'h2] = 'h38E; end
    EA_Imm:    begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h0A7; arA23[ 'h2] = 'h2DE; end
    default:   begin arIll[ 'h2] = 1'b1; arA1[ 'h2] = `UNDF; arA23[ 'h2] = `UNDF; end
    endcase

6: // Row: 6
    unique case ( col)
    EA_Dn:     begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h1EF; arA23[ 'h2] = `UNDF; end
    EA_An:     begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h1EF; arA23[ 'h2] = `UNDF; end
    EA_Ind:    begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h00B; arA23[ 'h2] = 'h29C; end
    EA_Post:   begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h00F; arA23[ 'h2] = 'h29C; end
    EA_Pre:    begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h179; arA23[ 'h2] = 'h29C; end
    EA_Rel_An: begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h1C6; arA23[ 'h2] = 'h29C; end
    EA_Idx_An: begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h1E7; arA23[ 'h2] = 'h29C; end
    EA_Abs_W:  begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h00E; arA23[ 'h2] = 'h29C; end
    EA_Abs_L:  begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h1E6; arA23[ 'h2] = 'h29C; end
    EA_Rel_PC: begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h1C6; arA23[ 'h2] = 'h29C; end
    EA_Idx_PC: begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h1E7; arA23[ 'h2] = 'h29C; end
    EA_Imm:    begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h0A7; arA23[ 'h2] = 'h1EF; end
    default:   begin arIll[ 'h2] = 1'b1; arA1[ 'h2] = `UNDF; arA23[ 'h2] = `UNDF; end
    endcase

7: // Row: 7
    unique case ( col)
    EA_Dn:     begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h2DD; arA23[ 'h2] = `UNDF; end
    EA_An:     begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h2DD; arA23[ 'h2] = `UNDF; end
    EA_Ind:    begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h00B; arA23[ 'h2] = 'h38C; end
    EA_Post:   begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h00F; arA23[ 'h2] = 'h38C; end
    EA_Pre:    begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h179; arA23[ 'h2] = 'h38C; end
    EA_Rel_An: begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h1C6; arA23[ 'h2] = 'h38C; end
    EA_Idx_An: begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h1E7; arA23[ 'h2] = 'h38C; end
    EA_Abs_W:  begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h00E; arA23[ 'h2] = 'h38C; end
    EA_Abs_L:  begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h1E6; arA23[ 'h2] = 'h38C; end
    EA_Rel_PC: begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h1C6; arA23[ 'h2] = 'h38C; end
    EA_Idx_PC: begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h1E7; arA23[ 'h2] = 'h38C; end
    EA_Imm:    begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h0A7; arA23[ 'h2] = 'h2DD; end
    default:   begin arIll[ 'h2] = 1'b1; arA1[ 'h2] = `UNDF; arA23[ 'h2] = `UNDF; end
    endcase

8: // Row: 8
    unique case ( col)
    EA_Dn:     begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h1EE; arA23[ 'h2] = `UNDF; end
    EA_An:     begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h1EE; arA23[ 'h2] = `UNDF; end
    EA_Ind:    begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h00B; arA23[ 'h2] = 'h30F; end
    EA_Post:   begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h00F; arA23[ 'h2] = 'h30F; end
    EA_Pre:    begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h179; arA23[ 'h2] = 'h30F; end
    EA_Rel_An: begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h1C6; arA23[ 'h2] = 'h30F; end
    EA_Idx_An: begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h1E7; arA23[ 'h2] = 'h30F; end
    EA_Abs_W:  begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h00E; arA23[ 'h2] = 'h30F; end
    EA_Abs_L:  begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h1E6; arA23[ 'h2] = 'h30F; end
    EA_Rel_PC: begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h1C6; arA23[ 'h2] = 'h30F; end
    EA_Idx_PC: begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h1E7; arA23[ 'h2] = 'h30F; end
    EA_Imm:    begin arIll[ 'h2] = 1'b0; arA1[ 'h2] = 'h0A7; arA23[ 'h2] = 'h1EE; end
    default:   begin arIll[ 'h2] = 1'b1; arA1[ 'h2] = `UNDF; arA23[ 'h2] = `UNDF; end
    endcase
default:  begin arIll[ 'h2] = 1'b1; arA1[ 'h2] = `UNDF; arA23[ 'h2] = `UNDF; end
endcase

//
// Line: 3
//
unique case( movEa)

0: // Row: 0
    unique case ( col)
    EA_Dn:     begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h121; arA23[ 'h3] = `UNDF; end
    EA_An:     begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h121; arA23[ 'h3] = `UNDF; end
    EA_Ind:    begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h006; arA23[ 'h3] = 'h29B; end
    EA_Post:   begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h21C; arA23[ 'h3] = 'h29B; end
    EA_Pre:    begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h103; arA23[ 'h3] = 'h29B; end
    EA_Rel_An: begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h1C2; arA23[ 'h3] = 'h29B; end
    EA_Idx_An: begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h1E3; arA23[ 'h3] = 'h29B; end
    EA_Abs_W:  begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h00A; arA23[ 'h3] = 'h29B; end
    EA_Abs_L:  begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h1E2; arA23[ 'h3] = 'h29B; end
    EA_Rel_PC: begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h1C2; arA23[ 'h3] = 'h29B; end
    EA_Idx_PC: begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h1E3; arA23[ 'h3] = 'h29B; end
    EA_Imm:    begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h0EA; arA23[ 'h3] = 'h121; end
    default:   begin arIll[ 'h3] = 1'b1; arA1[ 'h3] = `UNDF; arA23[ 'h3] = `UNDF; end
    endcase

1: // Row: 1
    unique case ( col)
    EA_Dn:     begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h279; arA23[ 'h3] = `UNDF; end
    EA_An:     begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h279; arA23[ 'h3] = `UNDF; end
    EA_Ind:    begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h006; arA23[ 'h3] = 'h158; end
    EA_Post:   begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h21C; arA23[ 'h3] = 'h158; end
    EA_Pre:    begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h103; arA23[ 'h3] = 'h158; end
    EA_Rel_An: begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h1C2; arA23[ 'h3] = 'h158; end
    EA_Idx_An: begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h1E3; arA23[ 'h3] = 'h158; end
    EA_Abs_W:  begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h00A; arA23[ 'h3] = 'h158; end
    EA_Abs_L:  begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h1E2; arA23[ 'h3] = 'h158; end
    EA_Rel_PC: begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h1C2; arA23[ 'h3] = 'h158; end
    EA_Idx_PC: begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h1E3; arA23[ 'h3] = 'h158; end
    EA_Imm:    begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h0EA; arA23[ 'h3] = 'h279; end
    default:   begin arIll[ 'h3] = 1'b1; arA1[ 'h3] = `UNDF; arA23[ 'h3] = `UNDF; end
    endcase

2: // Row: 2
    unique case ( col)
    EA_Dn:     begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h2FA; arA23[ 'h3] = `UNDF; end
    EA_An:     begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h2FA; arA23[ 'h3] = `UNDF; end
    EA_Ind:    begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h006; arA23[ 'h3] = 'h3AB; end
    EA_Post:   begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h21C; arA23[ 'h3] = 'h3AB; end
    EA_Pre:    begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h103; arA23[ 'h3] = 'h3AB; end
    EA_Rel_An: begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h1C2; arA23[ 'h3] = 'h3AB; end
    EA_Idx_An: begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h1E3; arA23[ 'h3] = 'h3AB; end
    EA_Abs_W:  begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h00A; arA23[ 'h3] = 'h3AB; end
    EA_Abs_L:  begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h1E2; arA23[ 'h3] = 'h3AB; end
    EA_Rel_PC: begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h1C2; arA23[ 'h3] = 'h3AB; end
    EA_Idx_PC: begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h1E3; arA23[ 'h3] = 'h3AB; end
    EA_Imm:    begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h0EA; arA23[ 'h3] = 'h2FA; end
    default:   begin arIll[ 'h3] = 1'b1; arA1[ 'h3] = `UNDF; arA23[ 'h3] = `UNDF; end
    endcase

3: // Row: 3
    unique case ( col)
    EA_Dn:     begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h2FE; arA23[ 'h3] = `UNDF; end
    EA_An:     begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h2FE; arA23[ 'h3] = `UNDF; end
    EA_Ind:    begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h006; arA23[ 'h3] = 'h3AF; end
    EA_Post:   begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h21C; arA23[ 'h3] = 'h3AF; end
    EA_Pre:    begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h103; arA23[ 'h3] = 'h3AF; end
    EA_Rel_An: begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h1C2; arA23[ 'h3] = 'h3AF; end
    EA_Idx_An: begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h1E3; arA23[ 'h3] = 'h3AF; end
    EA_Abs_W:  begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h00A; arA23[ 'h3] = 'h3AF; end
    EA_Abs_L:  begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h1E2; arA23[ 'h3] = 'h3AF; end
    EA_Rel_PC: begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h1C2; arA23[ 'h3] = 'h3AF; end
    EA_Idx_PC: begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h1E3; arA23[ 'h3] = 'h3AF; end
    EA_Imm:    begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h0EA; arA23[ 'h3] = 'h2FE; end
    default:   begin arIll[ 'h3] = 1'b1; arA1[ 'h3] = `UNDF; arA23[ 'h3] = `UNDF; end
    endcase

4: // Row: 4
    unique case ( col)
    EA_Dn:     begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h2F8; arA23[ 'h3] = `UNDF; end
    EA_An:     begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h2F8; arA23[ 'h3] = `UNDF; end
    EA_Ind:    begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h006; arA23[ 'h3] = 'h38B; end
    EA_Post:   begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h21C; arA23[ 'h3] = 'h38B; end
    EA_Pre:    begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h103; arA23[ 'h3] = 'h38B; end
    EA_Rel_An: begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h1C2; arA23[ 'h3] = 'h38B; end
    EA_Idx_An: begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h1E3; arA23[ 'h3] = 'h38B; end
    EA_Abs_W:  begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h00A; arA23[ 'h3] = 'h38B; end
    EA_Abs_L:  begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h1E2; arA23[ 'h3] = 'h38B; end
    EA_Rel_PC: begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h1C2; arA23[ 'h3] = 'h38B; end
    EA_Idx_PC: begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h1E3; arA23[ 'h3] = 'h38B; end
    EA_Imm:    begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h0EA; arA23[ 'h3] = 'h2F8; end
    default:   begin arIll[ 'h3] = 1'b1; arA1[ 'h3] = `UNDF; arA23[ 'h3] = `UNDF; end
    endcase

5: // Row: 5
    unique case ( col)
    EA_Dn:     begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h2DA; arA23[ 'h3] = `UNDF; end
    EA_An:     begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h2DA; arA23[ 'h3] = `UNDF; end
    EA_Ind:    begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h006; arA23[ 'h3] = 'h38A; end
    EA_Post:   begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h21C; arA23[ 'h3] = 'h38A; end
    EA_Pre:    begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h103; arA23[ 'h3] = 'h38A; end
    EA_Rel_An: begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h1C2; arA23[ 'h3] = 'h38A; end
    EA_Idx_An: begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h1E3; arA23[ 'h3] = 'h38A; end
    EA_Abs_W:  begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h00A; arA23[ 'h3] = 'h38A; end
    EA_Abs_L:  begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h1E2; arA23[ 'h3] = 'h38A; end
    EA_Rel_PC: begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h1C2; arA23[ 'h3] = 'h38A; end
    EA_Idx_PC: begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h1E3; arA23[ 'h3] = 'h38A; end
    EA_Imm:    begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h0EA; arA23[ 'h3] = 'h2DA; end
    default:   begin arIll[ 'h3] = 1'b1; arA1[ 'h3] = `UNDF; arA23[ 'h3] = `UNDF; end
    endcase

6: // Row: 6
    unique case ( col)
    EA_Dn:     begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h1EB; arA23[ 'h3] = `UNDF; end
    EA_An:     begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h1EB; arA23[ 'h3] = `UNDF; end
    EA_Ind:    begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h006; arA23[ 'h3] = 'h298; end
    EA_Post:   begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h21C; arA23[ 'h3] = 'h298; end
    EA_Pre:    begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h103; arA23[ 'h3] = 'h298; end
    EA_Rel_An: begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h1C2; arA23[ 'h3] = 'h298; end
    EA_Idx_An: begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h1E3; arA23[ 'h3] = 'h298; end
    EA_Abs_W:  begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h00A; arA23[ 'h3] = 'h298; end
    EA_Abs_L:  begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h1E2; arA23[ 'h3] = 'h298; end
    EA_Rel_PC: begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h1C2; arA23[ 'h3] = 'h298; end
    EA_Idx_PC: begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h1E3; arA23[ 'h3] = 'h298; end
    EA_Imm:    begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h0EA; arA23[ 'h3] = 'h1EB; end
    default:   begin arIll[ 'h3] = 1'b1; arA1[ 'h3] = `UNDF; arA23[ 'h3] = `UNDF; end
    endcase

7: // Row: 7
    unique case ( col)
    EA_Dn:     begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h2D9; arA23[ 'h3] = `UNDF; end
    EA_An:     begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h2D9; arA23[ 'h3] = `UNDF; end
    EA_Ind:    begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h006; arA23[ 'h3] = 'h388; end
    EA_Post:   begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h21C; arA23[ 'h3] = 'h388; end
    EA_Pre:    begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h103; arA23[ 'h3] = 'h388; end
    EA_Rel_An: begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h1C2; arA23[ 'h3] = 'h388; end
    EA_Idx_An: begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h1E3; arA23[ 'h3] = 'h388; end
    EA_Abs_W:  begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h00A; arA23[ 'h3] = 'h388; end
    EA_Abs_L:  begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h1E2; arA23[ 'h3] = 'h388; end
    EA_Rel_PC: begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h1C2; arA23[ 'h3] = 'h388; end
    EA_Idx_PC: begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h1E3; arA23[ 'h3] = 'h388; end
    EA_Imm:    begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h0EA; arA23[ 'h3] = 'h2D9; end
    default:   begin arIll[ 'h3] = 1'b1; arA1[ 'h3] = `UNDF; arA23[ 'h3] = `UNDF; end
    endcase

8: // Row: 8
    unique case ( col)
    EA_Dn:     begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h1EA; arA23[ 'h3] = `UNDF; end
    EA_An:     begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h1EA; arA23[ 'h3] = `UNDF; end
    EA_Ind:    begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h006; arA23[ 'h3] = 'h32B; end
    EA_Post:   begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h21C; arA23[ 'h3] = 'h32B; end
    EA_Pre:    begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h103; arA23[ 'h3] = 'h32B; end
    EA_Rel_An: begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h1C2; arA23[ 'h3] = 'h32B; end
    EA_Idx_An: begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h1E3; arA23[ 'h3] = 'h32B; end
    EA_Abs_W:  begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h00A; arA23[ 'h3] = 'h32B; end
    EA_Abs_L:  begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h1E2; arA23[ 'h3] = 'h32B; end
    EA_Rel_PC: begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h1C2; arA23[ 'h3] = 'h32B; end
    EA_Idx_PC: begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h1E3; arA23[ 'h3] = 'h32B; end
    EA_Imm:    begin arIll[ 'h3] = 1'b0; arA1[ 'h3] = 'h0EA; arA23[ 'h3] = 'h1EA; end
    default:   begin arIll[ 'h3] = 1'b1; arA1[ 'h3] = `UNDF; arA23[ 'h3] = `UNDF; end
    endcase
default:  begin arIll[ 'h3] = 1'b1; arA1[ 'h3] = `UNDF; arA23[ 'h3] = `UNDF; end
endcase

//
// Line: 5
//
unique case( row86)

3'b000: // Row: 0
    unique case ( col)
    EA_Dn:     begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h2D8; arA23[ 'h5] = `UNDF; end
    EA_An:     begin arIll[ 'h5] = 1'b1; arA1[ 'h5] = `UNDF; arA23[ 'h5] = `UNDF; end
    EA_Ind:    begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h006; arA23[ 'h5] = 'h2F3; end
    EA_Post:   begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h21C; arA23[ 'h5] = 'h2F3; end
    EA_Pre:    begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h103; arA23[ 'h5] = 'h2F3; end
    EA_Rel_An: begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h1C2; arA23[ 'h5] = 'h2F3; end
    EA_Idx_An: begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h1E3; arA23[ 'h5] = 'h2F3; end
    EA_Abs_W:  begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h00A; arA23[ 'h5] = 'h2F3; end
    EA_Abs_L:  begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h1E2; arA23[ 'h5] = 'h2F3; end
    default:   begin arIll[ 'h5] = 1'b1; arA1[ 'h5] = `UNDF; arA23[ 'h5] = `UNDF; end
    endcase

3'b001: // Row: 1
    unique case ( col)
    EA_Dn:     begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h2D8; arA23[ 'h5] = `UNDF; end
    EA_An:     begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h2DC; arA23[ 'h5] = `UNDF; end
    EA_Ind:    begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h006; arA23[ 'h5] = 'h2F3; end
    EA_Post:   begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h21C; arA23[ 'h5] = 'h2F3; end
    EA_Pre:    begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h103; arA23[ 'h5] = 'h2F3; end
    EA_Rel_An: begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h1C2; arA23[ 'h5] = 'h2F3; end
    EA_Idx_An: begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h1E3; arA23[ 'h5] = 'h2F3; end
    EA_Abs_W:  begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h00A; arA23[ 'h5] = 'h2F3; end
    EA_Abs_L:  begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h1E2; arA23[ 'h5] = 'h2F3; end
    default:   begin arIll[ 'h5] = 1'b1; arA1[ 'h5] = `UNDF; arA23[ 'h5] = `UNDF; end
    endcase

3'b010: // Row: 2
    unique case ( col)
    EA_Dn:     begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h2DC; arA23[ 'h5] = `UNDF; end
    EA_An:     begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h2DC; arA23[ 'h5] = `UNDF; end
    EA_Ind:    begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h00B; arA23[ 'h5] = 'h2F7; end
    EA_Post:   begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h00F; arA23[ 'h5] = 'h2F7; end
    EA_Pre:    begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h179; arA23[ 'h5] = 'h2F7; end
    EA_Rel_An: begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h1C6; arA23[ 'h5] = 'h2F7; end
    EA_Idx_An: begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h1E7; arA23[ 'h5] = 'h2F7; end
    EA_Abs_W:  begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h00E; arA23[ 'h5] = 'h2F7; end
    EA_Abs_L:  begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h1E6; arA23[ 'h5] = 'h2F7; end
    default:   begin arIll[ 'h5] = 1'b1; arA1[ 'h5] = `UNDF; arA23[ 'h5] = `UNDF; end
    endcase

3'b011: // Row: 3
    unique case ( col)
    EA_Dn:     begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h384; arA23[ 'h5] = `UNDF; end
    EA_An:     begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h06C; arA23[ 'h5] = `UNDF; end
    EA_Ind:    begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h006; arA23[ 'h5] = 'h380; end
    EA_Post:   begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h21C; arA23[ 'h5] = 'h380; end
    EA_Pre:    begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h103; arA23[ 'h5] = 'h380; end
    EA_Rel_An: begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h1C2; arA23[ 'h5] = 'h380; end
    EA_Idx_An: begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h1E3; arA23[ 'h5] = 'h380; end
    EA_Abs_W:  begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h00A; arA23[ 'h5] = 'h380; end
    EA_Abs_L:  begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h1E2; arA23[ 'h5] = 'h380; end
    default:   begin arIll[ 'h5] = 1'b1; arA1[ 'h5] = `UNDF; arA23[ 'h5] = `UNDF; end
    endcase

3'b100: // Row: 4
    unique case ( col)
    EA_Dn:     begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h2D8; arA23[ 'h5] = `UNDF; end
    EA_An:     begin arIll[ 'h5] = 1'b1; arA1[ 'h5] = `UNDF; arA23[ 'h5] = `UNDF; end
    EA_Ind:    begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h006; arA23[ 'h5] = 'h2F3; end
    EA_Post:   begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h21C; arA23[ 'h5] = 'h2F3; end
    EA_Pre:    begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h103; arA23[ 'h5] = 'h2F3; end
    EA_Rel_An: begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h1C2; arA23[ 'h5] = 'h2F3; end
    EA_Idx_An: begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h1E3; arA23[ 'h5] = 'h2F3; end
    EA_Abs_W:  begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h00A; arA23[ 'h5] = 'h2F3; end
    EA_Abs_L:  begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h1E2; arA23[ 'h5] = 'h2F3; end
    default:   begin arIll[ 'h5] = 1'b1; arA1[ 'h5] = `UNDF; arA23[ 'h5] = `UNDF; end
    endcase

3'b101: // Row: 5
    unique case ( col)
    EA_Dn:     begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h2D8; arA23[ 'h5] = `UNDF; end
    EA_An:     begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h2DC; arA23[ 'h5] = `UNDF; end
    EA_Ind:    begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h006; arA23[ 'h5] = 'h2F3; end
    EA_Post:   begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h21C; arA23[ 'h5] = 'h2F3; end
    EA_Pre:    begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h103; arA23[ 'h5] = 'h2F3; end
    EA_Rel_An: begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h1C2; arA23[ 'h5] = 'h2F3; end
    EA_Idx_An: begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h1E3; arA23[ 'h5] = 'h2F3; end
    EA_Abs_W:  begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h00A; arA23[ 'h5] = 'h2F3; end
    EA_Abs_L:  begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h1E2; arA23[ 'h5] = 'h2F3; end
    default:   begin arIll[ 'h5] = 1'b1; arA1[ 'h5] = `UNDF; arA23[ 'h5] = `UNDF; end
    endcase

3'b110: // Row: 6
    unique case ( col)
    EA_Dn:     begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h2DC; arA23[ 'h5] = `UNDF; end
    EA_An:     begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h2DC; arA23[ 'h5] = `UNDF; end
    EA_Ind:    begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h00B; arA23[ 'h5] = 'h2F7; end
    EA_Post:   begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h00F; arA23[ 'h5] = 'h2F7; end
    EA_Pre:    begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h179; arA23[ 'h5] = 'h2F7; end
    EA_Rel_An: begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h1C6; arA23[ 'h5] = 'h2F7; end
    EA_Idx_An: begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h1E7; arA23[ 'h5] = 'h2F7; end
    EA_Abs_W:  begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h00E; arA23[ 'h5] = 'h2F7; end
    EA_Abs_L:  begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h1E6; arA23[ 'h5] = 'h2F7; end
    default:   begin arIll[ 'h5] = 1'b1; arA1[ 'h5] = `UNDF; arA23[ 'h5] = `UNDF; end
    endcase

3'b111: // Row: 7
    unique case ( col)
    EA_Dn:     begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h384; arA23[ 'h5] = `UNDF; end
    EA_An:     begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h06C; arA23[ 'h5] = `UNDF; end
    EA_Ind:    begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h006; arA23[ 'h5] = 'h380; end
    EA_Post:   begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h21C; arA23[ 'h5] = 'h380; end
    EA_Pre:    begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h103; arA23[ 'h5] = 'h380; end
    EA_Rel_An: begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h1C2; arA23[ 'h5] = 'h380; end
    EA_Idx_An: begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h1E3; arA23[ 'h5] = 'h380; end
    EA_Abs_W:  begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h00A; arA23[ 'h5] = 'h380; end
    EA_Abs_L:  begin arIll[ 'h5] = 1'b0; arA1[ 'h5] = 'h1E2; arA23[ 'h5] = 'h380; end
    default:   begin arIll[ 'h5] = 1'b1; arA1[ 'h5] = `UNDF; arA23[ 'h5] = `UNDF; end
    endcase
endcase

//
// Line: 8
//
unique case( row86)

3'b000: // Row: 0
    unique case ( col)
    EA_Dn:     begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h1C1; arA23[ 'h8] = `UNDF; end
    EA_An:     begin arIll[ 'h8] = 1'b1; arA1[ 'h8] = `UNDF; arA23[ 'h8] = `UNDF; end
    EA_Ind:    begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h006; arA23[ 'h8] = 'h1C3; end
    EA_Post:   begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h21C; arA23[ 'h8] = 'h1C3; end
    EA_Pre:    begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h103; arA23[ 'h8] = 'h1C3; end
    EA_Rel_An: begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h1C2; arA23[ 'h8] = 'h1C3; end
    EA_Idx_An: begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h1E3; arA23[ 'h8] = 'h1C3; end
    EA_Abs_W:  begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h00A; arA23[ 'h8] = 'h1C3; end
    EA_Abs_L:  begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h1E2; arA23[ 'h8] = 'h1C3; end
    EA_Rel_PC: begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h1C2; arA23[ 'h8] = 'h1C3; end
    EA_Idx_PC: begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h1E3; arA23[ 'h8] = 'h1C3; end
    EA_Imm:    begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h0EA; arA23[ 'h8] = 'h1C1; end
    default:   begin arIll[ 'h8] = 1'b1; arA1[ 'h8] = `UNDF; arA23[ 'h8] = `UNDF; end
    endcase

3'b001: // Row: 1
    unique case ( col)
    EA_Dn:     begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h1C1; arA23[ 'h8] = `UNDF; end
    EA_An:     begin arIll[ 'h8] = 1'b1; arA1[ 'h8] = `UNDF; arA23[ 'h8] = `UNDF; end
    EA_Ind:    begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h006; arA23[ 'h8] = 'h1C3; end
    EA_Post:   begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h21C; arA23[ 'h8] = 'h1C3; end
    EA_Pre:    begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h103; arA23[ 'h8] = 'h1C3; end
    EA_Rel_An: begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h1C2; arA23[ 'h8] = 'h1C3; end
    EA_Idx_An: begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h1E3; arA23[ 'h8] = 'h1C3; end
    EA_Abs_W:  begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h00A; arA23[ 'h8] = 'h1C3; end
    EA_Abs_L:  begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h1E2; arA23[ 'h8] = 'h1C3; end
    EA_Rel_PC: begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h1C2; arA23[ 'h8] = 'h1C3; end
    EA_Idx_PC: begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h1E3; arA23[ 'h8] = 'h1C3; end
    EA_Imm:    begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h0EA; arA23[ 'h8] = 'h1C1; end
    default:   begin arIll[ 'h8] = 1'b1; arA1[ 'h8] = `UNDF; arA23[ 'h8] = `UNDF; end
    endcase

3'b010: // Row: 2
    unique case ( col)
    EA_Dn:     begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h1C5; arA23[ 'h8] = `UNDF; end
    EA_An:     begin arIll[ 'h8] = 1'b1; arA1[ 'h8] = `UNDF; arA23[ 'h8] = `UNDF; end
    EA_Ind:    begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h00B; arA23[ 'h8] = 'h1CB; end
    EA_Post:   begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h00F; arA23[ 'h8] = 'h1CB; end
    EA_Pre:    begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h179; arA23[ 'h8] = 'h1CB; end
    EA_Rel_An: begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h1C6; arA23[ 'h8] = 'h1CB; end
    EA_Idx_An: begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h1E7; arA23[ 'h8] = 'h1CB; end
    EA_Abs_W:  begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h00E; arA23[ 'h8] = 'h1CB; end
    EA_Abs_L:  begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h1E6; arA23[ 'h8] = 'h1CB; end
    EA_Rel_PC: begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h1C6; arA23[ 'h8] = 'h1CB; end
    EA_Idx_PC: begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h1E7; arA23[ 'h8] = 'h1CB; end
    EA_Imm:    begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h0A7; arA23[ 'h8] = 'h1C5; end
    default:   begin arIll[ 'h8] = 1'b1; arA1[ 'h8] = `UNDF; arA23[ 'h8] = `UNDF; end
    endcase

3'b011: // Row: 3
    unique case ( col)
    EA_Dn:     begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h0A6; arA23[ 'h8] = `UNDF; end
    EA_An:     begin arIll[ 'h8] = 1'b1; arA1[ 'h8] = `UNDF; arA23[ 'h8] = `UNDF; end
    EA_Ind:    begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h006; arA23[ 'h8] = 'h0A4; end
    EA_Post:   begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h21C; arA23[ 'h8] = 'h0A4; end
    EA_Pre:    begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h103; arA23[ 'h8] = 'h0A4; end
    EA_Rel_An: begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h1C2; arA23[ 'h8] = 'h0A4; end
    EA_Idx_An: begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h1E3; arA23[ 'h8] = 'h0A4; end
    EA_Abs_W:  begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h00A; arA23[ 'h8] = 'h0A4; end
    EA_Abs_L:  begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h1E2; arA23[ 'h8] = 'h0A4; end
    EA_Rel_PC: begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h1C2; arA23[ 'h8] = 'h0A4; end
    EA_Idx_PC: begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h1E3; arA23[ 'h8] = 'h0A4; end
    EA_Imm:    begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h0EA; arA23[ 'h8] = 'h0A6; end
    default:   begin arIll[ 'h8] = 1'b1; arA1[ 'h8] = `UNDF; arA23[ 'h8] = `UNDF; end
    endcase

3'b100: // Row: 4
    unique case ( col)
    EA_Dn:     begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h1CD; arA23[ 'h8] = `UNDF; end
    EA_An:     begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h107; arA23[ 'h8] = `UNDF; end
    EA_Ind:    begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h006; arA23[ 'h8] = 'h299; end
    EA_Post:   begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h21C; arA23[ 'h8] = 'h299; end
    EA_Pre:    begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h103; arA23[ 'h8] = 'h299; end
    EA_Rel_An: begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h1C2; arA23[ 'h8] = 'h299; end
    EA_Idx_An: begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h1E3; arA23[ 'h8] = 'h299; end
    EA_Abs_W:  begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h00A; arA23[ 'h8] = 'h299; end
    EA_Abs_L:  begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h1E2; arA23[ 'h8] = 'h299; end
    EA_Rel_PC: begin arIll[ 'h8] = 1'b1; arA1[ 'h8] = `UNDF; arA23[ 'h8] = `UNDF; end
    EA_Idx_PC: begin arIll[ 'h8] = 1'b1; arA1[ 'h8] = `UNDF; arA23[ 'h8] = `UNDF; end
    EA_Imm:    begin arIll[ 'h8] = 1'b1; arA1[ 'h8] = `UNDF; arA23[ 'h8] = `UNDF; end
    default:   begin arIll[ 'h8] = 1'b1; arA1[ 'h8] = `UNDF; arA23[ 'h8] = `UNDF; end
    endcase

3'b101: // Row: 5
    unique case ( col)
    EA_Dn:     begin arIll[ 'h8] = 1'b1; arA1[ 'h8] = `UNDF; arA23[ 'h8] = `UNDF; end
    EA_An:     begin arIll[ 'h8] = 1'b1; arA1[ 'h8] = `UNDF; arA23[ 'h8] = `UNDF; end
    EA_Ind:    begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h006; arA23[ 'h8] = 'h299; end
    EA_Post:   begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h21C; arA23[ 'h8] = 'h299; end
    EA_Pre:    begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h103; arA23[ 'h8] = 'h299; end
    EA_Rel_An: begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h1C2; arA23[ 'h8] = 'h299; end
    EA_Idx_An: begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h1E3; arA23[ 'h8] = 'h299; end
    EA_Abs_W:  begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h00A; arA23[ 'h8] = 'h299; end
    EA_Abs_L:  begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h1E2; arA23[ 'h8] = 'h299; end
    EA_Rel_PC: begin arIll[ 'h8] = 1'b1; arA1[ 'h8] = `UNDF; arA23[ 'h8] = `UNDF; end
    EA_Idx_PC: begin arIll[ 'h8] = 1'b1; arA1[ 'h8] = `UNDF; arA23[ 'h8] = `UNDF; end
    EA_Imm:    begin arIll[ 'h8] = 1'b1; arA1[ 'h8] = `UNDF; arA23[ 'h8] = `UNDF; end
    default:   begin arIll[ 'h8] = 1'b1; arA1[ 'h8] = `UNDF; arA23[ 'h8] = `UNDF; end
    endcase

3'b110: // Row: 6
    unique case ( col)
    EA_Dn:     begin arIll[ 'h8] = 1'b1; arA1[ 'h8] = `UNDF; arA23[ 'h8] = `UNDF; end
    EA_An:     begin arIll[ 'h8] = 1'b1; arA1[ 'h8] = `UNDF; arA23[ 'h8] = `UNDF; end
    EA_Ind:    begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h00B; arA23[ 'h8] = 'h29D; end
    EA_Post:   begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h00F; arA23[ 'h8] = 'h29D; end
    EA_Pre:    begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h179; arA23[ 'h8] = 'h29D; end
    EA_Rel_An: begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h1C6; arA23[ 'h8] = 'h29D; end
    EA_Idx_An: begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h1E7; arA23[ 'h8] = 'h29D; end
    EA_Abs_W:  begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h00E; arA23[ 'h8] = 'h29D; end
    EA_Abs_L:  begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h1E6; arA23[ 'h8] = 'h29D; end
    EA_Rel_PC: begin arIll[ 'h8] = 1'b1; arA1[ 'h8] = `UNDF; arA23[ 'h8] = `UNDF; end
    EA_Idx_PC: begin arIll[ 'h8] = 1'b1; arA1[ 'h8] = `UNDF; arA23[ 'h8] = `UNDF; end
    EA_Imm:    begin arIll[ 'h8] = 1'b1; arA1[ 'h8] = `UNDF; arA23[ 'h8] = `UNDF; end
    default:   begin arIll[ 'h8] = 1'b1; arA1[ 'h8] = `UNDF; arA23[ 'h8] = `UNDF; end
    endcase

3'b111: // Row: 7
    unique case ( col)
    EA_Dn:     begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h0AE; arA23[ 'h8] = `UNDF; end
    EA_An:     begin arIll[ 'h8] = 1'b1; arA1[ 'h8] = `UNDF; arA23[ 'h8] = `UNDF; end
    EA_Ind:    begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h006; arA23[ 'h8] = 'h0AC; end
    EA_Post:   begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h21C; arA23[ 'h8] = 'h0AC; end
    EA_Pre:    begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h103; arA23[ 'h8] = 'h0AC; end
    EA_Rel_An: begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h1C2; arA23[ 'h8] = 'h0AC; end
    EA_Idx_An: begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h1E3; arA23[ 'h8] = 'h0AC; end
    EA_Abs_W:  begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h00A; arA23[ 'h8] = 'h0AC; end
    EA_Abs_L:  begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h1E2; arA23[ 'h8] = 'h0AC; end
    EA_Rel_PC: begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h1C2; arA23[ 'h8] = 'h0AC; end
    EA_Idx_PC: begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h1E3; arA23[ 'h8] = 'h0AC; end
    EA_Imm:    begin arIll[ 'h8] = 1'b0; arA1[ 'h8] = 'h0EA; arA23[ 'h8] = 'h0AE; end
    default:   begin arIll[ 'h8] = 1'b1; arA1[ 'h8] = `UNDF; arA23[ 'h8] = `UNDF; end
    endcase
endcase

//
// Line: 9
//
unique case( row86)

3'b000: // Row: 0
    unique case ( col)
    EA_Dn:     begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h1C1; arA23[ 'h9] = `UNDF; end
    EA_An:     begin arIll[ 'h9] = 1'b1; arA1[ 'h9] = `UNDF; arA23[ 'h9] = `UNDF; end
    EA_Ind:    begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h006; arA23[ 'h9] = 'h1C3; end
    EA_Post:   begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h21C; arA23[ 'h9] = 'h1C3; end
    EA_Pre:    begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h103; arA23[ 'h9] = 'h1C3; end
    EA_Rel_An: begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h1C2; arA23[ 'h9] = 'h1C3; end
    EA_Idx_An: begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h1E3; arA23[ 'h9] = 'h1C3; end
    EA_Abs_W:  begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h00A; arA23[ 'h9] = 'h1C3; end
    EA_Abs_L:  begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h1E2; arA23[ 'h9] = 'h1C3; end
    EA_Rel_PC: begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h1C2; arA23[ 'h9] = 'h1C3; end
    EA_Idx_PC: begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h1E3; arA23[ 'h9] = 'h1C3; end
    EA_Imm:    begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h0EA; arA23[ 'h9] = 'h1C1; end
    default:   begin arIll[ 'h9] = 1'b1; arA1[ 'h9] = `UNDF; arA23[ 'h9] = `UNDF; end
    endcase

3'b001: // Row: 1
    unique case ( col)
    EA_Dn:     begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h1C1; arA23[ 'h9] = `UNDF; end
    EA_An:     begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h1C1; arA23[ 'h9] = `UNDF; end
    EA_Ind:    begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h006; arA23[ 'h9] = 'h1C3; end
    EA_Post:   begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h21C; arA23[ 'h9] = 'h1C3; end
    EA_Pre:    begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h103; arA23[ 'h9] = 'h1C3; end
    EA_Rel_An: begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h1C2; arA23[ 'h9] = 'h1C3; end
    EA_Idx_An: begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h1E3; arA23[ 'h9] = 'h1C3; end
    EA_Abs_W:  begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h00A; arA23[ 'h9] = 'h1C3; end
    EA_Abs_L:  begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h1E2; arA23[ 'h9] = 'h1C3; end
    EA_Rel_PC: begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h1C2; arA23[ 'h9] = 'h1C3; end
    EA_Idx_PC: begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h1E3; arA23[ 'h9] = 'h1C3; end
    EA_Imm:    begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h0EA; arA23[ 'h9] = 'h1C1; end
    default:   begin arIll[ 'h9] = 1'b1; arA1[ 'h9] = `UNDF; arA23[ 'h9] = `UNDF; end
    endcase

3'b010: // Row: 2
    unique case ( col)
    EA_Dn:     begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h1C5; arA23[ 'h9] = `UNDF; end
    EA_An:     begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h1C5; arA23[ 'h9] = `UNDF; end
    EA_Ind:    begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h00B; arA23[ 'h9] = 'h1CB; end
    EA_Post:   begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h00F; arA23[ 'h9] = 'h1CB; end
    EA_Pre:    begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h179; arA23[ 'h9] = 'h1CB; end
    EA_Rel_An: begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h1C6; arA23[ 'h9] = 'h1CB; end
    EA_Idx_An: begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h1E7; arA23[ 'h9] = 'h1CB; end
    EA_Abs_W:  begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h00E; arA23[ 'h9] = 'h1CB; end
    EA_Abs_L:  begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h1E6; arA23[ 'h9] = 'h1CB; end
    EA_Rel_PC: begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h1C6; arA23[ 'h9] = 'h1CB; end
    EA_Idx_PC: begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h1E7; arA23[ 'h9] = 'h1CB; end
    EA_Imm:    begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h0A7; arA23[ 'h9] = 'h1C5; end
    default:   begin arIll[ 'h9] = 1'b1; arA1[ 'h9] = `UNDF; arA23[ 'h9] = `UNDF; end
    endcase

3'b011: // Row: 3
    unique case ( col)
    EA_Dn:     begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h1C9; arA23[ 'h9] = `UNDF; end
    EA_An:     begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h1C9; arA23[ 'h9] = `UNDF; end
    EA_Ind:    begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h006; arA23[ 'h9] = 'h1C7; end
    EA_Post:   begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h21C; arA23[ 'h9] = 'h1C7; end
    EA_Pre:    begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h103; arA23[ 'h9] = 'h1C7; end
    EA_Rel_An: begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h1C2; arA23[ 'h9] = 'h1C7; end
    EA_Idx_An: begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h1E3; arA23[ 'h9] = 'h1C7; end
    EA_Abs_W:  begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h00A; arA23[ 'h9] = 'h1C7; end
    EA_Abs_L:  begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h1E2; arA23[ 'h9] = 'h1C7; end
    EA_Rel_PC: begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h1C2; arA23[ 'h9] = 'h1C7; end
    EA_Idx_PC: begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h1E3; arA23[ 'h9] = 'h1C7; end
    EA_Imm:    begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h0EA; arA23[ 'h9] = 'h1C9; end
    default:   begin arIll[ 'h9] = 1'b1; arA1[ 'h9] = `UNDF; arA23[ 'h9] = `UNDF; end
    endcase

3'b100: // Row: 4
    unique case ( col)
    EA_Dn:     begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h1C1; arA23[ 'h9] = `UNDF; end
    EA_An:     begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h10F; arA23[ 'h9] = `UNDF; end
    EA_Ind:    begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h006; arA23[ 'h9] = 'h299; end
    EA_Post:   begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h21C; arA23[ 'h9] = 'h299; end
    EA_Pre:    begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h103; arA23[ 'h9] = 'h299; end
    EA_Rel_An: begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h1C2; arA23[ 'h9] = 'h299; end
    EA_Idx_An: begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h1E3; arA23[ 'h9] = 'h299; end
    EA_Abs_W:  begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h00A; arA23[ 'h9] = 'h299; end
    EA_Abs_L:  begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h1E2; arA23[ 'h9] = 'h299; end
    EA_Rel_PC: begin arIll[ 'h9] = 1'b1; arA1[ 'h9] = `UNDF; arA23[ 'h9] = `UNDF; end
    EA_Idx_PC: begin arIll[ 'h9] = 1'b1; arA1[ 'h9] = `UNDF; arA23[ 'h9] = `UNDF; end
    EA_Imm:    begin arIll[ 'h9] = 1'b1; arA1[ 'h9] = `UNDF; arA23[ 'h9] = `UNDF; end
    default:   begin arIll[ 'h9] = 1'b1; arA1[ 'h9] = `UNDF; arA23[ 'h9] = `UNDF; end
    endcase

3'b101: // Row: 5
    unique case ( col)
    EA_Dn:     begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h1C1; arA23[ 'h9] = `UNDF; end
    EA_An:     begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h10F; arA23[ 'h9] = `UNDF; end
    EA_Ind:    begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h006; arA23[ 'h9] = 'h299; end
    EA_Post:   begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h21C; arA23[ 'h9] = 'h299; end
    EA_Pre:    begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h103; arA23[ 'h9] = 'h299; end
    EA_Rel_An: begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h1C2; arA23[ 'h9] = 'h299; end
    EA_Idx_An: begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h1E3; arA23[ 'h9] = 'h299; end
    EA_Abs_W:  begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h00A; arA23[ 'h9] = 'h299; end
    EA_Abs_L:  begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h1E2; arA23[ 'h9] = 'h299; end
    EA_Rel_PC: begin arIll[ 'h9] = 1'b1; arA1[ 'h9] = `UNDF; arA23[ 'h9] = `UNDF; end
    EA_Idx_PC: begin arIll[ 'h9] = 1'b1; arA1[ 'h9] = `UNDF; arA23[ 'h9] = `UNDF; end
    EA_Imm:    begin arIll[ 'h9] = 1'b1; arA1[ 'h9] = `UNDF; arA23[ 'h9] = `UNDF; end
    default:   begin arIll[ 'h9] = 1'b1; arA1[ 'h9] = `UNDF; arA23[ 'h9] = `UNDF; end
    endcase

3'b110: // Row: 6
    unique case ( col)
    EA_Dn:     begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h1C5; arA23[ 'h9] = `UNDF; end
    EA_An:     begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h10B; arA23[ 'h9] = `UNDF; end
    EA_Ind:    begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h00B; arA23[ 'h9] = 'h29D; end
    EA_Post:   begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h00F; arA23[ 'h9] = 'h29D; end
    EA_Pre:    begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h179; arA23[ 'h9] = 'h29D; end
    EA_Rel_An: begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h1C6; arA23[ 'h9] = 'h29D; end
    EA_Idx_An: begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h1E7; arA23[ 'h9] = 'h29D; end
    EA_Abs_W:  begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h00E; arA23[ 'h9] = 'h29D; end
    EA_Abs_L:  begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h1E6; arA23[ 'h9] = 'h29D; end
    EA_Rel_PC: begin arIll[ 'h9] = 1'b1; arA1[ 'h9] = `UNDF; arA23[ 'h9] = `UNDF; end
    EA_Idx_PC: begin arIll[ 'h9] = 1'b1; arA1[ 'h9] = `UNDF; arA23[ 'h9] = `UNDF; end
    EA_Imm:    begin arIll[ 'h9] = 1'b1; arA1[ 'h9] = `UNDF; arA23[ 'h9] = `UNDF; end
    default:   begin arIll[ 'h9] = 1'b1; arA1[ 'h9] = `UNDF; arA23[ 'h9] = `UNDF; end
    endcase

3'b111: // Row: 7
    unique case ( col)
    EA_Dn:     begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h1C5; arA23[ 'h9] = `UNDF; end
    EA_An:     begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h1C5; arA23[ 'h9] = `UNDF; end
    EA_Ind:    begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h00B; arA23[ 'h9] = 'h1CB; end
    EA_Post:   begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h00F; arA23[ 'h9] = 'h1CB; end
    EA_Pre:    begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h179; arA23[ 'h9] = 'h1CB; end
    EA_Rel_An: begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h1C6; arA23[ 'h9] = 'h1CB; end
    EA_Idx_An: begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h1E7; arA23[ 'h9] = 'h1CB; end
    EA_Abs_W:  begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h00E; arA23[ 'h9] = 'h1CB; end
    EA_Abs_L:  begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h1E6; arA23[ 'h9] = 'h1CB; end
    EA_Rel_PC: begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h1C6; arA23[ 'h9] = 'h1CB; end
    EA_Idx_PC: begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h1E7; arA23[ 'h9] = 'h1CB; end
    EA_Imm:    begin arIll[ 'h9] = 1'b0; arA1[ 'h9] = 'h0A7; arA23[ 'h9] = 'h1C5; end
    default:   begin arIll[ 'h9] = 1'b1; arA1[ 'h9] = `UNDF; arA23[ 'h9] = `UNDF; end
    endcase
endcase

//
// Line: B
//
unique case( row86)

3'b000: // Row: 0
    unique case ( col)
    EA_Dn:     begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h1D1; arA23[ 'hb] = `UNDF; end
    EA_An:     begin arIll[ 'hb] = 1'b1; arA1[ 'hb] = `UNDF; arA23[ 'hb] = `UNDF; end
    EA_Ind:    begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h006; arA23[ 'hb] = 'h1D3; end
    EA_Post:   begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h21C; arA23[ 'hb] = 'h1D3; end
    EA_Pre:    begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h103; arA23[ 'hb] = 'h1D3; end
    EA_Rel_An: begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h1C2; arA23[ 'hb] = 'h1D3; end
    EA_Idx_An: begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h1E3; arA23[ 'hb] = 'h1D3; end
    EA_Abs_W:  begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h00A; arA23[ 'hb] = 'h1D3; end
    EA_Abs_L:  begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h1E2; arA23[ 'hb] = 'h1D3; end
    EA_Rel_PC: begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h1C2; arA23[ 'hb] = 'h1D3; end
    EA_Idx_PC: begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h1E3; arA23[ 'hb] = 'h1D3; end
    EA_Imm:    begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h0EA; arA23[ 'hb] = 'h1D1; end
    default:   begin arIll[ 'hb] = 1'b1; arA1[ 'hb] = `UNDF; arA23[ 'hb] = `UNDF; end
    endcase

3'b001: // Row: 1
    unique case ( col)
    EA_Dn:     begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h1D1; arA23[ 'hb] = `UNDF; end
    EA_An:     begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h1D1; arA23[ 'hb] = `UNDF; end
    EA_Ind:    begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h006; arA23[ 'hb] = 'h1D3; end
    EA_Post:   begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h21C; arA23[ 'hb] = 'h1D3; end
    EA_Pre:    begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h103; arA23[ 'hb] = 'h1D3; end
    EA_Rel_An: begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h1C2; arA23[ 'hb] = 'h1D3; end
    EA_Idx_An: begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h1E3; arA23[ 'hb] = 'h1D3; end
    EA_Abs_W:  begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h00A; arA23[ 'hb] = 'h1D3; end
    EA_Abs_L:  begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h1E2; arA23[ 'hb] = 'h1D3; end
    EA_Rel_PC: begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h1C2; arA23[ 'hb] = 'h1D3; end
    EA_Idx_PC: begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h1E3; arA23[ 'hb] = 'h1D3; end
    EA_Imm:    begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h0EA; arA23[ 'hb] = 'h1D1; end
    default:   begin arIll[ 'hb] = 1'b1; arA1[ 'hb] = `UNDF; arA23[ 'hb] = `UNDF; end
    endcase

3'b010: // Row: 2
    unique case ( col)
    EA_Dn:     begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h1D5; arA23[ 'hb] = `UNDF; end
    EA_An:     begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h1D5; arA23[ 'hb] = `UNDF; end
    EA_Ind:    begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h00B; arA23[ 'hb] = 'h1D7; end
    EA_Post:   begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h00F; arA23[ 'hb] = 'h1D7; end
    EA_Pre:    begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h179; arA23[ 'hb] = 'h1D7; end
    EA_Rel_An: begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h1C6; arA23[ 'hb] = 'h1D7; end
    EA_Idx_An: begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h1E7; arA23[ 'hb] = 'h1D7; end
    EA_Abs_W:  begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h00E; arA23[ 'hb] = 'h1D7; end
    EA_Abs_L:  begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h1E6; arA23[ 'hb] = 'h1D7; end
    EA_Rel_PC: begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h1C6; arA23[ 'hb] = 'h1D7; end
    EA_Idx_PC: begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h1E7; arA23[ 'hb] = 'h1D7; end
    EA_Imm:    begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h0A7; arA23[ 'hb] = 'h1D5; end
    default:   begin arIll[ 'hb] = 1'b1; arA1[ 'hb] = `UNDF; arA23[ 'hb] = `UNDF; end
    endcase

3'b011: // Row: 3
    unique case ( col)
    EA_Dn:     begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h1D9; arA23[ 'hb] = `UNDF; end
    EA_An:     begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h1D9; arA23[ 'hb] = `UNDF; end
    EA_Ind:    begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h006; arA23[ 'hb] = 'h1CF; end
    EA_Post:   begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h21C; arA23[ 'hb] = 'h1CF; end
    EA_Pre:    begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h103; arA23[ 'hb] = 'h1CF; end
    EA_Rel_An: begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h1C2; arA23[ 'hb] = 'h1CF; end
    EA_Idx_An: begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h1E3; arA23[ 'hb] = 'h1CF; end
    EA_Abs_W:  begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h00A; arA23[ 'hb] = 'h1CF; end
    EA_Abs_L:  begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h1E2; arA23[ 'hb] = 'h1CF; end
    EA_Rel_PC: begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h1C2; arA23[ 'hb] = 'h1CF; end
    EA_Idx_PC: begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h1E3; arA23[ 'hb] = 'h1CF; end
    EA_Imm:    begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h0EA; arA23[ 'hb] = 'h1D9; end
    default:   begin arIll[ 'hb] = 1'b1; arA1[ 'hb] = `UNDF; arA23[ 'hb] = `UNDF; end
    endcase

3'b100: // Row: 4
    unique case ( col)
    EA_Dn:     begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h100; arA23[ 'hb] = `UNDF; end
    EA_An:     begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h06B; arA23[ 'hb] = `UNDF; end
    EA_Ind:    begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h006; arA23[ 'hb] = 'h299; end
    EA_Post:   begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h21C; arA23[ 'hb] = 'h299; end
    EA_Pre:    begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h103; arA23[ 'hb] = 'h299; end
    EA_Rel_An: begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h1C2; arA23[ 'hb] = 'h299; end
    EA_Idx_An: begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h1E3; arA23[ 'hb] = 'h299; end
    EA_Abs_W:  begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h00A; arA23[ 'hb] = 'h299; end
    EA_Abs_L:  begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h1E2; arA23[ 'hb] = 'h299; end
    EA_Rel_PC: begin arIll[ 'hb] = 1'b1; arA1[ 'hb] = `UNDF; arA23[ 'hb] = `UNDF; end
    EA_Idx_PC: begin arIll[ 'hb] = 1'b1; arA1[ 'hb] = `UNDF; arA23[ 'hb] = `UNDF; end
    EA_Imm:    begin arIll[ 'hb] = 1'b1; arA1[ 'hb] = `UNDF; arA23[ 'hb] = `UNDF; end
    default:   begin arIll[ 'hb] = 1'b1; arA1[ 'hb] = `UNDF; arA23[ 'hb] = `UNDF; end
    endcase

3'b101: // Row: 5
    unique case ( col)
    EA_Dn:     begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h100; arA23[ 'hb] = `UNDF; end
    EA_An:     begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h06B; arA23[ 'hb] = `UNDF; end
    EA_Ind:    begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h006; arA23[ 'hb] = 'h299; end
    EA_Post:   begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h21C; arA23[ 'hb] = 'h299; end
    EA_Pre:    begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h103; arA23[ 'hb] = 'h299; end
    EA_Rel_An: begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h1C2; arA23[ 'hb] = 'h299; end
    EA_Idx_An: begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h1E3; arA23[ 'hb] = 'h299; end
    EA_Abs_W:  begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h00A; arA23[ 'hb] = 'h299; end
    EA_Abs_L:  begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h1E2; arA23[ 'hb] = 'h299; end
    EA_Rel_PC: begin arIll[ 'hb] = 1'b1; arA1[ 'hb] = `UNDF; arA23[ 'hb] = `UNDF; end
    EA_Idx_PC: begin arIll[ 'hb] = 1'b1; arA1[ 'hb] = `UNDF; arA23[ 'hb] = `UNDF; end
    EA_Imm:    begin arIll[ 'hb] = 1'b1; arA1[ 'hb] = `UNDF; arA23[ 'hb] = `UNDF; end
    default:   begin arIll[ 'hb] = 1'b1; arA1[ 'hb] = `UNDF; arA23[ 'hb] = `UNDF; end
    endcase

3'b110: // Row: 6
    unique case ( col)
    EA_Dn:     begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h10C; arA23[ 'hb] = `UNDF; end
    EA_An:     begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h06F; arA23[ 'hb] = `UNDF; end
    EA_Ind:    begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h00B; arA23[ 'hb] = 'h29D; end
    EA_Post:   begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h00F; arA23[ 'hb] = 'h29D; end
    EA_Pre:    begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h179; arA23[ 'hb] = 'h29D; end
    EA_Rel_An: begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h1C6; arA23[ 'hb] = 'h29D; end
    EA_Idx_An: begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h1E7; arA23[ 'hb] = 'h29D; end
    EA_Abs_W:  begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h00E; arA23[ 'hb] = 'h29D; end
    EA_Abs_L:  begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h1E6; arA23[ 'hb] = 'h29D; end
    EA_Rel_PC: begin arIll[ 'hb] = 1'b1; arA1[ 'hb] = `UNDF; arA23[ 'hb] = `UNDF; end
    EA_Idx_PC: begin arIll[ 'hb] = 1'b1; arA1[ 'hb] = `UNDF; arA23[ 'hb] = `UNDF; end
    EA_Imm:    begin arIll[ 'hb] = 1'b1; arA1[ 'hb] = `UNDF; arA23[ 'hb] = `UNDF; end
    default:   begin arIll[ 'hb] = 1'b1; arA1[ 'hb] = `UNDF; arA23[ 'hb] = `UNDF; end
    endcase

3'b111: // Row: 7
    unique case ( col)
    EA_Dn:     begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h1D5; arA23[ 'hb] = `UNDF; end
    EA_An:     begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h1D5; arA23[ 'hb] = `UNDF; end
    EA_Ind:    begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h00B; arA23[ 'hb] = 'h1D7; end
    EA_Post:   begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h00F; arA23[ 'hb] = 'h1D7; end
    EA_Pre:    begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h179; arA23[ 'hb] = 'h1D7; end
    EA_Rel_An: begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h1C6; arA23[ 'hb] = 'h1D7; end
    EA_Idx_An: begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h1E7; arA23[ 'hb] = 'h1D7; end
    EA_Abs_W:  begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h00E; arA23[ 'hb] = 'h1D7; end
    EA_Abs_L:  begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h1E6; arA23[ 'hb] = 'h1D7; end
    EA_Rel_PC: begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h1C6; arA23[ 'hb] = 'h1D7; end
    EA_Idx_PC: begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h1E7; arA23[ 'hb] = 'h1D7; end
    EA_Imm:    begin arIll[ 'hb] = 1'b0; arA1[ 'hb] = 'h0A7; arA23[ 'hb] = 'h1D5; end
    default:   begin arIll[ 'hb] = 1'b1; arA1[ 'hb] = `UNDF; arA23[ 'hb] = `UNDF; end
    endcase
endcase

//
// Line: C
//
unique case( row86)

3'b000: // Row: 0
    unique case ( col)
    EA_Dn:     begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h1C1; arA23[ 'hc] = `UNDF; end
    EA_An:     begin arIll[ 'hc] = 1'b1; arA1[ 'hc] = `UNDF; arA23[ 'hc] = `UNDF; end
    EA_Ind:    begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h006; arA23[ 'hc] = 'h1C3; end
    EA_Post:   begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h21C; arA23[ 'hc] = 'h1C3; end
    EA_Pre:    begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h103; arA23[ 'hc] = 'h1C3; end
    EA_Rel_An: begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h1C2; arA23[ 'hc] = 'h1C3; end
    EA_Idx_An: begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h1E3; arA23[ 'hc] = 'h1C3; end
    EA_Abs_W:  begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h00A; arA23[ 'hc] = 'h1C3; end
    EA_Abs_L:  begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h1E2; arA23[ 'hc] = 'h1C3; end
    EA_Rel_PC: begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h1C2; arA23[ 'hc] = 'h1C3; end
    EA_Idx_PC: begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h1E3; arA23[ 'hc] = 'h1C3; end
    EA_Imm:    begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h0EA; arA23[ 'hc] = 'h1C1; end
    default:   begin arIll[ 'hc] = 1'b1; arA1[ 'hc] = `UNDF; arA23[ 'hc] = `UNDF; end
    endcase

3'b001: // Row: 1
    unique case ( col)
    EA_Dn:     begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h1C1; arA23[ 'hc] = `UNDF; end
    EA_An:     begin arIll[ 'hc] = 1'b1; arA1[ 'hc] = `UNDF; arA23[ 'hc] = `UNDF; end
    EA_Ind:    begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h006; arA23[ 'hc] = 'h1C3; end
    EA_Post:   begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h21C; arA23[ 'hc] = 'h1C3; end
    EA_Pre:    begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h103; arA23[ 'hc] = 'h1C3; end
    EA_Rel_An: begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h1C2; arA23[ 'hc] = 'h1C3; end
    EA_Idx_An: begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h1E3; arA23[ 'hc] = 'h1C3; end
    EA_Abs_W:  begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h00A; arA23[ 'hc] = 'h1C3; end
    EA_Abs_L:  begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h1E2; arA23[ 'hc] = 'h1C3; end
    EA_Rel_PC: begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h1C2; arA23[ 'hc] = 'h1C3; end
    EA_Idx_PC: begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h1E3; arA23[ 'hc] = 'h1C3; end
    EA_Imm:    begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h0EA; arA23[ 'hc] = 'h1C1; end
    default:   begin arIll[ 'hc] = 1'b1; arA1[ 'hc] = `UNDF; arA23[ 'hc] = `UNDF; end
    endcase

3'b010: // Row: 2
    unique case ( col)
    EA_Dn:     begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h1C5; arA23[ 'hc] = `UNDF; end
    EA_An:     begin arIll[ 'hc] = 1'b1; arA1[ 'hc] = `UNDF; arA23[ 'hc] = `UNDF; end
    EA_Ind:    begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h00B; arA23[ 'hc] = 'h1CB; end
    EA_Post:   begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h00F; arA23[ 'hc] = 'h1CB; end
    EA_Pre:    begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h179; arA23[ 'hc] = 'h1CB; end
    EA_Rel_An: begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h1C6; arA23[ 'hc] = 'h1CB; end
    EA_Idx_An: begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h1E7; arA23[ 'hc] = 'h1CB; end
    EA_Abs_W:  begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h00E; arA23[ 'hc] = 'h1CB; end
    EA_Abs_L:  begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h1E6; arA23[ 'hc] = 'h1CB; end
    EA_Rel_PC: begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h1C6; arA23[ 'hc] = 'h1CB; end
    EA_Idx_PC: begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h1E7; arA23[ 'hc] = 'h1CB; end
    EA_Imm:    begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h0A7; arA23[ 'hc] = 'h1C5; end
    default:   begin arIll[ 'hc] = 1'b1; arA1[ 'hc] = `UNDF; arA23[ 'hc] = `UNDF; end
    endcase

3'b011: // Row: 3
    unique case ( col)
    EA_Dn:     begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h15B; arA23[ 'hc] = `UNDF; end
    EA_An:     begin arIll[ 'hc] = 1'b1; arA1[ 'hc] = `UNDF; arA23[ 'hc] = `UNDF; end
    EA_Ind:    begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h006; arA23[ 'hc] = 'h15A; end
    EA_Post:   begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h21C; arA23[ 'hc] = 'h15A; end
    EA_Pre:    begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h103; arA23[ 'hc] = 'h15A; end
    EA_Rel_An: begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h1C2; arA23[ 'hc] = 'h15A; end
    EA_Idx_An: begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h1E3; arA23[ 'hc] = 'h15A; end
    EA_Abs_W:  begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h00A; arA23[ 'hc] = 'h15A; end
    EA_Abs_L:  begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h1E2; arA23[ 'hc] = 'h15A; end
    EA_Rel_PC: begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h1C2; arA23[ 'hc] = 'h15A; end
    EA_Idx_PC: begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h1E3; arA23[ 'hc] = 'h15A; end
    EA_Imm:    begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h0EA; arA23[ 'hc] = 'h15B; end
    default:   begin arIll[ 'hc] = 1'b1; arA1[ 'hc] = `UNDF; arA23[ 'hc] = `UNDF; end
    endcase

3'b100: // Row: 4
    unique case ( col)
    EA_Dn:     begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h1CD; arA23[ 'hc] = `UNDF; end
    EA_An:     begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h107; arA23[ 'hc] = `UNDF; end
    EA_Ind:    begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h006; arA23[ 'hc] = 'h299; end
    EA_Post:   begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h21C; arA23[ 'hc] = 'h299; end
    EA_Pre:    begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h103; arA23[ 'hc] = 'h299; end
    EA_Rel_An: begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h1C2; arA23[ 'hc] = 'h299; end
    EA_Idx_An: begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h1E3; arA23[ 'hc] = 'h299; end
    EA_Abs_W:  begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h00A; arA23[ 'hc] = 'h299; end
    EA_Abs_L:  begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h1E2; arA23[ 'hc] = 'h299; end
    EA_Rel_PC: begin arIll[ 'hc] = 1'b1; arA1[ 'hc] = `UNDF; arA23[ 'hc] = `UNDF; end
    EA_Idx_PC: begin arIll[ 'hc] = 1'b1; arA1[ 'hc] = `UNDF; arA23[ 'hc] = `UNDF; end
    EA_Imm:    begin arIll[ 'hc] = 1'b1; arA1[ 'hc] = `UNDF; arA23[ 'hc] = `UNDF; end
    default:   begin arIll[ 'hc] = 1'b1; arA1[ 'hc] = `UNDF; arA23[ 'hc] = `UNDF; end
    endcase

3'b101: // Row: 5
    unique case ( col)
    EA_Dn:     begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h3E3; arA23[ 'hc] = `UNDF; end
    EA_An:     begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h3E3; arA23[ 'hc] = `UNDF; end
    EA_Ind:    begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h006; arA23[ 'hc] = 'h299; end
    EA_Post:   begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h21C; arA23[ 'hc] = 'h299; end
    EA_Pre:    begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h103; arA23[ 'hc] = 'h299; end
    EA_Rel_An: begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h1C2; arA23[ 'hc] = 'h299; end
    EA_Idx_An: begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h1E3; arA23[ 'hc] = 'h299; end
    EA_Abs_W:  begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h00A; arA23[ 'hc] = 'h299; end
    EA_Abs_L:  begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h1E2; arA23[ 'hc] = 'h299; end
    EA_Rel_PC: begin arIll[ 'hc] = 1'b1; arA1[ 'hc] = `UNDF; arA23[ 'hc] = `UNDF; end
    EA_Idx_PC: begin arIll[ 'hc] = 1'b1; arA1[ 'hc] = `UNDF; arA23[ 'hc] = `UNDF; end
    EA_Imm:    begin arIll[ 'hc] = 1'b1; arA1[ 'hc] = `UNDF; arA23[ 'hc] = `UNDF; end
    default:   begin arIll[ 'hc] = 1'b1; arA1[ 'hc] = `UNDF; arA23[ 'hc] = `UNDF; end
    endcase

3'b110: // Row: 6
    unique case ( col)
    EA_Dn:     begin arIll[ 'hc] = 1'b1; arA1[ 'hc] = `UNDF; arA23[ 'hc] = `UNDF; end
    EA_An:     begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h3E3; arA23[ 'hc] = `UNDF; end
    EA_Ind:    begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h00B; arA23[ 'hc] = 'h29D; end
    EA_Post:   begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h00F; arA23[ 'hc] = 'h29D; end
    EA_Pre:    begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h179; arA23[ 'hc] = 'h29D; end
    EA_Rel_An: begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h1C6; arA23[ 'hc] = 'h29D; end
    EA_Idx_An: begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h1E7; arA23[ 'hc] = 'h29D; end
    EA_Abs_W:  begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h00E; arA23[ 'hc] = 'h29D; end
    EA_Abs_L:  begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h1E6; arA23[ 'hc] = 'h29D; end
    EA_Rel_PC: begin arIll[ 'hc] = 1'b1; arA1[ 'hc] = `UNDF; arA23[ 'hc] = `UNDF; end
    EA_Idx_PC: begin arIll[ 'hc] = 1'b1; arA1[ 'hc] = `UNDF; arA23[ 'hc] = `UNDF; end
    EA_Imm:    begin arIll[ 'hc] = 1'b1; arA1[ 'hc] = `UNDF; arA23[ 'hc] = `UNDF; end
    default:   begin arIll[ 'hc] = 1'b1; arA1[ 'hc] = `UNDF; arA23[ 'hc] = `UNDF; end
    endcase

3'b111: // Row: 7
    unique case ( col)
    EA_Dn:     begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h15B; arA23[ 'hc] = `UNDF; end
    EA_An:     begin arIll[ 'hc] = 1'b1; arA1[ 'hc] = `UNDF; arA23[ 'hc] = `UNDF; end
    EA_Ind:    begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h006; arA23[ 'hc] = 'h15A; end
    EA_Post:   begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h21C; arA23[ 'hc] = 'h15A; end
    EA_Pre:    begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h103; arA23[ 'hc] = 'h15A; end
    EA_Rel_An: begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h1C2; arA23[ 'hc] = 'h15A; end
    EA_Idx_An: begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h1E3; arA23[ 'hc] = 'h15A; end
    EA_Abs_W:  begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h00A; arA23[ 'hc] = 'h15A; end
    EA_Abs_L:  begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h1E2; arA23[ 'hc] = 'h15A; end
    EA_Rel_PC: begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h1C2; arA23[ 'hc] = 'h15A; end
    EA_Idx_PC: begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h1E3; arA23[ 'hc] = 'h15A; end
    EA_Imm:    begin arIll[ 'hc] = 1'b0; arA1[ 'hc] = 'h0EA; arA23[ 'hc] = 'h15B; end
    default:   begin arIll[ 'hc] = 1'b1; arA1[ 'hc] = `UNDF; arA23[ 'hc] = `UNDF; end
    endcase
endcase

//
// Line: D
//
unique case( row86)

3'b000: // Row: 0
    unique case ( col)
    EA_Dn:     begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h1C1; arA23[ 'hd] = `UNDF; end
    EA_An:     begin arIll[ 'hd] = 1'b1; arA1[ 'hd] = `UNDF; arA23[ 'hd] = `UNDF; end
    EA_Ind:    begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h006; arA23[ 'hd] = 'h1C3; end
    EA_Post:   begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h21C; arA23[ 'hd] = 'h1C3; end
    EA_Pre:    begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h103; arA23[ 'hd] = 'h1C3; end
    EA_Rel_An: begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h1C2; arA23[ 'hd] = 'h1C3; end
    EA_Idx_An: begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h1E3; arA23[ 'hd] = 'h1C3; end
    EA_Abs_W:  begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h00A; arA23[ 'hd] = 'h1C3; end
    EA_Abs_L:  begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h1E2; arA23[ 'hd] = 'h1C3; end
    EA_Rel_PC: begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h1C2; arA23[ 'hd] = 'h1C3; end
    EA_Idx_PC: begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h1E3; arA23[ 'hd] = 'h1C3; end
    EA_Imm:    begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h0EA; arA23[ 'hd] = 'h1C1; end
    default:   begin arIll[ 'hd] = 1'b1; arA1[ 'hd] = `UNDF; arA23[ 'hd] = `UNDF; end
    endcase

3'b001: // Row: 1
    unique case ( col)
    EA_Dn:     begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h1C1; arA23[ 'hd] = `UNDF; end
    EA_An:     begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h1C1; arA23[ 'hd] = `UNDF; end
    EA_Ind:    begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h006; arA23[ 'hd] = 'h1C3; end
    EA_Post:   begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h21C; arA23[ 'hd] = 'h1C3; end
    EA_Pre:    begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h103; arA23[ 'hd] = 'h1C3; end
    EA_Rel_An: begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h1C2; arA23[ 'hd] = 'h1C3; end
    EA_Idx_An: begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h1E3; arA23[ 'hd] = 'h1C3; end
    EA_Abs_W:  begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h00A; arA23[ 'hd] = 'h1C3; end
    EA_Abs_L:  begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h1E2; arA23[ 'hd] = 'h1C3; end
    EA_Rel_PC: begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h1C2; arA23[ 'hd] = 'h1C3; end
    EA_Idx_PC: begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h1E3; arA23[ 'hd] = 'h1C3; end
    EA_Imm:    begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h0EA; arA23[ 'hd] = 'h1C1; end
    default:   begin arIll[ 'hd] = 1'b1; arA1[ 'hd] = `UNDF; arA23[ 'hd] = `UNDF; end
    endcase

3'b010: // Row: 2
    unique case ( col)
    EA_Dn:     begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h1C5; arA23[ 'hd] = `UNDF; end
    EA_An:     begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h1C5; arA23[ 'hd] = `UNDF; end
    EA_Ind:    begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h00B; arA23[ 'hd] = 'h1CB; end
    EA_Post:   begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h00F; arA23[ 'hd] = 'h1CB; end
    EA_Pre:    begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h179; arA23[ 'hd] = 'h1CB; end
    EA_Rel_An: begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h1C6; arA23[ 'hd] = 'h1CB; end
    EA_Idx_An: begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h1E7; arA23[ 'hd] = 'h1CB; end
    EA_Abs_W:  begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h00E; arA23[ 'hd] = 'h1CB; end
    EA_Abs_L:  begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h1E6; arA23[ 'hd] = 'h1CB; end
    EA_Rel_PC: begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h1C6; arA23[ 'hd] = 'h1CB; end
    EA_Idx_PC: begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h1E7; arA23[ 'hd] = 'h1CB; end
    EA_Imm:    begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h0A7; arA23[ 'hd] = 'h1C5; end
    default:   begin arIll[ 'hd] = 1'b1; arA1[ 'hd] = `UNDF; arA23[ 'hd] = `UNDF; end
    endcase

3'b011: // Row: 3
    unique case ( col)
    EA_Dn:     begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h1C9; arA23[ 'hd] = `UNDF; end
    EA_An:     begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h1C9; arA23[ 'hd] = `UNDF; end
    EA_Ind:    begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h006; arA23[ 'hd] = 'h1C7; end
    EA_Post:   begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h21C; arA23[ 'hd] = 'h1C7; end
    EA_Pre:    begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h103; arA23[ 'hd] = 'h1C7; end
    EA_Rel_An: begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h1C2; arA23[ 'hd] = 'h1C7; end
    EA_Idx_An: begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h1E3; arA23[ 'hd] = 'h1C7; end
    EA_Abs_W:  begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h00A; arA23[ 'hd] = 'h1C7; end
    EA_Abs_L:  begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h1E2; arA23[ 'hd] = 'h1C7; end
    EA_Rel_PC: begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h1C2; arA23[ 'hd] = 'h1C7; end
    EA_Idx_PC: begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h1E3; arA23[ 'hd] = 'h1C7; end
    EA_Imm:    begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h0EA; arA23[ 'hd] = 'h1C9; end
    default:   begin arIll[ 'hd] = 1'b1; arA1[ 'hd] = `UNDF; arA23[ 'hd] = `UNDF; end
    endcase

3'b100: // Row: 4
    unique case ( col)
    EA_Dn:     begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h1C1; arA23[ 'hd] = `UNDF; end
    EA_An:     begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h10F; arA23[ 'hd] = `UNDF; end
    EA_Ind:    begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h006; arA23[ 'hd] = 'h299; end
    EA_Post:   begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h21C; arA23[ 'hd] = 'h299; end
    EA_Pre:    begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h103; arA23[ 'hd] = 'h299; end
    EA_Rel_An: begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h1C2; arA23[ 'hd] = 'h299; end
    EA_Idx_An: begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h1E3; arA23[ 'hd] = 'h299; end
    EA_Abs_W:  begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h00A; arA23[ 'hd] = 'h299; end
    EA_Abs_L:  begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h1E2; arA23[ 'hd] = 'h299; end
    EA_Rel_PC: begin arIll[ 'hd] = 1'b1; arA1[ 'hd] = `UNDF; arA23[ 'hd] = `UNDF; end
    EA_Idx_PC: begin arIll[ 'hd] = 1'b1; arA1[ 'hd] = `UNDF; arA23[ 'hd] = `UNDF; end
    EA_Imm:    begin arIll[ 'hd] = 1'b1; arA1[ 'hd] = `UNDF; arA23[ 'hd] = `UNDF; end
    default:   begin arIll[ 'hd] = 1'b1; arA1[ 'hd] = `UNDF; arA23[ 'hd] = `UNDF; end
    endcase

3'b101: // Row: 5
    unique case ( col)
    EA_Dn:     begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h1C1; arA23[ 'hd] = `UNDF; end
    EA_An:     begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h10F; arA23[ 'hd] = `UNDF; end
    EA_Ind:    begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h006; arA23[ 'hd] = 'h299; end
    EA_Post:   begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h21C; arA23[ 'hd] = 'h299; end
    EA_Pre:    begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h103; arA23[ 'hd] = 'h299; end
    EA_Rel_An: begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h1C2; arA23[ 'hd] = 'h299; end
    EA_Idx_An: begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h1E3; arA23[ 'hd] = 'h299; end
    EA_Abs_W:  begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h00A; arA23[ 'hd] = 'h299; end
    EA_Abs_L:  begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h1E2; arA23[ 'hd] = 'h299; end
    EA_Rel_PC: begin arIll[ 'hd] = 1'b1; arA1[ 'hd] = `UNDF; arA23[ 'hd] = `UNDF; end
    EA_Idx_PC: begin arIll[ 'hd] = 1'b1; arA1[ 'hd] = `UNDF; arA23[ 'hd] = `UNDF; end
    EA_Imm:    begin arIll[ 'hd] = 1'b1; arA1[ 'hd] = `UNDF; arA23[ 'hd] = `UNDF; end
    default:   begin arIll[ 'hd] = 1'b1; arA1[ 'hd] = `UNDF; arA23[ 'hd] = `UNDF; end
    endcase

3'b110: // Row: 6
    unique case ( col)
    EA_Dn:     begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h1C5; arA23[ 'hd] = `UNDF; end
    EA_An:     begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h10B; arA23[ 'hd] = `UNDF; end
    EA_Ind:    begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h00B; arA23[ 'hd] = 'h29D; end
    EA_Post:   begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h00F; arA23[ 'hd] = 'h29D; end
    EA_Pre:    begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h179; arA23[ 'hd] = 'h29D; end
    EA_Rel_An: begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h1C6; arA23[ 'hd] = 'h29D; end
    EA_Idx_An: begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h1E7; arA23[ 'hd] = 'h29D; end
    EA_Abs_W:  begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h00E; arA23[ 'hd] = 'h29D; end
    EA_Abs_L:  begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h1E6; arA23[ 'hd] = 'h29D; end
    EA_Rel_PC: begin arIll[ 'hd] = 1'b1; arA1[ 'hd] = `UNDF; arA23[ 'hd] = `UNDF; end
    EA_Idx_PC: begin arIll[ 'hd] = 1'b1; arA1[ 'hd] = `UNDF; arA23[ 'hd] = `UNDF; end
    EA_Imm:    begin arIll[ 'hd] = 1'b1; arA1[ 'hd] = `UNDF; arA23[ 'hd] = `UNDF; end
    default:   begin arIll[ 'hd] = 1'b1; arA1[ 'hd] = `UNDF; arA23[ 'hd] = `UNDF; end
    endcase

3'b111: // Row: 7
    unique case ( col)
    EA_Dn:     begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h1C5; arA23[ 'hd] = `UNDF; end
    EA_An:     begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h1C5; arA23[ 'hd] = `UNDF; end
    EA_Ind:    begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h00B; arA23[ 'hd] = 'h1CB; end
    EA_Post:   begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h00F; arA23[ 'hd] = 'h1CB; end
    EA_Pre:    begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h179; arA23[ 'hd] = 'h1CB; end
    EA_Rel_An: begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h1C6; arA23[ 'hd] = 'h1CB; end
    EA_Idx_An: begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h1E7; arA23[ 'hd] = 'h1CB; end
    EA_Abs_W:  begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h00E; arA23[ 'hd] = 'h1CB; end
    EA_Abs_L:  begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h1E6; arA23[ 'hd] = 'h1CB; end
    EA_Rel_PC: begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h1C6; arA23[ 'hd] = 'h1CB; end
    EA_Idx_PC: begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h1E7; arA23[ 'hd] = 'h1CB; end
    EA_Imm:    begin arIll[ 'hd] = 1'b0; arA1[ 'hd] = 'h0A7; arA23[ 'hd] = 'h1C5; end
    default:   begin arIll[ 'hd] = 1'b1; arA1[ 'hd] = `UNDF; arA23[ 'hd] = `UNDF; end
    endcase
endcase
end


endmodule
