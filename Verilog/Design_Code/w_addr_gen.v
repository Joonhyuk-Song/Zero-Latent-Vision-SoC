`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
//////////////////////////////////////////////
// -----------------------------------------------------------------------------
// Module: x_addr_gen
// Description: A sequential address generator with a "delayed start" mechanism.
// It increments the address on every 'pulse' after an initial arming phase.
// -----------------------------------------------------------------------------
module w_addr_gen #(
    parameter AW=8,
    parameter N=4,
    parameter OFFSET = 0

) (
    input clk,
    input rst,    // Synchronous reset, active high
    input pulse,  // Increment trigger
    output reg [AW-1:0] addr
);

    reg armed;    // Internal state to handle the first pulse delay

    always @(posedge clk) begin
        if (rst) begin
            // Reset the address to 0 and disarm the generator
            addr  <= OFFSET;
            armed <= 1'b0;
        end else if (pulse) begin
            // On the first pulse, just "arm" the counter (stays at addr 0)
            if (!armed) 
                armed <= 1'b1;
            // On every pulse AFTER the first one, increment the address
            else 
                addr <= addr + N;
        end
    end

endmodule
