// =============================================================================
// Single-Slope 8-Bit ADC — Digital Control Logic
// =============================================================================
// Description:
//   Implements the digital control path for a single-slope (ramp) ADC.
//   An external analog ramp generator and comparator are required.
//
//   Analog Specifications:
//     Reference Voltage : VREF     = 3.3 V  (parameter VREF_MV = 3300)
//     Input Range       : 0 V  to  3.3 V
//     Resolution        : 8-bit (256 steps)
//     LSB Voltage       : 3300 mV / 256 = ~12.89 mV per LSB
//     Full-Scale Code   : 8'hFF = 3.287 V  (one LSB below VREF)
//
//   Operation:
//     1. On 'start_conv', the FSM resets the ramp generator (ramp_reset=1)
//        and clears the internal counter.
//     2. The ramp generator begins rising from 0V toward VREF (3.3V); the
//        8-bit counter increments each clock cycle (clock-gated for power savings).
//     3. When the ramp crosses Vin the external comparator asserts
//        'comparator_in'. The FSM immediately latches the counter and stops.
//     4. 'conv_done' pulses for one cycle; 'dout' holds the result.
//     5. If the counter overflows (>255) without a comparator trigger,
//        'overflow' is asserted and 'dout' is set to 8'hFF.
//
// Power Optimizations:
//   - Counter clock-gated: only active during CONVERT state
//   - Counter and ramp reset in IDLE to avoid glitches
//   - FSM returns to IDLE immediately after latching result
//
// Interfaces:
//   Input  : clock        — system clock
//   Input  : reset        — synchronous active-high reset
//   Input  : start_conv   — pulse high for one cycle to start conversion
//   Input  : comparator_in— from external analog comparator (Vramp >= Vin → 1)
//   Output : ramp_reset   — hold high to reset ramp generator to 0V
//   Output : dout[7:0]    — latched 8-bit conversion result
//   Output : conv_done    — one-cycle pulse when conversion completes
//   Output : overflow     — high when input exceeds full-scale (no comparator hit)
// =============================================================================

module single_slope_adc #(
    // -------------------------------------------------------------------------
    // Analog Reference Parameters
    // -------------------------------------------------------------------------
    parameter int VREF_MV      = 3300,   // Reference voltage in millivolts (3.3V)
    parameter int RESOLUTION   = 8,      // ADC resolution in bits
    // Derived: LSB size in microvolts = VREF_MV*1000 / 2^RESOLUTION
    // = 3300000 / 256 = 12890 uV (~12.89 mV per LSB) — for documentation only
    localparam int LSB_UV      = (VREF_MV * 1000) / (2 ** RESOLUTION)
) (
    input  logic        clock,
    input  logic        reset,
    input  logic        start_conv,
    input  logic        comparator_in,
    output logic        ramp_reset,
    output logic [7:0]  dout,
    output logic        conv_done,
    output logic        overflow
);

    // -------------------------------------------------------------------------
    // FSM State Encoding (one-hot for power efficiency)
    // -------------------------------------------------------------------------
    typedef enum logic [2:0] {
        IDLE        = 3'b001,
        RESET_RAMP  = 3'b010,
        CONVERT     = 3'b100
    } state_t;

    state_t state, next_state;

    // -------------------------------------------------------------------------
    // Internal Signals
    // -------------------------------------------------------------------------
    logic [7:0]  counter;           // Conversion counter
    logic        counter_en;        // Clock gate enable for counter
    logic        counter_clear;     // Synchronous clear for counter
    logic        counter_overflow;  // Counter wrapped past 8-bit max
    logic [7:0]  result_reg;        // Latched conversion result
    logic        latch_result;      // Pulse to capture counter into result_reg
    logic        set_overflow;      // Flag overflow condition

    // -------------------------------------------------------------------------
    // FSM — Sequential (State Register)
    // -------------------------------------------------------------------------
    always_ff @(posedge clock) begin
        if (reset)
            state <= IDLE;
        else
            state <= next_state;
    end

    // -------------------------------------------------------------------------
    // FSM — Combinational (Next State + Output Decode)
    // -------------------------------------------------------------------------
    always_comb begin
        // Defaults (safe, power-minimizing)
        next_state    = state;
        ramp_reset    = 1'b1;   // Keep ramp held low unless converting
        counter_en    = 1'b0;
        counter_clear = 1'b0;
        latch_result  = 1'b0;
        set_overflow  = 1'b0;
        conv_done     = 1'b0;

        unique case (state)
            // -----------------------------------------------------------------
            IDLE: begin
                ramp_reset    = 1'b1;   // Hold ramp generator in reset
                counter_clear = 1'b1;   // Keep counter at zero (low power)
                if (start_conv)
                    next_state = RESET_RAMP;
            end

            // -----------------------------------------------------------------
            // One-cycle ramp reset + counter clear before counting begins
            // -----------------------------------------------------------------
            RESET_RAMP: begin
                ramp_reset    = 1'b1;
                counter_clear = 1'b1;
                next_state    = CONVERT;
            end

            // -----------------------------------------------------------------
            // Active conversion: counter increments each cycle (clock gated)
            // Stop on comparator hit or overflow
            // -----------------------------------------------------------------
            CONVERT: begin
                ramp_reset = 1'b0;      // Release ramp — let it rise
                counter_en = 1'b1;      // Enable clock-gated counter

                if (comparator_in) begin
                    // Comparator fired — valid result
                    latch_result = 1'b1;
                    conv_done    = 1'b1;
                    next_state   = IDLE;
                end else if (counter_overflow) begin
                    // Input exceeded full scale
                    set_overflow = 1'b1;
                    conv_done    = 1'b1;
                    next_state   = IDLE;
                end
            end

            default: next_state = IDLE;
        endcase
    end

    // -------------------------------------------------------------------------
    // Clock-Gated 8-Bit Counter
    // Only increments when counter_en is asserted (CONVERT state)
    // -------------------------------------------------------------------------
    always_ff @(posedge clock) begin
        if (reset || counter_clear)
            counter <= 8'h00;
        else if (counter_en)
            counter <= counter + 8'h01;
    end

    // Overflow: counter has reached 8'hFF and is about to wrap
    assign counter_overflow = counter_en && (counter == 8'hFF);

    // -------------------------------------------------------------------------
    // Result Latch and Output Registers
    // -------------------------------------------------------------------------
    always_ff @(posedge clock) begin
        if (reset) begin
            result_reg <= 8'h00;
            overflow   <= 1'b0;
        end else if (latch_result) begin
            result_reg <= counter;
            overflow   <= 1'b0;
        end else if (set_overflow) begin
            result_reg <= 8'hFF;
            overflow   <= 1'b1;
        end
    end

    // Output is always the last latched result (stable between conversions)
    assign dout = result_reg;

endmodule
