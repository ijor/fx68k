module fx68kRom
#(
    parameter bit     OUTPUT_REG = 1,
    parameter integer ADDR_WIDTH = 10,
    parameter integer DATA_WIDTH = 32,
    parameter string  INIT_FILE  = "NONE"
)
(
    input                   rst,
    input                   clk,
    input                   clk_ena,
    input  [ADDR_WIDTH-1:0] addr,
    output [DATA_WIDTH-1:0] q
);

//=============================================================================
// Inferred ROM block
//=============================================================================

    logic [DATA_WIDTH-1:0] rom [0:(1 << ADDR_WIDTH)-1];

//=============================================================================
// ROM content
//=============================================================================

    initial begin : ROM_INIT
        integer i;
        
        if (INIT_FILE == "NONE") begin
            for (i = 0; i < (1 << ADDR_WIDTH); i = i + 1) begin
                rom[i] = {DATA_WIDTH{1'b0}};
            end
        end
        else begin
            $readmemb(INIT_FILE, rom);
        end
    end
    
//=============================================================================
// ROM read
//=============================================================================

    reg [DATA_WIDTH-1:0] r_rom_q_p0;
    
    always_ff @(posedge clk) begin : ROM_READ_P0
    
        r_rom_q_p0 <= rom[addr];
    end
    
//=============================================================================
// Asynchronous reset on registered output
//=============================================================================

    reg [DATA_WIDTH-1:0] r_rom_q_p1;
    
    always_ff @(posedge rst or posedge clk) begin : OUTPUT_REG_P1
    
        if (rst) begin
            r_rom_q_p1 <= {DATA_WIDTH{1'b0}};
        end
        else if (clk_ena) begin
            r_rom_q_p1 <= r_rom_q_p0;
        end
    end
    
    assign q = (OUTPUT_REG) ? r_rom_q_p1 : r_rom_q_p0;
    
endmodule
