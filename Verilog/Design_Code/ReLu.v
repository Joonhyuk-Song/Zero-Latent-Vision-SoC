// -----------------------------------------------------------------------------
// Module: relu_activation
// Description: Implements f(x) = max(0, x) and outputs an 8-bit unsigned value.
// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------
// Module: relu_activation
// Description: Implements f(x) = max(0, min(255, x)) with a 7-bit fractional shift.
// -----------------------------------------------------------------------------
module relu_activation #(
    parameter IW = 32, // Input Width (from signed accumulator)
    parameter OW = 8   // Output Width (unsigned intensity)
)(
    input wire signed [IW-1:0] data_in,
    output wire [OW-1:0] data_out // Unsigned output
);

    // 1. Detect if the value is negative (MSB is 1)
    wire is_negative = data_in[IW-1];

    // 2. Detect if the integer part exceeds 8 bits (255)
    // We check all bits from the top of our 8-bit window (bit 14) 
    // up to the sign bit (bit 30).
    wire overflow = |data_in[IW-2:15]; 

    // 3. Combined Logic:
    // If negative -> 0
    // Else if overflow -> 255
    // Else -> bits [14:7]
    assign data_out = (is_negative) ? 8'd0 : 
                      (overflow)    ? 8'd255 : 
                                      data_in[14:7];

endmodule