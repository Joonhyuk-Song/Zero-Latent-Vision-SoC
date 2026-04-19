// =============================================================================
// Module  : control_unit
// Purpose : Moore FSM pipelined control unit for ADC → SRAM → NPU datapath.
//
//  Pipeline stages
//  ┌───────────┐   pipe_adc_done   ┌────────────┐   pipe_sram_done  ┌──────────┐
//  │  ADC FSM  │ ────────────────► │  SRAM FSM  │ ─────────────────► │  NPU FSM │
//  │ 28x28 cap │                   │ wr+rd map  │                    │ 4b result│
//  └───────────┘                   └────────────┘                    └──────────┘
//
//  While NPU processes frame N, SRAM stores frame N+1, ADC captures frame N+2.
//
//  Parameters
//  ----------
//  ADC_PIXELS    : total pixels per frame (default 28*28 = 784)
//  SRAM_WR_LAT   : cycles to write full feature map into SRAM
//  SRAM_RD_LAT   : cycles to read full feature map from SRAM
//  NPU_LATENCY   : cycles for NPU to generate 4-bit result
//
//  Moore FSM rule : all outputs are registered and depend solely on
//                   the current state register — never on inputs directly.
// =============================================================================

module control_unit #(
    parameter int ADC_PIXELS  = 784,   // 28 x 28
    parameter int SRAM_WR_LAT = 784,   // write latency (cycles)
    parameter int SRAM_RD_LAT = 784,   // read  latency (cycles)
    parameter int NPU_LATENCY = 100    // NPU processing latency (cycles)
)(
    input  logic clock,
    input  logic reset,

    // ── Start pulse ──────────────────────────────────────────────────────────
    input  logic start,             // pulse: begin a new capture / inference

    // ── ADC interface ────────────────────────────────────────────────────────
    input  logic adc_valid,         // ADC has a valid pixel on its output bus
    output logic adc_capture_en,    // (Moore) assert to clock ADC pixel in

    // ── SRAM interface ───────────────────────────────────────────────────────
    output logic sram_write_en,     // (Moore) write-enable to SRAM
    output logic sram_read_en,      // (Moore) read-enable from SRAM

    // ── NPU interface ────────────────────────────────────────────────────────
    output logic npu_start,         // (Moore) single-cycle kick to NPU
    input  logic npu_done_in,       // NPU asserts when 4-bit result is ready

    // ── Stage-done status (Moore outputs) ────────────────────────────────────
    output logic adc_stage_done,    // ADC captured full 28x28 frame
    output logic sram_write_done,   // SRAM finished writing feature map
    output logic sram_read_done,    // SRAM finished reading feature map
    output logic npu_stage_done,    // NPU finished processing
    output logic result_valid       // 4-bit result is available to downstream
);

    // =========================================================================
    // Local counter widths (clog2 helper avoids magic numbers)
    // =========================================================================
    localparam int ADC_CNT_W  = $clog2(ADC_PIXELS  + 1);
    localparam int SRAM_CNT_W = $clog2(SRAM_WR_LAT > SRAM_RD_LAT ?
                                        SRAM_WR_LAT + 1 : SRAM_RD_LAT + 1);
    localparam int NPU_CNT_W  = $clog2(NPU_LATENCY + 1);

    // =========================================================================
    // ADC stage FSM
    // =========================================================================
    typedef enum logic [1:0] {
        ADC_IDLE   = 2'b00,
        ADC_ACTIVE = 2'b01,
        ADC_DONE   = 2'b10
    } adc_state_t;

    adc_state_t          adc_state, adc_next;
    logic [ADC_CNT_W-1:0] adc_cnt;

    // ── ADC state register ───────────────────────────────────────────────────
    always_ff @(posedge clock or posedge reset) begin
        if (reset)
            adc_state <= ADC_IDLE;
        else
            adc_state <= adc_next;
    end

    // ── ADC pixel counter ────────────────────────────────────────────────────
    always_ff @(posedge clock or posedge reset) begin
        if (reset)
            adc_cnt <= '0;
        else if (adc_state == ADC_IDLE)
            adc_cnt <= '0;
        else if (adc_state == ADC_ACTIVE && adc_valid)
            adc_cnt <= adc_cnt + 1'b1;
    end

    // ── ADC next-state logic ─────────────────────────────────────────────────
    always_comb begin
        adc_next = adc_state;
        case (adc_state)
            ADC_IDLE:   if (start)                              adc_next = ADC_ACTIVE;
            ADC_ACTIVE: if (adc_cnt == ADC_CNT_W'(ADC_PIXELS - 1) && adc_valid)
                                                                adc_next = ADC_DONE;
            ADC_DONE:                                           adc_next = ADC_IDLE;
            default:                                            adc_next = ADC_IDLE;
        endcase
    end

    // ── ADC Moore outputs (registered) ──────────────────────────────────────
    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            adc_capture_en  <= 1'b0;
            adc_stage_done  <= 1'b0;
        end else begin
            adc_capture_en  <= (adc_next == ADC_ACTIVE);
            adc_stage_done  <= (adc_next == ADC_DONE);
        end
    end

    // ── Pipeline register: ADC → SRAM ────────────────────────────────────────
    // Captures the "ADC done" pulse so SRAM stage can start one cycle later.
    logic pipe_adc_to_sram;
    always_ff @(posedge clock or posedge reset) begin
        if (reset)
            pipe_adc_to_sram <= 1'b0;
        else
            pipe_adc_to_sram <= (adc_next == ADC_DONE);
    end

    // =========================================================================
    // SRAM stage FSM  (write phase followed by read phase)
    // =========================================================================
    typedef enum logic [2:0] {
        SRAM_IDLE     = 3'b000,
        SRAM_WRITE    = 3'b001,
        SRAM_WR_DONE  = 3'b010,
        SRAM_READ     = 3'b011,
        SRAM_RD_DONE  = 3'b100
    } sram_state_t;

    sram_state_t           sram_state, sram_next;
    logic [SRAM_CNT_W-1:0] sram_cnt;

    // ── SRAM state register ──────────────────────────────────────────────────
    always_ff @(posedge clock or posedge reset) begin
        if (reset)
            sram_state <= SRAM_IDLE;
        else
            sram_state <= sram_next;
    end

    // ── SRAM cycle counter ───────────────────────────────────────────────────
    always_ff @(posedge clock or posedge reset) begin
        if (reset)
            sram_cnt <= '0;
        else if (sram_state == SRAM_IDLE || sram_state == SRAM_WR_DONE)
            sram_cnt <= '0;
        else if (sram_state == SRAM_WRITE || sram_state == SRAM_READ)
            sram_cnt <= sram_cnt + 1'b1;
    end

    // ── SRAM next-state logic ────────────────────────────────────────────────
    always_comb begin
        sram_next = sram_state;
        case (sram_state)
            SRAM_IDLE:
                if (pipe_adc_to_sram)                           sram_next = SRAM_WRITE;

            SRAM_WRITE:
                if (sram_cnt == SRAM_CNT_W'(SRAM_WR_LAT - 1))  sram_next = SRAM_WR_DONE;

            SRAM_WR_DONE:                                       sram_next = SRAM_READ;

            SRAM_READ:
                if (sram_cnt == SRAM_CNT_W'(SRAM_RD_LAT - 1))  sram_next = SRAM_RD_DONE;

            SRAM_RD_DONE:                                       sram_next = SRAM_IDLE;

            default:                                            sram_next = SRAM_IDLE;
        endcase
    end

    // ── SRAM Moore outputs (registered) ─────────────────────────────────────
    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            sram_write_en   <= 1'b0;
            sram_read_en    <= 1'b0;
            sram_write_done <= 1'b0;
            sram_read_done  <= 1'b0;
        end else begin
            sram_write_en   <= (sram_next == SRAM_WRITE);
            sram_read_en    <= (sram_next == SRAM_READ);
            sram_write_done <= (sram_next == SRAM_WR_DONE);
            sram_read_done  <= (sram_next == SRAM_RD_DONE);
        end
    end

    // ── Pipeline register: SRAM → NPU ────────────────────────────────────────
    logic pipe_sram_to_npu;
    always_ff @(posedge clock or posedge reset) begin
        if (reset)
            pipe_sram_to_npu <= 1'b0;
        else
            pipe_sram_to_npu <= (sram_next == SRAM_RD_DONE);
    end

    // =========================================================================
    // NPU stage FSM
    // =========================================================================
    typedef enum logic [1:0] {
        NPU_IDLE   = 2'b00,
        NPU_START  = 2'b01,   // single-cycle kick state (generates npu_start)
        NPU_ACTIVE = 2'b10,
        NPU_DONE   = 2'b11
    } npu_state_t;

    npu_state_t           npu_state, npu_next;
    logic [NPU_CNT_W-1:0] npu_cnt;

    // ── NPU state register ───────────────────────────────────────────────────
    always_ff @(posedge clock or posedge reset) begin
        if (reset)
            npu_state <= NPU_IDLE;
        else
            npu_state <= npu_next;
    end

    // ── NPU cycle counter ────────────────────────────────────────────────────
    always_ff @(posedge clock or posedge reset) begin
        if (reset)
            npu_cnt <= '0;
        else if (npu_state != NPU_ACTIVE)
            npu_cnt <= '0;
        else
            npu_cnt <= npu_cnt + 1'b1;
    end

    // ── NPU next-state logic ─────────────────────────────────────────────────
    always_comb begin
        npu_next = npu_state;
        case (npu_state)
            NPU_IDLE:
                if (pipe_sram_to_npu)                           npu_next = NPU_START;

            NPU_START:                                          npu_next = NPU_ACTIVE;

            NPU_ACTIVE:
                // Accept either internal counter or external npu_done_in
                if (npu_done_in ||
                    npu_cnt == NPU_CNT_W'(NPU_LATENCY - 1))    npu_next = NPU_DONE;

            NPU_DONE:                                           npu_next = NPU_IDLE;

            default:                                            npu_next = NPU_IDLE;
        endcase
    end

    // ── NPU Moore outputs (registered) ──────────────────────────────────────
    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            npu_start      <= 1'b0;
            npu_stage_done <= 1'b0;
            result_valid   <= 1'b0;
        end else begin
            npu_start      <= (npu_next == NPU_START);
            npu_stage_done <= (npu_next == NPU_DONE);
            result_valid   <= (npu_next == NPU_DONE);
        end
    end

    // =========================================================================
    // Formal / simulation assertions (synthesizable guard with `ifdef)
    // =========================================================================
`ifdef SIMULATION
    // ADC must not start while already active
    property adc_no_double_start;
        @(posedge clock) disable iff (reset)
        (adc_state == ADC_ACTIVE) |-> !start;
    endproperty
    assert property (adc_no_double_start)
        else $warning("[control_unit] start pulsed while ADC already active");

    // Pipeline occupancy: SRAM should only be active after ADC completes
    property sram_after_adc;
        @(posedge clock) disable iff (reset)
        $rose(sram_write_en) |-> $past(adc_stage_done, 1);
    endproperty
    assert property (sram_after_adc)
        else $warning("[control_unit] SRAM write began without ADC done");

    // NPU should only start after SRAM read completes
    property npu_after_sram;
        @(posedge clock) disable iff (reset)
        $rose(npu_start) |-> $past(sram_read_done, 1);
    endproperty
    assert property (npu_after_sram)
        else $warning("[control_unit] NPU started without SRAM read done");
`endif

endmodule
