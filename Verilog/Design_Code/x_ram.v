`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
//////////////////////////////////////////////////////////////////////////////////

// -----------------------------------------------------------------------------
// Module: x_ram
// Description: A Parameterized Synchronous Dual-Port RAM.
// This module allows for independent read and write operations on the same clock.
// -----------------------------------------------------------------------------

module x_ram #(
    parameter DW = 8,                // Data Width: Number of bits per memory word
    parameter AW = 8,                // Address Width: Defines depth (2^AW locations)
    parameter MEMFILE = ""           // Path to a hex file for pre-loading memory
)(
    input clk,                       // System Clock: All operations are synchronous to this
    
    // Port A: Read Interface
    input [AW-1:0] Read_Address,     // The address we want to read from
    input Read_Enable,               // Control signal: 1 = perform read, 0 = ignore
    output reg [DW-1:0] Read_Data, // The data retrieved (signed for arithmetic support)

    // Port B: Write Interface
    input [AW-1:0] Write_Address,    // The address where we want to store data
    input Write_Enable,              // Control signal: 1 = perform write, 0 = ignore
    input [DW-1:0] Write_Data        // The data to be stored
);

    // --- Memory Array Declaration ---
    // This creates an array of registers. 
    // Depth is calculated as 2^AW. (1 << 8 = 256)
    reg [DW-1:0] mem [0:(1<<AW)-1];

    // --- Memory Initialization ---
    // If a MEMFILE is provided, use $readmemh to load hex values into the array.
    // This happens once at the beginning of simulation/FPGA power-up.
    initial begin
        if (MEMFILE != "") begin
            $readmemh(MEMFILE, mem);
        end
    end

    // --- Synchronous Logic Block ---
    // Everything inside here happens on the rising edge of the clock.
    always @(posedge clk) begin
        
        // Write Operation:
        // If Write_Enable is high, the input data is "latched" into the memory array.
        if (Write_Enable) begin
            mem[Write_Address] <= Write_Data;
        end

        // Read Operation:
        // If Read_Enable is high, data is fetched from the array and sent to the output.
        // Note: Because this is inside the 'always' block, it takes one clock cycle 
        // for the data to actually appear on the Read_Data pins (Synchronous Read).
        if (Read_Enable) begin
            Read_Data <= mem[Read_Address];
        end
        
    end

endmodule

