module fx68kRom
#(
    parameter bit     OUTPUT_REG  = 1,
    parameter integer ADDR_WIDTH  = 10,
    parameter integer DATA_WIDTH  = 32,
    parameter         INIT_FILE   = "NONE",
    parameter         FPGA_DEVICE = "Stratix",
    parameter         BRAM_TYPE   = "M4K"
)
(
    input                   rst,
    input                   clk,
    input                   clk_ena,
    input  [ADDR_WIDTH-1:0] addr,
    output [DATA_WIDTH-1:0] q
);

    altsyncram
    #(
        .address_aclr_a  ("NONE"),
        .init_file       (INIT_FILE),
        .intended_device_family (FPGA_DEVICE),
        .lpm_hint        ("ENABLE_RUNTIME_MOD=NO"),
        .lpm_type        ("altsyncram"),
        .numwords_a      (1 << ADDR_WIDTH),
        .operation_mode  ("ROM"),
        .outdata_aclr_a  ((OUTPUT_REG) ? "CLEAR1" : "NONE"),
        .outdata_reg_a   ((OUTPUT_REG) ? "CLOCK1" : "UNREGISTERED"),
        .ram_block_type  (BRAM_TYPE),
        .widthad_a       (ADDR_WIDTH),
        .width_a         (DATA_WIDTH),
        .width_byteena_a (1)
    )
    U_altsyncram
    (
        .aclr0           (1'b0),
        .aclr1           ((OUTPUT_REG) ? rst : 1'b0),
        .clock0          (clk),
        .clock1          ((OUTPUT_REG) ? clk : 1'b1),
        .clocken0        (1'b1),
        .clocken1        ((OUTPUT_REG) ? clk_ena : 1'b1),
        .clocken2        (1'b1),
        .clocken3        (1'b1),
        
        .address_a       (addr),
        .addressstall_a  (1'b0),
        .rden_a          (1'b1),
        .wren_a          (1'b0),
        .byteena_a       (1'b1),
        .data_a          ({DATA_WIDTH{1'b1}}),
        .q_a             (q),
        
        .address_b       (1'b1),
        .addressstall_b  (1'b0),
        .rden_b          (1'b1),
        .wren_b          (1'b0),
        .byteena_b       (1'b1),
        .data_b          (1'b1),
        .q_b             (/* open */),
        
        .eccstatus       (/* open */)
    );
    
endmodule
