`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/30/2026 07:06:23 PM
// Design Name: 
// Module Name: comb_add
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module combinational_adder #(parameter W=32) (
    input wire signed [W-1:0] a,    // First addend
    input wire signed [W-1:0] b,    // Second addend
    output wire signed [W-1:0] y    // Sum result
);
    // Continuous assignment: y is always equal to a + b
    assign y = a + b;
endmodule