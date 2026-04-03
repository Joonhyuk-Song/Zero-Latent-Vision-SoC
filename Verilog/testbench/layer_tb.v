`timescale 1ns / 1ps

module layer_tb();

    parameter NUM_NEURONS = 5;
    parameter NUM_INPUTS = 24;
    parameter N = 4;

    reg clk, RST, P1, P2, P3, P4, P5;
    wire [(NUM_NEURONS * 8) - 1 : 0] layer_out; 

    neural_layer #(
        .NUM_NEURONS(NUM_NEURONS),
        .NUM_INPUTS(NUM_INPUTS),
        .N(N)
    ) uut (
        .clk(clk), .RST(RST), .P1(P1), .P2(P2), .P3(P3), .P4(P4), .P5(P5),
        .layer_out(layer_out)
    );

    always #5 clk = ~clk;

// --- Monitoring Parallel Buses (Corrected Paths) ---
    genvar i;
    generate
        for (i = 0; i < NUM_NEURONS; i = i + 1) begin : monitor_gen
            integer k;
            always @(posedge clk) begin
                if (P2) begin
                    #1; // Wait for memory/mult logic to settle
                    $display("Time: %0t | Neuron [%0d] Parallel Bus:", $time, i);
                    for (k = 0; k < N; k = k + 1) begin
                        // Access the bus directly from the neuron instance, not the gen_pe block
                        $display("  [PE %0d] X: %d | W: %d | Prod: %d", 
                            k, 
                            uut.neuron_block[i].n_inst.x_bus[k], 
                            uut.neuron_block[i].n_inst.w_bus[k],
                            uut.neuron_block[i].n_inst.partial_products[k]);
                    end
                end
                
                if (P5) begin
                    #2;
                    $display("Time: %0t | Neuron [%0d] | Final ReLU Out: %d", 
                             $time, i, layer_out[i*8 +: 8]);
                end
            end
        end
    endgenerate
    
    initial begin
        clk = 0; RST = 0; P1 = 0; P2 = 0; P3 = 0; P4 = 0; P5 = 0;
        #10; RST = 1; #20; RST = 0;

        // MAC Loop adjusted for parallelism N
        repeat (NUM_INPUTS / N) begin
            @(negedge clk) P1 = 1; @(negedge clk) P1 = 0; // Addr
            @(negedge clk) P2 = 1; @(negedge clk) P2 = 0; // Read Bus
            @(negedge clk) P3 = 1; @(negedge clk) P3 = 0; // Accumulate
            repeat(1) @(negedge clk); 
        end

        #20; @(negedge clk) P4 = 1; @(negedge clk) P4 = 0; // Bias Addr
        #20; @(negedge clk) P5 = 1; @(negedge clk) P5 = 0; // Output
        #100; $finish;
    end
endmodule