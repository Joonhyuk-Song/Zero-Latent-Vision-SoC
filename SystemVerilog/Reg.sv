// =============================================================================
// Module: reg_bus
// Description: Synchronous register with synchronous reset and load enable.
// =============================================================================
`timescale 1ns / 1ps

module reg_bus #(parameter DW = 32) (
    input  logic             clk,
    input  logic             Reset,
    input  logic             Enable,
    input  logic [DW-1:0]   Input,
    output logic [DW-1:0]   Output
);
    always_ff @(posedge clk) begin
        if (Reset)       Output <= '0;
        else if (Enable) Output <= Input;
    end
endmodule
