`timescale 1ns / 1ps
module b_rom #(parameter DW = 16, parameter AW = 8) (
    input  logic              clk,
    input  logic [AW-1:0]    Read_Address,
    input  logic              Read_Enable,
    output logic signed [DW-1:0] Read_Data
);
    logic [DW-1:0] mem [0:(1<<AW)-1];
    initial begin
        mem[0]  = 16'h0026;
        mem[1]  = 16'hfff6;
        mem[2]  = 16'hffdf;
        mem[3]  = 16'h003f;
        mem[4]  = 16'h008a;
        mem[5]  = 16'hffe1;
        mem[6]  = 16'h005a;
        mem[7]  = 16'h000a;
        mem[8]  = 16'hffb3;
        mem[9]  = 16'h0069;
        mem[10] = 16'h0073;
        mem[11] = 16'hffc0;
        mem[12] = 16'h0066;
        mem[13] = 16'h007f;
        mem[14] = 16'h00a2;
        mem[15] = 16'h005c;
        mem[16] = 16'hfee6;
        mem[17] = 16'hff53;
    end
    always_ff @(posedge clk)
        if (Read_Enable) Read_Data <= mem[Read_Address];
endmodule
