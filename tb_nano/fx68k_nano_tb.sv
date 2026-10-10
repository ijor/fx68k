import fx68k_pkg::*;

module fx68k_nano_tb
(
    input                   rst,
    input                   clk,
    input                   enPhi1,
    input                   enPhi2,
    output [NANO_WIDTH-1:0] nanoOut1,
    output [NANO_WIDTH-1:0] nanoOut2
);
    localparam [63:0]
        c_UADDR_MASK = 64'b0101010101010101_1010101010101010_1111000010101111_0101010101010101;

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

        if (rst) begin
            tState <= 5'b00100; // T2
        end
        else begin
            tState <= 5'b00000;
            case (1'b1)
                tState[T0]:
                begin
                    if (enPhi2) begin
                        tState[T4] <= 1'b1;
                    end
                    else begin
                        tState[T0] <= 1'b1;
                    end
                end
                tState[T1]:
                begin
                    if (enPhi2) begin
                        tState[T2] <= 1'b1;
                    end
                    else begin
                        tState[T1] <= 1'b1;
                    end
                end
                tState[T2]:
                begin
                    if (enPhi1) begin
                        tState[T3] <= 1'b1;
                    end
                    else begin
                        tState[T2] <= 1'b1;
                    end
                end
                tState[T3]:
                begin
                    if (enPhi2) begin
                        tState[T4] <= 1'b1;
                    end
                    else begin
                        tState[T3] <= 1'b1;
                    end
                end
                tState[T4]:
                begin
                    if (enPhi1) begin
                        tState[T1] <= 1'b1;
                    end
                    else begin
                        tState[T4] <= 1'b1;
                    end
                end
            endcase
        end
    end

    wire enT1 = enPhi1 & tState[T4];
    wire enT2 = enPhi2 & tState[T1];
    wire enT3 = enPhi1 & tState[T2];
    wire enT4 = enPhi2 & (tState[T0] | tState[T3]);

    wire [UADDR_WIDTH-1:0] wMicroAddr;
    reg  [UADDR_WIDTH-1:0] rMicroAddr_t1;

    wire [NADDR_WIDTH-1:0] wNanoAddr1;
    wire [NADDR_WIDTH-1:0] wNanoAddr2;
    reg  [NADDR_WIDTH-1:0] rNanoAddr1_t1;
    reg  [NADDR_WIDTH-1:0] rNanoAddr2_t1;
    wire  [NANO_WIDTH-1:0] wNanoLatch1_t3;
    wire  [NANO_WIDTH-1:0] wNanoLatch2_t3;
    
    assign wMicroAddr = rMicroAddr_t1 + 'd1;

    always_ff @(posedge clk) begin : ROM_ADDR_T1

        if (rst) begin
            rMicroAddr_t1 <= 'b0;
            rNanoAddr1_t1 <= 'b0;
            rNanoAddr2_t1 <= 'b0;
        end
        else if (enT1) begin
            rMicroAddr_t1 <= wMicroAddr;
            rNanoAddr1_t1 <= wNanoAddr1;
            rNanoAddr2_t1 <= wNanoAddr2;
        end
    end

    microToNanoAddr_old U_microToNanoAddr1
    (
        .uAddr   (wMicroAddr),
        .orgAddr (wNanoAddr1)
    );

    microToNanoAddr_new U_microToNanoAddr2
    (
        .uAddr   (wMicroAddr),
        .orgAddr (wNanoAddr2)
    );
    
    wire wMicroAddrVld = c_UADDR_MASK[rMicroAddr_t1[UADDR_WIDTH-1:4]];

    fx68kRom
    #(
       .OUTPUT_REG  (1),
       .ADDR_WIDTH  (NADDR_WIDTH),
       .DATA_WIDTH  (NANO_WIDTH),
       .INIT_FILE   ("nanorom.mem")
    )
    U_nanoRom1_t3
    (
        .rst        (rst),
        .clk        (clk),
        .clk_ena    (enT3 & wMicroAddrVld),
        .addr       (rNanoAddr1_t1),
        .q          (wNanoLatch1_t3)
    );
    
    assign nanoOut1 = wNanoLatch1_t3;

    fx68kRom
    #(
       .OUTPUT_REG  (1),
       .ADDR_WIDTH  (NADDR_WIDTH),
       .DATA_WIDTH  (NANO_WIDTH),
       .INIT_FILE   ("nanorom2.mem")
    )
    U_nanoRom2_t3
    (
        .rst        (rst),
        .clk        (clk),
        .clk_ena    (enT3 & wMicroAddrVld),
        .addr       (rNanoAddr2_t1),
        .q          (wNanoLatch2_t3)
    );

    assign nanoOut2 = wNanoLatch2_t3;

    always_ff @(posedge clk) begin : ROM_CHECK_T1

        if (enT1 & wMicroAddrVld) begin
            $display("%0h : %0h / %0h -> %s",
                     rMicroAddr_t1,
                     wNanoLatch1_t3,
                     wNanoLatch2_t3,
                     (wNanoLatch1_t3 == wNanoLatch2_t3) ? "OK" : "KO");
            if (rMicroAddr_t1 == 'h3EF) $finish;
        end
    end

endmodule

// Translate uaddr to nanoaddr (old)
module microToNanoAddr_old
(
    input  [UADDR_WIDTH-1:0] uAddr,
    output [NADDR_WIDTH-1:0] orgAddr
);
    logic [NADDR_WIDTH-1:2] orgBase;

    always @(uAddr) begin
        // nano ROM (136 addresses)
        case (uAddr[UADDR_WIDTH-1:2])
            'h00: orgBase = 7'h00;
            'h01: orgBase = 7'h01;
            'h02: orgBase = 7'h02;
            'h03: orgBase = 7'h02;
            'h08: orgBase = 7'h03;
            'h09: orgBase = 7'h04;
            'h0A: orgBase = 7'h05;
            'h0B: orgBase = 7'h05;
            'h10: orgBase = 7'h06;
            'h11: orgBase = 7'h07;
            'h12: orgBase = 7'h08;
            'h13: orgBase = 7'h08;
            'h18: orgBase = 7'h09;
            'h19: orgBase = 7'h0A;
            'h1A: orgBase = 7'h0B;
            'h1B: orgBase = 7'h0B;
            'h20: orgBase = 7'h0C;
            'h21: orgBase = 7'h0D;
            'h22: orgBase = 7'h0E;
            'h23: orgBase = 7'h0D;
            'h28: orgBase = 7'h0F;
            'h29: orgBase = 7'h10;
            'h2A: orgBase = 7'h11;
            'h2B: orgBase = 7'h10;
            'h30: orgBase = 7'h12;
            'h31: orgBase = 7'h13;
            'h32: orgBase = 7'h14;
            'h33: orgBase = 7'h14;
            'h38: orgBase = 7'h15;
            'h39: orgBase = 7'h16;
            'h3A: orgBase = 7'h17;
            'h3B: orgBase = 7'h17;
            'h40: orgBase = 7'h18;
            'h41: orgBase = 7'h18;
            'h42: orgBase = 7'h18;
            'h43: orgBase = 7'h18;
            'h44: orgBase = 7'h19;
            'h45: orgBase = 7'h19;
            'h46: orgBase = 7'h19;
            'h47: orgBase = 7'h19;
            'h48: orgBase = 7'h1A;
            'h49: orgBase = 7'h1A;
            'h4A: orgBase = 7'h1A;
            'h4B: orgBase = 7'h1A;
            'h4C: orgBase = 7'h1B;
            'h4D: orgBase = 7'h1B;
            'h4E: orgBase = 7'h1B;
            'h4F: orgBase = 7'h1B;
            'h54: orgBase = 7'h1C;
            'h55: orgBase = 7'h1D;
            'h56: orgBase = 7'h1E;
            'h57: orgBase = 7'h1F;
            'h5C: orgBase = 7'h20;
            'h5D: orgBase = 7'h21;
            'h5E: orgBase = 7'h22;
            'h5F: orgBase = 7'h23;
            'h70: orgBase = 7'h24;
            'h71: orgBase = 7'h24;
            'h72: orgBase = 7'h24;
            'h73: orgBase = 7'h24;
            'h74: orgBase = 7'h24;
            'h75: orgBase = 7'h24;
            'h76: orgBase = 7'h24;
            'h77: orgBase = 7'h24;
            'h78: orgBase = 7'h25;
            'h79: orgBase = 7'h25;
            'h7A: orgBase = 7'h25;
            'h7B: orgBase = 7'h25;
            'h7C: orgBase = 7'h25;
            'h7D: orgBase = 7'h25;
            'h7E: orgBase = 7'h25;
            'h7F: orgBase = 7'h25;
            'h84: orgBase = 7'h26;
            'h85: orgBase = 7'h27;
            'h86: orgBase = 7'h28;
            'h87: orgBase = 7'h29;
            'h8C: orgBase = 7'h2A;
            'h8D: orgBase = 7'h2B;
            'h8E: orgBase = 7'h2C;
            'h8F: orgBase = 7'h2D;
            'h94: orgBase = 7'h2E;
            'h95: orgBase = 7'h2F;
            'h96: orgBase = 7'h30;
            'h97: orgBase = 7'h31;
            'h9C: orgBase = 7'h32;
            'h9D: orgBase = 7'h33;
            'h9E: orgBase = 7'h34;
            'h9F: orgBase = 7'h35;
            'hA4: orgBase = 7'h36;
            'hA5: orgBase = 7'h36;
            'hA6: orgBase = 7'h37;
            'hA7: orgBase = 7'h37;
            'hAC: orgBase = 7'h38;
            'hAD: orgBase = 7'h38;
            'hAE: orgBase = 7'h39;
            'hAF: orgBase = 7'h39;
            'hB4: orgBase = 7'h3A;
            'hB5: orgBase = 7'h3A;
            'hB6: orgBase = 7'h3B;
            'hB7: orgBase = 7'h3B;
            'hBC: orgBase = 7'h3C;
            'hBD: orgBase = 7'h3C;
            'hBE: orgBase = 7'h3D;
            'hBF: orgBase = 7'h3D;
            'hC0: orgBase = 7'h3E;
            'hC1: orgBase = 7'h3F;
            'hC2: orgBase = 7'h40;
            'hC3: orgBase = 7'h41;
            'hC8: orgBase = 7'h42;
            'hC9: orgBase = 7'h43;
            'hCA: orgBase = 7'h44;
            'hCB: orgBase = 7'h45;
            'hD0: orgBase = 7'h46;
            'hD1: orgBase = 7'h47;
            'hD2: orgBase = 7'h48;
            'hD3: orgBase = 7'h49;
            'hD8: orgBase = 7'h4A;
            'hD9: orgBase = 7'h4B;
            'hDA: orgBase = 7'h4C;
            'hDB: orgBase = 7'h4D;
            'hE0: orgBase = 7'h4E;
            'hE1: orgBase = 7'h4E;
            'hE2: orgBase = 7'h4F;
            'hE3: orgBase = 7'h4F;
            'hE8: orgBase = 7'h50;
            'hE9: orgBase = 7'h50;
            'hEA: orgBase = 7'h51;
            'hEB: orgBase = 7'h51;
            'hF0: orgBase = 7'h52;
            'hF1: orgBase = 7'h52;
            'hF2: orgBase = 7'h52;
            'hF3: orgBase = 7'h52;
            'hF8: orgBase = 7'h53;
            'hF9: orgBase = 7'h53;
            'hFA: orgBase = 7'h53;
            'hFB: orgBase = 7'h53;
            default: orgBase = 7'h54;
        endcase
    end

    assign orgAddr = { orgBase, uAddr[1:0] };

endmodule

// Translate uaddr to nanoaddr (new)
module microToNanoAddr_new
(
    input  [UADDR_WIDTH-1:0] uAddr,
    output [NADDR_WIDTH-1:0] orgAddr
);
    logic [NADDR_WIDTH-1:4] orgBase;

    always @ (uAddr) begin
        casez (uAddr[UADDR_WIDTH-1:4])
            'b00_000? : orgBase = 5'h00;
            'b00_001? : orgBase = 5'h01;
            'b00_010? : orgBase = 5'h02;
            'b00_011? : orgBase = 5'h03;
            'b00_100? : orgBase = 5'h04;
            'b00_101? : orgBase = 5'h05;
            'b00_110? : orgBase = 5'h06;
            'b00_111? : orgBase = 5'h07;

            'b01_?000 : orgBase = 5'h10;
            'b01_?001 : orgBase = 5'h11;
            'b01_?010 : orgBase = 5'h12;
            'b01_?011 : orgBase = 5'h13;
            'b01_010? : orgBase = 5'h14;
            'b01_011? : orgBase = 5'h15;
            'b01_110? : orgBase = 5'h16;
            'b01_111? : orgBase = 5'h17;

            'b10_000? : orgBase = 5'h08;
            'b10_001? : orgBase = 5'h09;
            'b10_010? : orgBase = 5'h0A;
            'b10_011? : orgBase = 5'h0B;
            'b10_100? : orgBase = 5'h0C;
            'b10_101? : orgBase = 5'h0D;
            'b10_110? : orgBase = 5'h0E;
            'b10_111? : orgBase = 5'h0F;

            'b11_000? : orgBase = 5'h18;
            'b11_001? : orgBase = 5'h19;
            'b11_010? : orgBase = 5'h1A;
            'b11_011? : orgBase = 5'h1B;
            'b11_100? : orgBase = 5'h1C;
            'b11_101? : orgBase = 5'h1D;
            'b11_110? : orgBase = 5'h1E;
            'b11_111? : orgBase = 5'h1F;
        endcase
    end
    
    assign orgAddr = { orgBase, uAddr[3:0]};

endmodule
