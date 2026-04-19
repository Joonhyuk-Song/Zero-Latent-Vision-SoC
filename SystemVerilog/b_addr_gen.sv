`timescale 1ns / 1ps
// Static bias address generator. Outputs constant OFFSET address.
module b_addr_gen #(parameter AW = 8, parameter OFFSET = 0) (
    input  logic            clk,
    input  logic            pulse,
    output logic [AW-1:0]  addr
);
    localparam [AW-1:0] ADDR_CONST = OFFSET;
    assign addr = ADDR_CONST;
endmodule