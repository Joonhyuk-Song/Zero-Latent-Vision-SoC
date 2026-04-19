// =============================================================================
// Module  : system_top
// Purpose : Integration wrapper — connects control_unit, cds_adc, x_ram
//           (inside FNN), and FNN using their real port interfaces.
//
//  Data-flow
//  ─────────
//    cds_adc ──pixel_out[7:0]──► x_ram write port (inside FNN)
//    FNN reads x_ram internally via its own address generators
//    FNN ──prediction[3:0]─────► result_data output
//
//  Control-flow (orchestrated by control_unit Moore FSM)
//  ──────────────────────────────────────────────────────
//    start ──► control_unit ──adc_capture_en──► start_cds generator ──► cds_adc
//    cds_done (per pixel) ──► adc_valid ──► control_unit pixel counter
//    cds_done ──► Write_Enable + wr_addr counter ──► x_ram (inside FNN)
//    adc_stage_done (784 pixels) ──► (pipeline reg) ──► SRAM phase (1-cycle pass)
//    npu_start ──► FNN.start
//    fnn_done  ──► npu_done_in ──► control_unit NPU FSM
//
//  Notes on SRAM phase
//  ───────────────────
//  All 784 pixels are written to x_ram on every cds_done pulse during the ADC
//  phase, so x_ram is fully loaded before the NPU starts.  The SRAM stage in
//  control_unit acts as a guaranteed 1-cycle handshake gap (SRAM_WR_LAT=1,
//  SRAM_RD_LAT=1) before asserting npu_start.
//
//  start_cds generation
//  ────────────────────
//  cds_adc requires a single-cycle pulse on start_cds.  When adc_capture_en
//  is asserted by control_unit, we re-trigger start_cds whenever the ADC
//  returns to idle (busy == 0 and cds_done == 0).
// =============================================================================

