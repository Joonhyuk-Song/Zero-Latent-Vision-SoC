`timescale 1ns / 1ps
module hidden_neuron #(
    parameter NEURON_ID          = 0,
    parameter WEIGHTS_PER_NEURON = 784,
    parameter N                  = 4,
    parameter W_MEMFILE          = "w.mem",
    parameter B_MEMFILE          = "b.mem",
    parameter AW                 = 15,
    parameter W_offset           = 0,
    parameter B_offset           = 0
) (
    input  logic                clk,
    input  logic                RST,
    input  logic                P1, P2, P3, P4, P5,
    input  logic [N*8-1:0]     x_in,
    output logic signed [31:0]  Y
);
    localparam int W_BASE = NEURON_ID * WEIGHTS_PER_NEURON + W_offset;
    localparam int B_BASE = NEURON_ID + B_offset;

    logic [AW-1:0] w_base_addr;
    w_addr_gen #(.AW(AW), .N(N), .OFFSET(W_BASE)) W_AG (
        .clk(clk), .rst(RST), .pulse(P1), .addr(w_base_addr)
    );

    logic [7:0] b_addr;
    b_addr_gen #(.AW(8), .OFFSET(B_BASE)) B_AG (
        .clk(clk), .pulse(P4), .addr(b_addr)
    );

    logic signed [N*8-1:0] w_data;
    w_rom #(.DW(8), .AW(AW), .N(N)) W_ROM_INST (
        .clk(clk), .Read_Address(w_base_addr),
        .Read_Enable(P2), .Read_Data(w_data)
    );

    logic signed [16:0] partial_products [0:N-1];
    genvar gi;
    generate
        for (gi = 0; gi < N; gi++) begin : gen_pe
            logic [7:0]        x_val;
            logic signed [7:0] w_val;
            assign x_val = x_in  [gi*8 +: 8];
            assign w_val = w_data[gi*8 +: 8];
            assign partial_products[gi] = $signed({1'b0, x_val}) * $signed(w_val);
        end
    endgenerate

    logic signed [31:0] sum_of_n;
    always_comb begin
        sum_of_n = '0;
        for (int j = 0; j < N; j++)
            sum_of_n += {{15{partial_products[j][16]}}, partial_products[j]};
    end

    logic signed [31:0] acc_out, acc_sum;
    combinational_adder #(.W(32)) ACC_ADD (.a(sum_of_n), .b(acc_out), .y(acc_sum));
    reg_bus #(.DW(32)) ACC_REG (.clk(clk), .Reset(RST), .Enable(P3), .Input(acc_sum), .Output(acc_out));

    logic signed [15:0] bias_val;
    b_rom #(.DW(16), .AW(8)) B_ROM_INST (
        .clk(clk), .Read_Address(b_addr),
        .Read_Enable(P4), .Read_Data(bias_val)
    );

    combinational_adder #(.W(32)) BIAS_ADD (
        .a({{16{bias_val[15]}}, bias_val}),
        .b(acc_out), .y(Y)
    );
endmodule