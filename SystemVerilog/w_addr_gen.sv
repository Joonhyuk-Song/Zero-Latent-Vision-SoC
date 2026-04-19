`timescale 1ns / 1ps
module w_addr_gen #(parameter AW = 15, parameter N = 4, parameter OFFSET = 0) (
    input  logic             clk,
    input  logic             rst,
    input  logic             pulse,
    output logic [AW-1:0]   addr
);
    logic armed;
    always_ff @(posedge clk) begin
        if (rst) begin
            addr  <= AW'(OFFSET);
            armed <= 1'b0;
        end else if (pulse) begin
            if (!armed) armed <= 1'b1;
            else        addr  <= addr + AW'(N);
        end
    end
endmodule