`timescale 1ns / 1ps
// =============================================================================
// softmax: quantize ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ max-find ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ exp LUT ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ argmax  (12-cycle latency)
// =============================================================================
module softmax (
    input  logic              clk,
    input  logic              rst_n,
    input  logic              start,
    input  logic [4:0]        out_shift,
    input  logic signed [31:0] in0,in1,in2,in3,in4,
    input  logic signed [31:0] in5,in6,in7,in8,in9,
    output logic [3:0]         prediction,
    output logic               done
);
    function automatic logic signed [7:0] quantize(
        input logic signed [31:0] val, input logic [4:0] shift);
        logic signed [31:0] s;
        s = val >>> shift;
        if      (s > 32'sd127)  quantize = 8'sd127;
        else if (s < -32'sd128) quantize = -8'sd128;
        else                    quantize = s[7:0];
    endfunction

    logic signed [7:0] q [0:9];
    always_comb begin
        q[0]=quantize(in0,out_shift); q[1]=quantize(in1,out_shift);
        q[2]=quantize(in2,out_shift); q[3]=quantize(in3,out_shift);
        q[4]=quantize(in4,out_shift); q[5]=quantize(in5,out_shift);
        q[6]=quantize(in6,out_shift); q[7]=quantize(in7,out_shift);
        q[8]=quantize(in8,out_shift); q[9]=quantize(in9,out_shift);
    end

    logic signed [7:0] max_val;
    always_comb begin
        max_val = q[0];
        for (int m=1; m<10; m++) if (q[m]>max_val) max_val=q[m];
    end

    logic [3:0]        count;
    logic signed [7:0] current_q;
    logic [7:0]        max_prob_reg, rom_out, rom_addr;

    always_comb begin
        case (count)
            4'd0: current_q=q[0]; 4'd1: current_q=q[1]; 4'd2: current_q=q[2];
            4'd3: current_q=q[3]; 4'd4: current_q=q[4]; 4'd5: current_q=q[5];
            4'd6: current_q=q[6]; 4'd7: current_q=q[7]; 4'd8: current_q=q[8];
            4'd9: current_q=q[9]; default: current_q=q[0];
        endcase
    end
    assign rom_addr = 8'(max_val - current_q);

    exp_rom LUT (.addr(rom_addr),.data(rom_out));

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count<=4'd0; max_prob_reg<=8'h00; prediction<=4'd0; done<=1'b0;
        end else if (start) begin
            if (count < 4'd11) begin
                count <= count + 4'd1;
                if (count<=4'd9) begin
                    if (rom_out >= max_prob_reg) begin
                        max_prob_reg <= rom_out;
                        prediction   <= count;
                    end
                end
                done <= 1'b0;
            end else begin
                done <= 1'b1;
            end
        end else begin
            count<=4'd0; done<=1'b0; max_prob_reg<=8'h00;
        end
    end
endmodule

`timescale 1ns / 1ps
module exp_rom (
    input  logic [7:0] addr,
    output logic [7:0] data
);
    logic [7:0] rom [0:255];
    initial begin
        rom[0] = 8'hff;
        rom[1] = 8'hf0;
        rom[2] = 8'he1;
        rom[3] = 8'hd3;
        rom[4] = 8'hc7;
        rom[5] = 8'hbb;
        rom[6] = 8'haf;
        rom[7] = 8'ha5;
        rom[8] = 8'h9b;
        rom[9] = 8'h91;
        rom[10] = 8'h88;
        rom[11] = 8'h80;
        rom[12] = 8'h78;
        rom[13] = 8'h71;
        rom[14] = 8'h6a;
        rom[15] = 8'h64;
        rom[16] = 8'h5e;
        rom[17] = 8'h58;
        rom[18] = 8'h53;
        rom[19] = 8'h4e;
        rom[20] = 8'h49;
        rom[21] = 8'h45;
        rom[22] = 8'h40;
        rom[23] = 8'h3d;
        rom[24] = 8'h39;
        rom[25] = 8'h35;
        rom[26] = 8'h32;
        rom[27] = 8'h2f;
        rom[28] = 8'h2c;
        rom[29] = 8'h2a;
        rom[30] = 8'h27;
        rom[31] = 8'h25;
        rom[32] = 8'h23;
        rom[33] = 8'h20;
        rom[34] = 8'h1e;
        rom[35] = 8'h1d;
        rom[36] = 8'h1b;
        rom[37] = 8'h19;
        rom[38] = 8'h18;
        rom[39] = 8'h16;
        rom[40] = 8'h15;
        rom[41] = 8'h14;
        rom[42] = 8'h12;
        rom[43] = 8'h11;
        rom[44] = 8'h10;
        rom[45] = 8'h0f;
        rom[46] = 8'h0e;
        rom[47] = 8'h0e;
        rom[48] = 8'h0d;
        rom[49] = 8'h0c;
        rom[50] = 8'h0b;
        rom[51] = 8'h0b;
        rom[52] = 8'h0a;
        rom[53] = 8'h09;
        rom[54] = 8'h09;
        rom[55] = 8'h08;
        rom[56] = 8'h08;
        rom[57] = 8'h07;
        rom[58] = 8'h07;
        rom[59] = 8'h06;
        rom[60] = 8'h06;
        rom[61] = 8'h06;
        rom[62] = 8'h05;
        rom[63] = 8'h05;
        rom[64] = 8'h05;
        rom[65] = 8'h04;
        rom[66] = 8'h04;
        rom[67] = 8'h04;
        rom[68] = 8'h04;
        rom[69] = 8'h03;
        rom[70] = 8'h03;
        rom[71] = 8'h03;
        rom[72] = 8'h03;
        rom[73] = 8'h03;
        rom[74] = 8'h02;
        rom[75] = 8'h02;
        rom[76] = 8'h02;
        rom[77] = 8'h02;
        rom[78] = 8'h02;
        rom[79] = 8'h02;
        rom[80] = 8'h02;
        rom[81] = 8'h02;
        rom[82] = 8'h02;
        rom[83] = 8'h01;
        rom[84] = 8'h01;
        rom[85] = 8'h01;
        rom[86] = 8'h01;
        rom[87] = 8'h01;
        rom[88] = 8'h01;
        rom[89] = 8'h01;
        rom[90] = 8'h01;
        rom[91] = 8'h01;
        rom[92] = 8'h01;
        rom[93] = 8'h01;
        rom[94] = 8'h01;
        rom[95] = 8'h01;
        rom[96] = 8'h01;
        rom[97] = 8'h01;
        rom[98] = 8'h01;
        rom[99] = 8'h01;
        rom[100] = 8'h00;
        rom[101] = 8'h00;
        rom[102] = 8'h00;
        rom[103] = 8'h00;
        rom[104] = 8'h00;
        rom[105] = 8'h00;
        rom[106] = 8'h00;
        rom[107] = 8'h00;
        rom[108] = 8'h00;
        rom[109] = 8'h00;
        rom[110] = 8'h00;
        rom[111] = 8'h00;
        rom[112] = 8'h00;
        rom[113] = 8'h00;
        rom[114] = 8'h00;
        rom[115] = 8'h00;
        rom[116] = 8'h00;
        rom[117] = 8'h00;
        rom[118] = 8'h00;
        rom[119] = 8'h00;
        rom[120] = 8'h00;
        rom[121] = 8'h00;
        rom[122] = 8'h00;
        rom[123] = 8'h00;
        rom[124] = 8'h00;
        rom[125] = 8'h00;
        rom[126] = 8'h00;
        rom[127] = 8'h00;
        rom[128] = 8'h00;
        rom[129] = 8'h00;
        rom[130] = 8'h00;
        rom[131] = 8'h00;
        rom[132] = 8'h00;
        rom[133] = 8'h00;
        rom[134] = 8'h00;
        rom[135] = 8'h00;
        rom[136] = 8'h00;
        rom[137] = 8'h00;
        rom[138] = 8'h00;
        rom[139] = 8'h00;
        rom[140] = 8'h00;
        rom[141] = 8'h00;
        rom[142] = 8'h00;
        rom[143] = 8'h00;
        rom[144] = 8'h00;
        rom[145] = 8'h00;
        rom[146] = 8'h00;
        rom[147] = 8'h00;
        rom[148] = 8'h00;
        rom[149] = 8'h00;
        rom[150] = 8'h00;
        rom[151] = 8'h00;
        rom[152] = 8'h00;
        rom[153] = 8'h00;
        rom[154] = 8'h00;
        rom[155] = 8'h00;
        rom[156] = 8'h00;
        rom[157] = 8'h00;
        rom[158] = 8'h00;
        rom[159] = 8'h00;
        rom[160] = 8'h00;
        rom[161] = 8'h00;
        rom[162] = 8'h00;
        rom[163] = 8'h00;
        rom[164] = 8'h00;
        rom[165] = 8'h00;
        rom[166] = 8'h00;
        rom[167] = 8'h00;
        rom[168] = 8'h00;
        rom[169] = 8'h00;
        rom[170] = 8'h00;
        rom[171] = 8'h00;
        rom[172] = 8'h00;
        rom[173] = 8'h00;
        rom[174] = 8'h00;
        rom[175] = 8'h00;
        rom[176] = 8'h00;
        rom[177] = 8'h00;
        rom[178] = 8'h00;
        rom[179] = 8'h00;
        rom[180] = 8'h00;
        rom[181] = 8'h00;
        rom[182] = 8'h00;
        rom[183] = 8'h00;
        rom[184] = 8'h00;
        rom[185] = 8'h00;
        rom[186] = 8'h00;
        rom[187] = 8'h00;
        rom[188] = 8'h00;
        rom[189] = 8'h00;
        rom[190] = 8'h00;
        rom[191] = 8'h00;
        rom[192] = 8'h00;
        rom[193] = 8'h00;
        rom[194] = 8'h00;
        rom[195] = 8'h00;
        rom[196] = 8'h00;
        rom[197] = 8'h00;
        rom[198] = 8'h00;
        rom[199] = 8'h00;
        rom[200] = 8'h00;
        rom[201] = 8'h00;
        rom[202] = 8'h00;
        rom[203] = 8'h00;
        rom[204] = 8'h00;
        rom[205] = 8'h00;
        rom[206] = 8'h00;
        rom[207] = 8'h00;
        rom[208] = 8'h00;
        rom[209] = 8'h00;
        rom[210] = 8'h00;
        rom[211] = 8'h00;
        rom[212] = 8'h00;
        rom[213] = 8'h00;
        rom[214] = 8'h00;
        rom[215] = 8'h00;
        rom[216] = 8'h00;
        rom[217] = 8'h00;
        rom[218] = 8'h00;
        rom[219] = 8'h00;
        rom[220] = 8'h00;
        rom[221] = 8'h00;
        rom[222] = 8'h00;
        rom[223] = 8'h00;
        rom[224] = 8'h00;
        rom[225] = 8'h00;
        rom[226] = 8'h00;
        rom[227] = 8'h00;
        rom[228] = 8'h00;
        rom[229] = 8'h00;
        rom[230] = 8'h00;
        rom[231] = 8'h00;
        rom[232] = 8'h00;
        rom[233] = 8'h00;
        rom[234] = 8'h00;
        rom[235] = 8'h00;
        rom[236] = 8'h00;
        rom[237] = 8'h00;
        rom[238] = 8'h00;
        rom[239] = 8'h00;
        rom[240] = 8'h00;
        rom[241] = 8'h00;
        rom[242] = 8'h00;
        rom[243] = 8'h00;
        rom[244] = 8'h00;
        rom[245] = 8'h00;
        rom[246] = 8'h00;
        rom[247] = 8'h00;
        rom[248] = 8'h00;
        rom[249] = 8'h00;
        rom[250] = 8'h00;
        rom[251] = 8'h00;
        rom[252] = 8'h00;
        rom[253] = 8'h00;
        rom[254] = 8'h00;
        rom[255] = 8'h00;
    end
    assign data = rom[addr];
endmodule
