`timescale 1ns / 1ps

module neuron_top_parallel #(
    parameter NEURON_ID = 0,
    parameter WEIGHTS_PER_NEURON = 784,
    parameter N = 4, 
    parameter X_MEMFILE = "x.mem",
    parameter W_MEMFILE = "w.mem",
    parameter B_MEMFILE = "b.mem"
)(
    input clk,
    input RST,
    input P1, P2, P3, P4, P5,
    output signed [31:0] Y
);

    // --- 1. Address Generation ---
    localparam W_BASE_OFFSET = NEURON_ID * WEIGHTS_PER_NEURON;
    localparam B_BASE_OFFSET = NEURON_ID;

    wire [7:0] x_base_addr;
    wire [7:0] w_base_addr;
    wire [7:0] b_addr;

    x_addr_gen #(.AW(8),.N(N)) X_AG (.clk(clk), .rst(RST), .pulse(P1), .addr(x_base_addr));
    w_addr_gen #(.AW(8),.N(N), .OFFSET(W_BASE_OFFSET)) W_AG (.clk(clk), .rst(RST), .pulse(P1),.addr(w_base_addr));
    b_addr_gen #(.AW(8), .OFFSET(B_BASE_OFFSET)) B_AG (.clk(clk), .pulse(P4), .addr(b_addr));

    // --- 2. Parallel Processing Elements (PE) ---
    wire [7:0] x_bus [0:N-1];
    wire signed [7:0] w_bus [0:N-1];
    wire signed [31:0] partial_products [0:N-1];

    generate
        genvar i;
        for (i = 0; i < N; i = i + 1) begin : gen_pe
            x_ram #(.DW(8), .AW(8), .MEMFILE(X_MEMFILE)) X_INST (
                .clk(clk), 
                .Read_Address(x_base_addr + i), 
                .Read_Enable(P2), 
                .Read_Data(x_bus[i])
            );

            w_rom #(.DW(8), .AW(8), .MEMFILE(W_MEMFILE)) W_INST (
                .clk(clk), 
                .Read_Address(w_base_addr + i), 
                .Read_Enable(P2), 
                .Read_Data(w_bus[i])
            );

            combinational_multiplier #(16) MULT (
                .a({8'b0, x_bus[i]}),
                .b({{8{w_bus[i][7]}}, w_bus[i]}),
                .y(partial_products[i])
            );
        end
    endgenerate

    // --- 3. Adder Tree (Combinational Sum of N Products) ---
    reg signed [31:0] sum_of_n;
    integer j;
    always @(*) begin
        sum_of_n = 0;
        for (j = 0; j < N; j = j + 1) begin
            sum_of_n = sum_of_n + partial_products[j];
        end
    end

    // --- 4. Accumulation Stage (Sequential) ---
    wire signed [31:0] reg_output;
    wire [31:0] adder_acc_out;
    
    combinational_adder #(32) ACC_ADD (sum_of_n, reg_output, adder_acc_out);
    reg_bus #(32) ACC_REG (clk, RST, P3, adder_acc_out, reg_output);

    // --- 5. Bias Stage ---
    wire signed [15:0] bias_val;
    b_rom #(.DW(16), .AW(8), .MEMFILE(B_MEMFILE)) B_ROM_INST (
        .clk(clk), .Read_Address(b_addr), .Read_Enable(P5), .Read_Data(bias_val)
    );

    combinational_adder #(32) BIAS_ADD (
        {{16{bias_val[15]}}, bias_val}, 
        reg_output, 
        Y
    );
endmodule