module system_top #(
    parameter int ADC_PIXELS  = 784,  // 28 x 28
    parameter int NPU_LATENCY = 500   // generous timeout; fnn_done overrides this
)(
    input  logic        clock,
    input  logic        reset,

    // ── System control ───────────────────────────────────────────────────────
    input  logic        start,            // Pulse to begin capture + inference

    // ── CDS ADC analog interface (connect to pixel array comparators) ────────
    input  logic        comp_reset_in,    // Comparator output — reset  phase
    input  logic        comp_signal_in,   // Comparator output — signal phase
    output logic        ramp_reset,       // To external ramp generator

    // ── FNN softmax tuning ───────────────────────────────────────────────────
    input  logic [4:0]  soft_shift,       // Softmax fixed-point shift amount

    // ── Results ──────────────────────────────────────────────────────────────
    output logic [3:0]  result_data,      // 4-bit classification (digit 0-9)
    output logic        result_valid,     // 1-cycle pulse when result_data valid

    // ── Stage-done observability (for debug / status registers) ─────────────
    output logic        adc_stage_done,
    output logic        sram_write_done,
    output logic        sram_read_done,
    output logic        npu_stage_done
);

    // =========================================================================
    // Control-plane wires (control_unit ↔ sub-modules)
    // =========================================================================
    logic  adc_capture_en;    // control_unit → start_cds generator
    logic  adc_valid_w;       // cds_adc.cds_done → control_unit.adc_valid

    logic  sram_write_en;     // control_unit → (unused for gating; 1-cycle pass)
    logic  sram_read_en;      // control_unit → (unused for gating; 1-cycle pass)

    logic  npu_start_w;       // control_unit → FNN.start
    logic  npu_done_w;        // FNN.fnn_done → control_unit.npu_done_in

    // =========================================================================
    // ADC data-plane wires
    // =========================================================================
    logic [7:0]  pixel_out_w;    // cds_adc.pixel_out → frame_buf + filter
    logic        cds_busy_w;    // cds_adc.busy       (used by start_cds gen)

    // =========================================================================
    // start_cds generator
    // ─────────────────────
    // cds_adc.cds_done is a COMBINATIONAL output (asserted while FSM is in
    // DONE state, then FSM moves to IDLE on the next clock edge).
    // We must pulse start_cds AFTER cds_adc has reached IDLE — i.e., one
    // cycle after cds_done fires — to avoid a circular combinational path.
    //
    // adc_valid_d = cds_done registered by 1 cycle:
    //   Cycle N  : cds_adc in DONE  → cds_done=1,  adc_valid_d=0
    //   Cycle N+1: cds_adc in IDLE  → cds_done=0,  adc_valid_d=1 → start_cds=1
    //   Cycle N+2: cds_adc in CONV_RESET (new pixel started)
    // =========================================================================
    logic start_cds_w;
    logic adc_capture_en_d;   // 1-cycle delayed adc_capture_en
    logic adc_valid_d;        // 1-cycle delayed cds_done (breaks comb loop)

    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            adc_capture_en_d <= 1'b0;
            adc_valid_d      <= 1'b0;
        end else begin
            adc_capture_en_d <= adc_capture_en;
            adc_valid_d      <= adc_valid_w;    // registered cds_done
        end
    end

    // Pulse start_cds:
    //   (a) Rising edge of adc_capture_en → kick first conversion
    //   (b) One cycle after cds_done → cds_adc is now in IDLE, start next pixel
    assign start_cds_w = ( adc_capture_en & ~adc_capture_en_d)  // (a) first pixel
                       | ( adc_capture_en &  adc_valid_d       ); // (b) subsequent pixels

    // =========================================================================
    // x_ram write-address counter
    // Advances by 1 on every cds_done pulse during the ADC capture phase.
    // Resets to 0 whenever capture is not active.
    // =========================================================================
    logic [9:0] xram_wr_addr;

    always_ff @(posedge clock or posedge reset) begin
        if (reset)
            xram_wr_addr <= 10'd0;
        else if (!adc_capture_en)
            xram_wr_addr <= 10'd0;
        else if (adc_valid_w)                 // advance on each cds_done pulse
            xram_wr_addr <= xram_wr_addr + 10'd1;
    end

    // Write to x_ram on every cds_done pulse (adc_valid_w = cds_done)
    // pixel_out from cds_adc is valid for 1 cycle alongside cds_done
    logic xram_wr_en;
    assign xram_wr_en = adc_valid_w & adc_capture_en;

    // =========================================================================
    // control_unit instantiation
    // SRAM_WR_LAT=1 / SRAM_RD_LAT=1 → 1-cycle pass-through (x_ram already
    // loaded during ADC phase; no separate bulk-write phase needed).
    // =========================================================================
    control_unit #(
        .ADC_PIXELS  (ADC_PIXELS),
        .SRAM_WR_LAT (1        ),
        .SRAM_RD_LAT (1        ),
        .NPU_LATENCY (NPU_LATENCY)
    ) u_control_unit (
        .clock           (clock          ),
        .reset           (reset          ),
        .start           (start          ),

        // ADC handshake
        .adc_valid       (adc_valid_w    ),   // ← cds_done from cds_adc
        .adc_capture_en  (adc_capture_en ),   // → enables start_cds generator

        // SRAM handshake (1-cycle pass-through; x_ram loaded during ADC)
        .sram_write_en   (sram_write_en  ),
        .sram_read_en    (sram_read_en   ),

        // NPU handshake
        .npu_start       (npu_start_w    ),   // → FNN.start
        .npu_done_in     (npu_done_w     ),   // ← FNN.fnn_done

        // Stage-done observability
        .adc_stage_done  (adc_stage_done ),
        .sram_write_done (sram_write_done),
        .sram_read_done  (sram_read_done ),
        .npu_stage_done  (npu_stage_done ),
        .result_valid    (result_valid   )
    );

    // =========================================================================
    // cds_adc instantiation  (ADC stage)
    // =========================================================================
    cds_adc u_cds_adc (
        .clock         (clock         ),
        .reset         (reset         ),
        .start_cds     (start_cds_w   ),   // ← start_cds generator
        .comp_reset_in (comp_reset_in ),   // ← external comparator (reset phase)
        .comp_signal_in(comp_signal_in),   // ← external comparator (signal phase)
        .ramp_reset    (ramp_reset    ),   // → external ramp generator
        .pixel_out     (pixel_out_w   ),   // → x_ram Write_Data (inside FNN)
        .cds_done      (adc_valid_w   ),   // → control_unit.adc_valid + wr_en
        .busy          (cds_busy_w    )    // (unused by control_unit; for debug)
    );

    // =========================================================================
    // 3x3 Gaussian Spatial Filter + DSP pipeline
    //
    //  Stage 1 – Capture : raw CDS pixels in frame_buf[0:783] during ADC.
    //  Stage 2 – Filter  : 3x3 Gaussian [1 2 1; 2 4 2; 1 2 1]/16 per pixel
    //                      (edge-replicated borders).  Reduces Gaussian noise
    //                      variance by ~1/9 and quantization error by ~3x.
    //  Stage 3 – DSP     : noise gate (<=15->0) + rescale *291>>8 + 1.5x gain.
    //  Stage 4 – Write   : 784 filtered pixels written to XRAM (one per cycle).
    //  Stage 5 – FNN     : starts only after filter write-back completes.
    // =========================================================================

    // ---- frame_buf: raw CDS pixels captured during ADC phase -----------------
    logic [7:0] frame_buf [0:783];
    always_ff @(posedge clock) begin
        if (xram_wr_en) frame_buf[xram_wr_addr] <= pixel_out_w;
    end

    // ---- Filter FSM -----------------------------------------------------------
    typedef enum logic [1:0] { FILT_IDLE = 2'b00, FILT_RUN = 2'b01 } filt_state_t;
    filt_state_t filt_state;
    logic [4:0]  filt_row, filt_col;
    logic [9:0]  filt_row_base;
    logic        filter_done_r;

    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            filt_state    <= FILT_IDLE;
            filt_row      <= 5'd0;  filt_col      <= 5'd0;
            filt_row_base <= 10'd0; filter_done_r <= 1'b0;
        end else begin
            filter_done_r <= 1'b0;
            case (filt_state)
                FILT_IDLE: if (adc_stage_done) begin
                    filt_row <= 5'd0; filt_col <= 5'd0; filt_row_base <= 10'd0;
                    filt_state <= FILT_RUN;
                end
                FILT_RUN: begin
                    if (filt_col == 5'd27) begin
                        filt_col <= 5'd0;
                        if (filt_row == 5'd27) begin
                            filter_done_r <= 1'b1; filt_state <= FILT_IDLE;
                        end else begin
                            filt_row <= filt_row + 5'd1;
                            filt_row_base <= filt_row_base + 10'd28;
                        end
                    end else filt_col <= filt_col + 5'd1;
                end
                default: filt_state <= FILT_IDLE;
            endcase
        end
    end

    // ---- 3x3 neighbourhood (edge-replicated) ----------------------------------
    logic [9:0] rb_prev, rb_next;
    logic [4:0] c_prev, c_next;
    assign rb_prev = (filt_row == 5'd0)  ? filt_row_base : filt_row_base - 10'd28;
    assign rb_next = (filt_row == 5'd27) ? filt_row_base : filt_row_base + 10'd28;
    assign c_prev  = (filt_col == 5'd0)  ? 5'd0  : filt_col - 5'd1;
    assign c_next  = (filt_col == 5'd27) ? 5'd27 : filt_col + 5'd1;

    logic [7:0] fp00,fp01,fp02,fp10,fp11,fp12,fp20,fp21,fp22;
    assign fp00 = frame_buf[rb_prev       + {5'h0, c_prev  }];
    assign fp01 = frame_buf[rb_prev       + {5'h0, filt_col}];
    assign fp02 = frame_buf[rb_prev       + {5'h0, c_next  }];
    assign fp10 = frame_buf[filt_row_base + {5'h0, c_prev  }];
    assign fp11 = frame_buf[filt_row_base + {5'h0, filt_col}];
    assign fp12 = frame_buf[filt_row_base + {5'h0, c_next  }];
    assign fp20 = frame_buf[rb_next       + {5'h0, c_prev  }];
    assign fp21 = frame_buf[rb_next       + {5'h0, filt_col}];
    assign fp22 = frame_buf[rb_next       + {5'h0, c_next  }];

    // Kernel [1 2 1; 2 4 2; 1 2 1]/16  (max sum = 255*16 = 4080, needs 12 bits)
    logic [11:0] filt_sum;
    assign filt_sum =  {4'h0, fp00}
                    + {3'h0, fp01, 1'b0}
                    +  {4'h0, fp02}
                    + {3'h0, fp10, 1'b0}
                    + {2'h0, fp11, 2'b0}
                    + {3'h0, fp12, 1'b0}
                    +  {4'h0, fp20}
                    + {3'h0, fp21, 1'b0}
                    +  {4'h0, fp22};
    logic [7:0] gauss_out;
    assign gauss_out = filt_sum[11:4];   // divide by 16

    // ---- DSP on Gaussian output: noise gate + rescale + 1.5x gain ------------
    logic [7:0]  dsp_gated;
    logic [17:0] dsp_prod;
    logic [9:0]  dsp_shift;
    logic [7:0]  dsp_scaled;
    logic [8:0]  dsp_gained;
    logic [7:0]  filt_dsp_out;
    assign dsp_gated    = (gauss_out <= 8'd15) ? 8'h00 : gauss_out;
    assign dsp_prod     = {10'h0, dsp_gated} * 18'd291;
    assign dsp_shift    = dsp_prod[17:8];
    assign dsp_scaled   = (dsp_shift > 10'd255) ? 8'hFF : dsp_shift[7:0];
    assign dsp_gained   = {1'b0, dsp_scaled} + {2'b0, dsp_scaled[7:1]};
    assign filt_dsp_out = dsp_gained[8] ? 8'hFF : dsp_gained[7:0];

    // ---- Filter XRAM write signals --------------------------------------------
    logic [9:0] filt_wr_addr_w;
    logic       filt_wr_en_w;
    logic [7:0] filt_wr_data_w;
    assign filt_wr_en_w   = (filt_state == FILT_RUN);
    assign filt_wr_addr_w = filt_row_base + {5'h0, filt_col};
    assign filt_wr_data_w = filt_dsp_out;

    // ---- Gate FNN start until filter write-back completes --------------------
    logic npu_pending;
    always_ff @(posedge clock or posedge reset) begin
        if (reset)              npu_pending <= 1'b0;
        else if (npu_start_w)   npu_pending <= 1'b1;
        else if (filter_done_r) npu_pending <= 1'b0;
    end
    logic fnn_start_gated;
    assign fnn_start_gated = npu_pending & filter_done_r;

    // =========================================================================
    // FNN instantiation  (NPU stage)
    // x_ram written by filter FSM; FNN start gated by filter_done_r
    // =========================================================================
    FNN u_fnn (
        .clk          (clock           ),
        .RST          (reset           ),
        .start        (fnn_start_gated ),
        .soft_shift   (soft_shift      ),
        .prediction   (result_data     ),
        .fnn_done     (npu_done_w      ),
        .xram_wr_addr (filt_wr_addr_w  ),
        .xram_wr_en   (filt_wr_en_w    ),
        .xram_wr_data (filt_wr_data_w  )
    );

endmodule
