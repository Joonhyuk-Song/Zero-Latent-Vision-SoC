// =============================================================================
// CDS ADC Controller — Correlated Double Sampling Wrapper
// =============================================================================
// Description:
//   Wraps single_slope_adc to perform two conversions per pixel:
//     Phase 1 (CONV_RESET)  : ADC samples the pixel reset level → D_reset
//     Phase 2 (CONV_SIGNAL) : ADC samples the pixel signal level → D_signal
//     Phase 3 (SUBTRACT)    : pixel_out = saturate(D_signal - D_reset, 0)
//
//   Cancels: kTC reset noise, fixed-pattern offset, column-level offset.
//   Does not cancel: shot noise, ramp thermal noise.
//
//   Analog Specs (inherited from single_slope_adc):
//     VREF = 3.3V, 8-bit, LSB = ~12.89 mV
//
//   Timing:
//     Latency = D_reset_cycles + D_signal_cycles + 1 subtract cycle
//     Worst case = 256 + 256 + 1 = 513 cycles
//
// Interfaces:
//   Input  : clock           — system clock
//   Input  : reset           — synchronous active-high reset
//   Input  : start_cds       — pulse high 1 cycle to begin CDS conversion
//   Input  : comp_reset_in   — comparator output during RESET phase
//   Input  : comp_signal_in  — comparator output during SIGNAL phase
//   Output : ramp_reset      — to external ramp generator (from ADC)
//   Output : pixel_out[7:0]  — noise-reduced pixel value (D_signal - D_reset)
//   Output : cds_done        — 1-cycle pulse when pixel_out is valid
//   Output : busy            — high while conversion is in progress
// =============================================================================

