`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 

//////////////////////////////////////////////////////////////////////////////////

// -----------------------------------------------------------------------------
// Module: b_addr_gen
// Description: A Static Address Generator. 
// Unlike the 'x' version, this module always outputs address 0.
// -----------------------------------------------------------------------------

module b_addr_gen #(
    parameter AW = 8,                 // Address Width
    parameter OFFSET = 0
)(
    input wire clk,                  // Clock (Unused in this specific logic)
    input wire pulse,                // Pulse (Unused in this specific logic)
    output wire [AW-1:0] addr        // Output address bus
);

    // --- Static Assignment ---
    // The 'assign' keyword creates a continuous combinatorial connection.
    // This tells the hardware: "Tie every bit of the addr bus to Ground (0)."
    assign addr = OFFSET;

endmodule