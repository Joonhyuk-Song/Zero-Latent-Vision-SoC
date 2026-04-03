`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
//////////////////////////////////////////////////////////////////////////////////
// -----------------------------------------------------------------------------
// Module: reg_bus
// Description: A Synchronous Register with an Enable signal.
// This is used to store data and hold it stable across multiple clock cycles.
// -----------------------------------------------------------------------------

module reg_bus #(parameter DW=32) (
    input clk,                       // System clock
    input Reset,                     // Synchronous reset: Clears data to 0
    input Enable,                    // Load control: Only update when this is 1
    input [DW-1:0] Input,            // Data waiting to be stored
    output reg [DW-1:0] Output       // The currently stored data
);

    // --- Sequential Logic ---
    // This happens only at the exact moment the clock edge rises.
    always @(posedge clk) begin
        
        // 1. Reset takes priority.
        // If Reset is high, the stored data is cleared immediately.
        if (Reset) begin
            Output <= {DW{1'b0}};    // All DW bits are set to 0
        end 
        
        // 2. Enable check.
        // If Reset is low, we check if we are allowed to "load" new data.
        // If Enable is 0, the Output keeps its current value indefinitely.
        else if (Enable) begin
            Output <= Input;         // New data is captured/stored
        end
        
    end

endmodule