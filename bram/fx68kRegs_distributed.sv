`timescale 1 ns / 1 ns

module fx68kRegs
(
    input          clk,
    input          clk_ena,

    // Read/write port A
    input    [4:0] address_a,
    input          wren_a,
    input    [3:0] byteena_a,
    input   [31:0] data_a,
    output  [31:0] q_a,

    // Read/write port B
    input    [4:0] address_b,
    input          wren_b,
    input    [3:0] byteena_b,
    input   [31:0] data_b,
    output  [31:0] q_b
);

//=============================================================================
// Inferred distributed RAMs (128 SLICEs)
//=============================================================================

// A : Write, A : Read
(* syn_ramstyle = "distributed" *) reg [15:0] r_ram_L_aa [0:31]; // 16 SLICEs
(* syn_ramstyle = "distributed" *) reg  [7:0] r_ram_W_aa [0:31]; // 8 SLICEs
(* syn_ramstyle = "distributed" *) reg  [7:0] r_ram_B_aa [0:31]; // 8 SLICEs
// A : Write, B : Read
(* syn_ramstyle = "distributed" *) reg [15:0] r_ram_L_ab [0:31];
(* syn_ramstyle = "distributed" *) reg  [7:0] r_ram_W_ab [0:31];
(* syn_ramstyle = "distributed" *) reg  [7:0] r_ram_B_ab [0:31];
// B : Write, A : Read
(* syn_ramstyle = "distributed" *) reg [15:0] r_ram_L_ba [0:31];
(* syn_ramstyle = "distributed" *) reg  [7:0] r_ram_W_ba [0:31];
(* syn_ramstyle = "distributed" *) reg  [7:0] r_ram_B_ba [0:31];
// B : Write, B : Read
(* syn_ramstyle = "distributed" *) reg [15:0] r_ram_L_bb [0:31];
(* syn_ramstyle = "distributed" *) reg  [7:0] r_ram_W_bb [0:31];
(* syn_ramstyle = "distributed" *) reg  [7:0] r_ram_B_bb [0:31];

//=============================================================================
// Last value select (12 SLICEs)
//=============================================================================

(* syn_ramstyle = "distributed" *) reg [2:0] r_lvs_aa [0:31]; // 3 SLICEs
(* syn_ramstyle = "distributed" *) reg [2:0] r_lvs_ab [0:31];
(* syn_ramstyle = "distributed" *) reg [2:0] r_lvs_ba [0:31];
(* syn_ramstyle = "distributed" *) reg [2:0] r_lvs_bb [0:31];

    always_ff @(posedge clk) begin : LAST_VALUE_SEL

        if (clk_ena & wren_a) begin
            r_lvs_aa[address_a][0] <= (byteena_a[0]) ? r_lvs_ba[address_a][0] : r_lvs_aa[address_a][0];
            r_lvs_ab[address_a][0] <= (byteena_a[0]) ? r_lvs_ba[address_a][0] : r_lvs_aa[address_a][0];
            r_lvs_aa[address_a][1] <= (byteena_a[1]) ? r_lvs_ba[address_a][1] : r_lvs_aa[address_a][1];
            r_lvs_ab[address_a][1] <= (byteena_a[1]) ? r_lvs_ba[address_a][1] : r_lvs_aa[address_a][1];
            r_lvs_aa[address_a][2] <= (byteena_a[2]) ? r_lvs_ba[address_a][2] : r_lvs_aa[address_a][2];
            r_lvs_ab[address_a][2] <= (byteena_a[2]) ? r_lvs_ba[address_a][2] : r_lvs_aa[address_a][2];
        end

        if (clk_ena & wren_b) begin
            r_lvs_ba[address_b][0] <= (byteena_b[0]) ? ~r_lvs_ab[address_b][0] : r_lvs_bb[address_b][0];
            r_lvs_bb[address_b][0] <= (byteena_b[0]) ? ~r_lvs_ab[address_b][0] : r_lvs_bb[address_b][0];
            r_lvs_ba[address_b][1] <= (byteena_b[1]) ? ~r_lvs_ab[address_b][1] : r_lvs_bb[address_b][1];
            r_lvs_bb[address_b][1] <= (byteena_b[1]) ? ~r_lvs_ab[address_b][1] : r_lvs_bb[address_b][1];
            r_lvs_ba[address_b][2] <= (byteena_b[2]) ? ~r_lvs_ab[address_b][2] : r_lvs_bb[address_b][2];
            r_lvs_bb[address_b][2] <= (byteena_b[2]) ? ~r_lvs_ab[address_b][2] : r_lvs_bb[address_b][2];
        end
    end

//=============================================================================
// Port A access
//=============================================================================

wire  [2:0] w_lvs_a = r_lvs_aa[address_a] ^ r_lvs_ba[address_a];
wire [15:0] w_L_a   = (w_lvs_a[2]) ? r_ram_L_ba[address_a] : r_ram_L_aa[address_a];
wire  [7:0] w_W_a   = (w_lvs_a[1]) ? r_ram_W_ba[address_a] : r_ram_W_aa[address_a];
wire  [7:0] w_B_a   = (w_lvs_a[0]) ? r_ram_B_ba[address_a] : r_ram_B_aa[address_a];

reg  [31:0] r_q_a;

    always_ff @(posedge clk) begin : PORT_A
        
        if (clk_ena) begin
            if (byteena_a[2] & wren_a) begin
                r_ram_L_aa[address_a] <= data_a[31:16];
                r_ram_L_ab[address_a] <= data_a[31:16];
                r_q_a[31:16]          <= data_a[31:16];
            end
            else begin
                r_q_a[31:16]          <= w_L_a;
            end

            if (byteena_a[1] & wren_a) begin
                r_ram_W_aa[address_a] <= data_a[15: 8];
                r_ram_W_ab[address_a] <= data_a[15: 8];
                r_q_a[15: 8]          <= data_a[15: 8];
            end
            else begin
                r_q_a[15: 8]          <= w_W_a;
            end

            if (byteena_a[0] & wren_a) begin
                r_ram_B_aa[address_a] <= data_a[ 7: 0];
                r_ram_B_ab[address_a] <= data_a[ 7: 0];
                r_q_a[ 7: 0]          <= data_a[ 7: 0];
            end
            else begin
                r_q_a[ 7: 0]          <= w_B_a;
            end
        end
    end

    assign q_a = r_q_a;

//=============================================================================
// Port B access
//=============================================================================

wire  [2:0] w_lvs_b = r_lvs_ab[address_b] ^ r_lvs_bb[address_b];
wire [15:0] w_L_b   = (w_lvs_b[2]) ? r_ram_L_bb[address_b] : r_ram_L_ab[address_b];
wire  [7:0] w_W_b   = (w_lvs_b[1]) ? r_ram_W_bb[address_b] : r_ram_W_ab[address_b];
wire  [7:0] w_B_b   = (w_lvs_b[0]) ? r_ram_B_bb[address_b] : r_ram_B_ab[address_b];

reg  [31:0] r_q_b;
    
    always_ff @(posedge clk) begin : PORT_B
    
        if (clk_ena) begin
            if (byteena_b[2] & wren_b) begin
                r_ram_L_ba[address_b] <= data_b[31:16];
                r_ram_L_bb[address_b] <= data_b[31:16];
                r_q_b[31:16]          <= data_b[31:16];
            end
            else begin
                r_q_b[31:16]          <= w_L_b;
            end

            if (byteena_b[1] & wren_b) begin
                r_ram_W_ba[address_b] <= data_b[15: 8];
                r_ram_W_bb[address_b] <= data_b[15: 8];
                r_q_b[15: 8]          <= data_b[15: 8];
            end
            else begin
                r_q_b[15: 8]          <= w_W_b;
            end

            if (byteena_b[0] & wren_b) begin
                r_ram_B_ba[address_b] <= data_b[ 7: 0];
                r_ram_B_bb[address_b] <= data_b[ 7: 0];
                r_q_b[ 7: 0]          <= data_b[ 7: 0];
            end
            else begin
                r_q_b[ 7: 0]          <= w_B_b;
            end
        end
    end

    assign q_b = r_q_b;

//=============================================================================
// For simulation
//=============================================================================

`ifdef verilator3
wire [15:0] ram_L [0:17];
wire  [7:0] ram_W [0:17];
wire  [7:0] ram_B [0:17];

genvar _i;

generate
    for (_i = 0; _i <= 17; _i = _i +1) begin : GEN_DEBUG_REGS
        assign ram_L[_i] = (r_lvs_ab[_i][2] ^ r_lvs_bb[_i][2]) ? r_ram_L_bb[_i] : r_ram_L_ab[_i];
        assign ram_W[_i] = (r_lvs_ab[_i][1] ^ r_lvs_bb[_i][1]) ? r_ram_W_bb[_i] : r_ram_W_ab[_i];
        assign ram_B[_i] = (r_lvs_ab[_i][0] ^ r_lvs_bb[_i][0]) ? r_ram_B_bb[_i] : r_ram_B_ab[_i];
    end
endgenerate

`endif

endmodule
