`timescale 1ns / 1ps
module hidden_layer #(
    parameter NUM_NEURONS        = 8,
    parameter WEIGHTS_PER_NEURON = 784,
    parameter N                  = 4,
    parameter W_MEMFILE          = "w.mem",
    parameter B_MEMFILE          = "b.mem",
    parameter W_offset           = 0,
    parameter B_offset           = 0
) (
    input  logic                           clk, RST,
    input  logic                           P1, P2, P3, P4, P5,
    input  logic [N*8-1:0]               x_in,
    output logic [(NUM_NEURONS*32)-1:0]  layer_out
);
    genvar i;
    generate
        for (i = 0; i < NUM_NEURONS; i++) begin : neuron_block
            hidden_neuron #(
                .NEURON_ID(i), .WEIGHTS_PER_NEURON(WEIGHTS_PER_NEURON),
                .N(N), .W_MEMFILE(W_MEMFILE), .B_MEMFILE(B_MEMFILE),
                .W_offset(W_offset), .B_offset(B_offset)
            ) n_inst (
                .clk(clk), .RST(RST),
                .P1(P1), .P2(P2), .P3(P3), .P4(P4), .P5(P5),
                .x_in(x_in), .Y(layer_out[i*32 +: 32])
            );
        end
    endgenerate
endmodule