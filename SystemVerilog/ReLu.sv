// =============================================================================
// Module: relu_activation
// Description: ReLU with shift=11 to match Python relu_shift=11.
//   data_out = clamp(data_in >> 11, 0, 255)
//   Extracts bits [18:11] from the 32-bit signed accumulator.
// =============================================================================
`timescale 1ns / 1ps

module relu_activation #(
    parameter IW = 32,
    parameter OW = 8
) (
    input  logic signed [IW-1:0] data_in,
    output logic        [OW-1:0] data_out
);
    wire is_negative = data_in[IW-1];
    // Overflow: any bit above bit 18 (excluding sign bit) is set
    wire overflow    = |data_in[IW-2:19];

    assign data_out = is_negative ? 8'd0    :
                      overflow    ? 8'd255  :
                                    data_in[18:11];
endmodule