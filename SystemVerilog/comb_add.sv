`timescale 1ns / 1ps
module combinational_adder #(parameter W = 32) (
    input  logic signed [W-1:0] a,
    input  logic signed [W-1:0] b,
    output logic signed [W-1:0] y
);
    assign y = a + b;
endmodule