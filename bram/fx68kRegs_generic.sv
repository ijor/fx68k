module fx68kRegs
(
    input         clk,
    input         clk_ena,
    
    input   [4:0] address_a,
    input         wren_a,
    input   [3:0] byteena_a,
    input  [31:0] data_a,
    output [31:0] q_a,
    
    input   [4:0] address_b,
    input         wren_b,
    input   [3:0] byteena_b,
    input  [31:0] data_b,
    output [31:0] q_b
);

//=============================================================================
// Inferred blocks RAM
//=============================================================================

    logic [15:0] ram_L [0:31];
    logic [ 7:0] ram_W [0:31];
    logic [ 7:0] ram_B [0:31];

//=============================================================================
// Port A access
//=============================================================================
    
    reg [31:0] r_q_a;
    
    always_ff @(posedge clk) begin : PORT_A
    
        if (clk_ena) begin
            if (byteena_a[2] & wren_a) begin
                ram_L[address_a] <= data_a[31:16];
                r_q_a[31:16] <= data_a[31:16];
            end
            else begin
                r_q_a[31:16] <= ram_L[address_a];
            end
            if (byteena_a[1] & wren_a) begin
                ram_W[address_a] <= data_a[15: 8];
                r_q_a[15: 8] <= data_a[15: 8];
            end
            else begin
                r_q_a[15: 8] <= ram_W[address_a];
            end
            if (byteena_a[0] & wren_a) begin
                ram_B[address_a] <= data_a[ 7: 0];
                r_q_a[ 7: 0] <= data_a[ 7: 0];
            end
            else begin
                r_q_a[ 7: 0] <= ram_B[address_a];
            end
        end
    end
    
    assign q_a = r_q_a;

//=============================================================================
// Port B access
//=============================================================================

    reg [31:0] r_q_b;
    
    always_ff @(posedge clk) begin : PORT_B
    
        if (clk_ena) begin
            if (byteena_b[2] & wren_b) begin
                ram_L[address_b] <= data_b[31:16];
                r_q_b[31:16] <= data_b[31:16];
            end
            else begin
                r_q_b[31:16] <= ram_L[address_b];
            end
            if (byteena_b[1] & wren_b) begin
                ram_W[address_b] <= data_b[15: 8];
                r_q_b[15: 8] <= data_b[15: 8];
            end
            else begin
                r_q_b[15: 8] <= ram_W[address_b];
            end
            if (byteena_b[0] & wren_b) begin
                ram_B[address_b] <= data_b[ 7: 0];
                r_q_b[ 7: 0] <= data_b[ 7: 0];
            end
            else begin
                r_q_b[ 7: 0] <= ram_B[address_b];
            end
        end
    end

    assign q_b = r_q_b;

endmodule
