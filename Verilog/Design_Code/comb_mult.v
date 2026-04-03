`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 

module combinational_multiplier #(parameter W=32) (
    input wire signed [W-1:0] a,    // Multiplicand
    input wire signed [W-1:0] b,    // Multiplier
    output wire signed [(2*W)-1:0] y // Product result
);
    // Continuous assignment: y is always equal to a * b
    assign y = a * b;
endmodule