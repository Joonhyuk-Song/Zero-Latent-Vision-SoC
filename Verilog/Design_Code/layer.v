module neural_layer #(
    parameter NUM_NEURONS = 5,
    parameter NUM_INPUTS = 24,
    parameter N = 4,
    parameter X_MEMFILE = "x.mem",
    parameter W_MEMFILE = "w.mem",
    parameter B_MEMFILE = "b.mem"
)(
    input clk, RST, P1, P2, P3, P4, P5,
    output [(NUM_NEURONS * 8) - 1 : 0] layer_out
);

    // 32-bit bus to capture raw sums from neurons
    wire signed [31:0] neuron_raw_sums [0:NUM_NEURONS-1];

    genvar i;
    generate
        for (i = 0; i < NUM_NEURONS; i = i + 1) begin : neuron_block
            // Neuron Instance
            neuron_top_parallel #(
                .NEURON_ID(i),
                .WEIGHTS_PER_NEURON(NUM_INPUTS),
                .N(N),
                .X_MEMFILE(X_MEMFILE),
                .W_MEMFILE(W_MEMFILE),
                .B_MEMFILE(B_MEMFILE)
            ) n_inst (
                .clk(clk), .RST(RST),
                .P1(P1), .P2(P2), .P3(P3), .P4(P4), .P5(P5),
                .Y(neuron_raw_sums[i]) 
            );

            // ReLU Activation (External to neuron, inside layer)
            relu_activation #(.IW(32), .OW(8)) RELU_INST (
                .data_in(neuron_raw_sums[i]),
                .data_out(layer_out[i*8 +: 8])
            );
        end
    endgenerate
endmodule