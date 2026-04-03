`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
//////////////////////////////////////////////////////////////////////////////////
module w_rom #(
    parameter DW = 8,                // Data Width: Size of each data word (bits)
    parameter AW = 8,                // Address Width: Number of address bits
    parameter MEMFILE = ""           // Path to hex file containing the ROM data
)(
    input clk,                       // Clock: Read happens on the rising edge
    input [AW-1:0] Read_Address,     // The specific index to read from
    input Read_Enable,               // Control signal: 1 = perform read, 0 = hold output
    output reg signed [DW-1:0] Read_Data // Output data register
);

    // --- Memory Array ---
    // Declares an internal array to hold the ROM data.
    // The size is 2 to the power of AW (e.g., 2^8 = 256 words).
    reg [DW-1:0] mem [0:(1<<AW)-1];

    // --- ROM Initialization ---
    // Since there is no logic to write to this memory during runtime, 
    // the data MUST be loaded from an external file at startup.
    initial begin
        if (MEMFILE != "") begin
            $readmemh(MEMFILE, mem);
        end
    end

    // --- Synchronous Read Logic ---
    // This is a "registered read." When Read_Enable is high, the memory
    // content at Read_Address is transferred to the Read_Data register 
    // at the moment the clock ticks up.
    always @(posedge clk) begin
        if (Read_Enable) begin
            Read_Data <= mem[Read_Address];
        end
    end

endmodule