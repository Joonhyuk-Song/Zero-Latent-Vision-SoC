`timescale 1ns / 1ps

module FNN #(
    parameter L1_NEURONS  = 8,
    parameter L2_NEURONS  = 10,
    parameter L1_N        = 4,
    parameter L2_N        = 8,
    parameter L1_STEPS    = 784 / L1_N,
    parameter WAW         = 15
) (
    input  logic        clk,
    input  logic        RST,
    input  logic        start,
    input  logic [4:0]  soft_shift,
    output logic [3:0]  prediction,
    output logic        fnn_done,
    // x_ram external write port (driven by system_top during ADC phase)
    input  logic [9:0]  xram_wr_addr,
    input  logic        xram_wr_en,
    input  logic [7:0]  xram_wr_data
);
    typedef enum logic [3:0] {
        IDLE    = 4'd0, CALC_L1 = 4'd1, L1_BIAS = 4'd2,
        L1_RELU = 4'd3, CALC_L2 = 4'd4, L2_BIAS = 4'd5,
        SOFTMAX = 4'd6, DONE    = 4'd7
    } state_t;

    state_t state;
    logic l1_p1, l1_p2, l1_p3, l1_p4, l1_p5;
    logic l2_p1, l2_p2, l2_p3, l2_p4, l2_p5;
    logic soft_start, done_softmax;
    logic [7:0] step;
    logic [1:0] sub;

    logic [9:0]  x_rd_addr;
    logic        x_rd_en;
    logic [7:0]  xd0, xd1, xd2, xd3;

    x_ram #(.DW(8),.AW(10)) XRAM (
        .clk(clk), .Read_Address(x_rd_addr), .Read_Enable(x_rd_en),
        .Read_Data0(xd0), .Read_Data1(xd1), .Read_Data2(xd2), .Read_Data3(xd3),
        .Write_Address(xram_wr_addr), .Write_Enable(xram_wr_en), .Write_Data(xram_wr_data)
    );

    logic [31:0] x_in_l1;
    logic [(L1_NEURONS*32)-1:0] l1_raw;

    hidden_layer #(
        .NUM_NEURONS       (L1_NEURONS),
        .WEIGHTS_PER_NEURON(784),
        .N                 (L1_N),
        .W_MEMFILE         ("w.mem"),
        .B_MEMFILE         ("b.mem"),
        .W_offset          (0),
        .B_offset          (0)
    ) L1 (
        .clk(clk), .RST(RST),
        .P1(l1_p1), .P2(l1_p2), .P3(l1_p3), .P4(l1_p4), .P5(l1_p5),
        .x_in(x_in_l1), .layer_out(l1_raw)
    );

    logic [(L1_NEURONS*8)-1:0] l1_relu_out;
    genvar gi;
    generate
        for (gi = 0; gi < L1_NEURONS; gi++) begin : relu_blk
            relu_activation #(.IW(32),.OW(8)) RELU_INST (
                .data_in(l1_raw[gi*32 +: 32]),
                .data_out(l1_relu_out[gi*8 +: 8])
            );
        end
    endgenerate

    logic [(L2_NEURONS*32)-1:0] l2_raw;

    hidden_layer #(
        .NUM_NEURONS       (L2_NEURONS),
        .WEIGHTS_PER_NEURON(L1_NEURONS),
        .N                 (L2_N),
        .W_MEMFILE         ("w.mem"),
        .B_MEMFILE         ("b.mem"),
        .W_offset          (784 * L1_NEURONS),
        .B_offset          (L1_NEURONS)
    ) L2 (
        .clk(clk), .RST(RST),
        .P1(l2_p1), .P2(l2_p2), .P3(l2_p3), .P4(l2_p4), .P5(l2_p5),
        .x_in(l1_relu_out), .layer_out(l2_raw)
    );

    softmax SOFTMAX_INST (
        .clk(clk), .rst_n(~RST), .start(soft_start), .out_shift(soft_shift),
        .in0(l2_raw[0*32+:32]), .in1(l2_raw[1*32+:32]),
        .in2(l2_raw[2*32+:32]), .in3(l2_raw[3*32+:32]),
        .in4(l2_raw[4*32+:32]), .in5(l2_raw[5*32+:32]),
        .in6(l2_raw[6*32+:32]), .in7(l2_raw[7*32+:32]),
        .in8(l2_raw[8*32+:32]), .in9(l2_raw[9*32+:32]),
        .prediction(prediction), .done(done_softmax)
    );

    always_ff @(posedge clk or posedge RST) begin
        if (RST) begin
            state <= IDLE; step <= 8'd0; sub <= 2'd0;
            x_rd_addr <= 10'd0; x_rd_en <= 1'b0; x_in_l1 <= 32'd0;
            {l1_p1,l1_p2,l1_p3,l1_p4,l1_p5} <= 5'b0;
            {l2_p1,l2_p2,l2_p3,l2_p4,l2_p5} <= 5'b0;
            soft_start <= 1'b0; fnn_done <= 1'b0;
        end else begin
            {l1_p1,l1_p2,l1_p3,l1_p4,l1_p5} <= 5'b0;
            {l2_p1,l2_p2,l2_p3,l2_p4,l2_p5} <= 5'b0;
            soft_start <= 1'b0; x_rd_en <= 1'b0;

            case (state)
                IDLE: begin
                    fnn_done <= 1'b0; step <= 8'd0; sub <= 2'd0;
                    x_rd_addr <= 10'd0;
                    if (start) state <= CALC_L1;
                end

                CALC_L1: begin
                    case (sub)
                        2'd0: begin x_rd_en<=1'b1; l1_p1<=1'b1; sub<=2'd1; end
                        2'd1: begin l1_p2<=1'b1; sub<=2'd2; end
                        2'd2: begin
                            x_in_l1   <= {xd3,xd2,xd1,xd0};
                            x_rd_addr <= x_rd_addr + 10'd4;
                            sub <= 2'd3;
                        end
                        2'd3: begin
                            l1_p3 <= 1'b1; sub <= 2'd0;
                            if (step == 8'(L1_STEPS-1)) begin
                                step <= 8'd0; state <= L1_BIAS;
                            end else step <= step + 8'd1;
                        end
                        default: sub <= 2'd0;
                    endcase
                end

                L1_BIAS: begin
                    case (sub)
                        2'd0: begin l1_p4<=1'b1; sub<=2'd1; end
                        2'd1: begin l1_p5<=1'b1; sub<=2'd0; state<=L1_RELU; end
                        default: sub<=2'd0;
                    endcase
                end

                L1_RELU: begin state<=CALC_L2; step<=8'd0; sub<=2'd0; end

                CALC_L2: begin
                    case (sub)
                        2'd0: begin l2_p1<=1'b1; sub<=2'd1; end
                        2'd1: begin l2_p2<=1'b1; sub<=2'd2; end
                        2'd2: begin l2_p3<=1'b1; sub<=2'd0; state<=L2_BIAS; end
                        default: sub<=2'd0;
                    endcase
                end

                L2_BIAS: begin
                    case (sub)
                        2'd0: begin l2_p4<=1'b1; sub<=2'd1; end
                        2'd1: begin l2_p5<=1'b1; soft_start<=1'b1; sub<=2'd0; state<=SOFTMAX; end
                        default: sub<=2'd0;
                    endcase
                end

                SOFTMAX: begin
                    soft_start <= 1'b1;
                    if (done_softmax) begin
                        soft_start <= 1'b0;
                        state <= DONE;
                    end
                end

                DONE: begin
                    fnn_done<=1'b1;
                    if (!start) state<=IDLE;
                end

                default: state<=IDLE;
            endcase
        end
    end
endmodule