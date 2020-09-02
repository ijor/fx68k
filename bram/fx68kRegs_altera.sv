module fx68kRegs
#(
    parameter FPGA_DEVICE = "Stratix",
    parameter BRAM_TYPE   = "M4K"
)
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

    altsyncram
    #(
        .address_aclr_a   ("NONE"),
        .address_aclr_b   ("NONE"),
        .address_reg_b    ("CLOCK0"),
        .byteena_aclr_a   ("NONE"),
        .byteena_aclr_b   ("NONE"),
        .byteena_reg_b    ("CLOCK0"),
        .byte_size        (8),
        .indata_aclr_a    ("NONE"),
        .indata_aclr_b    ("NONE"),
        .indata_reg_b     ("CLOCK0"),
        .intended_device_family (FPGA_DEVICE),
        .lpm_type         ("altsyncram"),
        .numwords_a       (32),
        .numwords_b       (32),
        .operation_mode   ("BIDIR_DUAL_PORT"),
        .outdata_aclr_a   ("NONE"),
        .outdata_aclr_b   ("NONE"),
        .outdata_reg_a    ("UNREGISTERED"),
        .outdata_reg_b    ("UNREGISTERED"),
        .power_up_uninitialized ("FALSE"),
        .ram_block_type   (BRAM_TYPE),
        .read_during_write_mode_mixed_ports ("DONT_CARE"),
        .widthad_a        (5),
        .widthad_b        (5),
        .width_a          (32),
        .width_b          (32),
        .width_byteena_a  (4),
        .width_byteena_b  (4),
        .wrcontrol_aclr_a ("NONE"),
        .wrcontrol_aclr_b ("NONE"),
        .wrcontrol_wraddress_reg_b ("CLOCK0")
    )
    U_altsyncram
    (
        // Clock & reset
        .aclr0            (1'b0),
        .aclr1            (1'b0),
        .clock0           (clk),
        .clock1           (1'b1),
        .clocken0         (clk_ena),
        .clocken1         (1'b1),
        .clocken2         (1'b1),
        .clocken3         (1'b1),
        // Port A
        .rden_a           (1'b1),
        .wren_a           (wren_a),
        .byteena_a        (byteena_a),
        .address_a        (address_a),
        .addressstall_a   (1'b0),
        .data_a           (data_a),
        .q_a              (q_a),
        // Port B
        .rden_b           (1'b1),
        .wren_b           (wren_b),
        .byteena_b        (byteena_b),
        .address_b        (address_b),
        .addressstall_b   (1'b0),
        .data_b           (data_b),
        .q_b              (q_b),
        
        .eccstatus        ()
    );

endmodule
