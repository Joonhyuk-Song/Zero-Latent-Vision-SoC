`timescale 1ns / 1ps
module x_addr_gen #(parameter AW = 10, parameter N = 4) (
    input  logic            clk,
    input  logic            rst,
    input  logic            pulse,
    output logic [AW-1:0]  addr
);
    logic armed;
    always_ff @(posedge clk) begin
        if (rst) begin
            addr  <= '0;
            armed <= 1'b0;
        end else if (pulse) begin
            if (!armed) armed <= 1'b1;
            else        addr  <= addr + AW'(N);
        end
    end
endmodule