`timescale 1ns / 1ps

module neuron_tb();

    // --- Inputs to UUT ---
    reg clk;
    reg RST;
    reg P1, P2, P3, P4, P5;

    // --- Output from UUT ---
    wire [7:0] Y; 

    // --- 1. Instantiate Unit Under Test (UUT) ---
    neuron_top #(
        .X_MEMFILE("x.mem"),
        .W_MEMFILE("w.mem"),
        .B_MEMFILE("b.mem")
    ) uut (
        .clk(clk), .RST(RST), 
        .P1(P1), .P2(P2), .P3(P3), .P4(P4), .P5(P5), 
        .Y(Y)
    );

    // --- 2. Clock Generation ---
    always #5 clk = ~clk;

    // --- 3. Troubleshooting Display Block (FIXED WITH $STROBE) ---
    always @(posedge clk) begin
        // Use $strobe to ensure we see the values AFTER the clock edge update
        if (P3) begin
            $strobe("Time: %0t | [MULTIPLY] X*W: %d | [ACCUM] Prev: %d | New Sum: %d", 
                    $time, uut.x_times_w_term, uut.reg_output, uut.adder0_output);
        end
        
        if (P5) begin
            // $strobe is critical here because bias is read synchronously from b_rom
            $strobe("Time: %0t | [FINAL] Acc Total: %d | Bias: %d | Final Sum: %d", 
                    $time, uut.reg_output, uut.bias, uut.sum_with_bias);
            $strobe("Time: %0t | [OUTPUT] ReLU Activated 8-bit Y: %d", $time, Y);
        end
    end

    // --- 4. Stimulus Process ---
    initial begin
        // Initialize Signals
        clk = 0; RST = 0;
        P1 = 0; P2 = 0; P3 = 0; P4 = 0; P5 = 0;

        // Step 1: Global Reset
        #10 RST = 1;
        #20 RST = 0; 
        #10;

        $display("--- Starting 4-Input Dot Product Phase ---");
        
        // Step 2: Perform 4 Dot-Product Iterations
        repeat (4) begin
            #10 P1 = 1; #10 P1 = 0; // Trigger Address Gen
            #10 P2 = 1; #10 P2 = 0; // Trigger Memory Read
            #10 P3 = 1; #10 P3 = 0; // Trigger Accumulate
            #10;
        end

        // Step 3: Final Stage - Add Bias
        $display("--- Starting Bias and Activation Phase ---");
        #10 P4 = 1; #10 P4 = 0; // Trigger Static Bias Address 0
        #10 P5 = 1;             // Assert Read Enable
        
        // We hold P5 high for one full cycle to ensure the rising edge clocks the ROM
        #10; 
        P5 = 0;                 // De-assert after the edge has occurred
        
        #20;                    // Wait for combinational logic (Adder/ReLU) to settle
        $display("Final Result Captured at Time: %0t", $time);

        #100;
        $display("Test Complete.");
        $finish;
    end

endmodule