module cds_adc #(
    parameter int VREF_MV   = 3300,
    parameter int RESOLUTION = 8
) (
    input  logic        clock,
    input  logic        reset,
    input  logic        start_cds,
    input  logic        comp_reset_in,   // Comparator fires at pixel reset level
    input  logic        comp_signal_in,  // Comparator fires at pixel signal level
    output logic        ramp_reset,
    output logic [7:0]  pixel_out,
    output logic        cds_done,
    output logic        busy
);

    // -------------------------------------------------------------------------
    // FSM State Encoding
    // -------------------------------------------------------------------------
    // 5-state FSM (one-hot)
    // IDLE -> CONV_RESET -> START_SIGNAL -> CONV_SIGNAL -> DONE -> IDLE
    //
    // The inner ADC's dout (result_reg) is REGISTERED — it becomes valid one
    // clock AFTER conv_done fires.  Two bridge cycles handle this:
    //
    //   START_SIGNAL : entered 1 cycle after reset-phase conv_done.
    //                  adc_dout is now stable with D_reset.
    //                  Latch d_reset here; pulse start_conv for signal phase.
    //
    //   DONE         : entered 1 cycle after signal-phase conv_done.
    //                  adc_dout is now stable with D_signal.
    //                  Compute pixel_out = adc_dout - d_reset; assert cds_done.
    typedef enum logic [4:0] {
        IDLE         = 5'b00001,
        CONV_RESET   = 5'b00010,
        START_SIGNAL = 5'b00100,
        CONV_SIGNAL  = 5'b01000,
        DONE         = 5'b10000
    } state_t;

    state_t state, next_state;

    // -------------------------------------------------------------------------
    // Internal Signals — ADC Interface
    // -------------------------------------------------------------------------
    logic        adc_start_conv;
    logic        adc_comparator_in;
    logic        adc_ramp_reset;
    logic [7:0]  adc_dout;
    logic        adc_conv_done;
    logic        adc_overflow;

    // -------------------------------------------------------------------------
    // Internal Registers
    // -------------------------------------------------------------------------
    logic [7:0]  d_reset;           // Latched reset-phase ADC result
    logic [7:0]  d_signal;          // Latched signal-phase ADC result
    logic        latch_reset;       // Pulse to capture d_reset
    logic        latch_signal;      // Pulse to capture d_signal
    logic        do_subtract;       // Pulse to trigger subtraction

    // -------------------------------------------------------------------------
    // Single-Slope ADC Instantiation
    // -------------------------------------------------------------------------
    single_slope_adc #(
        .VREF_MV   (VREF_MV),
        .RESOLUTION(RESOLUTION)
    ) u_adc (
        .clock        (clock),
        .reset        (reset),
        .start_conv   (adc_start_conv),
        .comparator_in(adc_comparator_in),
        .ramp_reset   (adc_ramp_reset),
        .dout         (adc_dout),
        .conv_done    (adc_conv_done),
        .overflow     (adc_overflow)
    );

    // Route ramp_reset to top-level output
    assign ramp_reset = adc_ramp_reset;

    // -------------------------------------------------------------------------
    // Comparator Mux — select reset or signal phase comparator
    // -------------------------------------------------------------------------
    always_comb begin
        case (state)
            CONV_RESET               : adc_comparator_in = comp_reset_in;
            START_SIGNAL,
            CONV_SIGNAL,
            DONE                     : adc_comparator_in = comp_signal_in;
            default                  : adc_comparator_in = 1'b0;
        endcase
    end

    // -------------------------------------------------------------------------
    // FSM — Sequential
    // -------------------------------------------------------------------------
    always_ff @(posedge clock) begin
        if (reset)
            state <= IDLE;
        else
            state <= next_state;
    end

    // -------------------------------------------------------------------------
    // FSM — Combinational
    // -------------------------------------------------------------------------
    always_comb begin
        next_state     = state;
        adc_start_conv = 1'b0;
        latch_reset    = 1'b0;
        latch_signal   = 1'b0;
        do_subtract    = 1'b0;
        busy           = 1'b1;
        cds_done       = 1'b0;

        unique case (state)
            // -----------------------------------------------------------------
            IDLE: begin
                busy = 1'b0;
                if (start_cds) begin
                    adc_start_conv = 1'b1;
                    next_state     = CONV_RESET;
                end
            end

            // -----------------------------------------------------------------
            // Phase 1: Wait for reset-phase conversion to complete.
            // adc_dout is NOT yet valid when conv_done fires (result_reg latches
            // on the same edge).  Transition to START_SIGNAL to let it settle.
            // -----------------------------------------------------------------
            CONV_RESET: begin
                if (adc_conv_done)
                    next_state = START_SIGNAL;
            end

            // -----------------------------------------------------------------
            // Bridge 1: adc_dout now holds D_reset (1 cycle after conv_done).
            // Latch d_reset and immediately start signal-phase conversion.
            // -----------------------------------------------------------------
            START_SIGNAL: begin
                latch_reset    = 1'b1;   // Capture stable D_reset
                adc_start_conv = 1'b1;   // ADC is in IDLE now — start signal phase
                next_state     = CONV_SIGNAL;
            end

            // -----------------------------------------------------------------
            // Phase 2: Wait for signal-phase conversion to complete.
            // Same registered-output issue: go to DONE to let adc_dout settle.
            // -----------------------------------------------------------------
            CONV_SIGNAL: begin
                if (adc_conv_done)
                    next_state = DONE;
            end

            // -----------------------------------------------------------------
            // Bridge 2 / Subtract: adc_dout now holds D_signal.
            // Compute pixel_out and assert cds_done for exactly 1 cycle.
            // -----------------------------------------------------------------
            DONE: begin
                latch_signal = 1'b1;
                do_subtract  = 1'b1;
                cds_done     = 1'b1;
                next_state   = IDLE;
            end

            default: next_state = IDLE;
        endcase
    end

    // -------------------------------------------------------------------------
    // D_reset and D_signal Registers
    // -------------------------------------------------------------------------
    always_ff @(posedge clock) begin
        if (reset) begin
            d_reset  <= 8'h00;
            d_signal <= 8'h00;
        end else begin
            if (latch_reset)  d_reset  <= adc_dout;
            if (latch_signal) d_signal <= adc_dout;
        end
    end

    // -------------------------------------------------------------------------
    // CDS Subtraction — saturating at zero (no negative pixel values)
    //   In DONE state, adc_dout is stable with D_signal.
    //   pixel_out = adc_dout - d_reset (clipped to 0 if adc_dout < d_reset)
    // -------------------------------------------------------------------------
    always_ff @(posedge clock) begin
        if (reset) begin
            pixel_out <= 8'h00;
        end else if (do_subtract) begin
            if (adc_dout >= d_reset)
                pixel_out <= adc_dout - d_reset;
            else
                pixel_out <= 8'h00;
        end
    end

endmodule
