// =============================================================================
// Testbench : tb_system_top_noisy
// Purpose   : End-to-end integration of system_top — 5-frame noisy-image test.
//
//  - Loads 784 pixel voltage codes (decimal, one per line) from
//    "image_n_noisy_voltage".  Values may be 8-bit codes (0-255) or mV
//    (0-3300); mV are converted automatically.
//  - Runs the same image 5 times with 10 ms inter-frame gaps (50 ms window).
//  - Comparator model: fires comp_reset_in at fixed 16-cy delay and
//    comp_signal_in at pixel_voltages[pixel_idx] delay after each
//    ramp_reset falling edge.  The CDS FSM mux picks the right comparator.
//  - Checks pixel-write count, pipeline ordering, and result validity.
//
//  Clock : 100 MHz (10 ns period)
//  Estimated latency per frame: ~1.31 ms  (ADC ~1.30 ms + NPU ~8.9 us)
// =============================================================================
`timescale 1ns/1ps

module tb_system_top_noisy;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam int     CLK_HALF       = 5;
    localparam int     RESET_CYCLES   = 20;
    localparam int     RESET_COMP_DLY = 16;
    localparam int     ADC_PIXELS     = 784;
    localparam int     NPU_LATENCY    = 2000;
    localparam int     NUM_IMAGES     = 5;
    localparam int     TIMEOUT_CYCLES = 600_000;
    localparam longint INTER_GAP_NS   = 10_000_000;

    // =========================================================================
    // DUT signals
    // =========================================================================
    logic        clock;
    logic        reset;
    logic        start;
    logic        comp_reset_in;
    logic        comp_signal_in;
    logic        ramp_reset;
    logic [4:0]  soft_shift;
    logic [3:0]  result_data;
    logic        result_valid;
    logic        adc_stage_done;
    logic        sram_write_done;
    logic        sram_read_done;
    logic        npu_stage_done;

    // =========================================================================
    // DUT
    // =========================================================================
    system_top #(
        .ADC_PIXELS (ADC_PIXELS),
        .NPU_LATENCY(NPU_LATENCY)
    ) dut (
        .clock          (clock         ),
        .reset          (reset         ),
        .start          (start         ),
        .comp_reset_in  (comp_reset_in ),
        .comp_signal_in (comp_signal_in),
        .ramp_reset     (ramp_reset    ),
        .soft_shift     (soft_shift    ),
        .result_data    (result_data   ),
        .result_valid   (result_valid  ),
        .adc_stage_done (adc_stage_done),
        .sram_write_done(sram_write_done),
        .sram_read_done (sram_read_done),
        .npu_stage_done (npu_stage_done)
    );

    // =========================================================================
    // Clock + waveform
    // =========================================================================
    initial clock = 1'b0;
    always #(CLK_HALF) clock = ~clock;

    initial begin
        $dumpfile("dumpfile.fst");
        $dumpvars(0);
    end

    // =========================================================================
    // Image pixel data
    // =========================================================================
    integer pixel_voltages[0:ADC_PIXELS-1];
    integer ground_truth[0:NUM_IMAGES-1];

    // =========================================================================
    // Ground-truth labels (from label.text)
    // =========================================================================
    task automatic load_label_file();
        integer fp, ret, lbl;
        fp = $fopen("label.text", "r");
        if (fp == 0) begin
            $display("LOG: %0t : WARNING : tb_system_top_noisy : label_open : expected_value: valid_fd actual_value: 0", $time);
            for (int i = 0; i < NUM_IMAGES; i++) begin
                ground_truth[i] = -1; // unknown
            end
        end else begin
            for (int i = 0; i < NUM_IMAGES; i++) begin
                ret = $fscanf(fp, "%d", lbl);
                if (ret != 1) begin
                    lbl = -1;
                end
                ground_truth[i] = lbl;
            end
            $fclose(fp);
            $display("LOG: %0t : INFO : tb_system_top_noisy : label_load : expected_value: %0d_labels actual_value: loaded_ok", $time, NUM_IMAGES);
        end
    endtask

    task automatic load_image_file();
        integer fp, ret, raw;
        fp = $fopen("image_n_noisy_voltage", "r");
        if (fp == 0) begin
            $display("LOG: %0t : WARNING : tb_system_top_noisy : file_open : expected_value: valid_fd actual_value: 0", $time);
            for (int i = 0; i < ADC_PIXELS; i++) begin
                pixel_voltages[i] = 128;
            end
        end else begin
            for (int i = 0; i < ADC_PIXELS; i++) begin
                ret = $fscanf(fp, "%d", raw);
                if (ret != 1) begin
                    raw = 128;
                end
                if (raw > 255) begin
                    raw = raw / 13;
                end
                if (raw < 1) begin
                    raw = 1;
                end
                if (raw > 255) begin
                    raw = 255;
                end
                pixel_voltages[i] = raw;
            end
            $fclose(fp);
            $display("LOG: %0t : INFO : tb_system_top_noisy : file_load : expected_value: 784_pixels actual_value: loaded_ok", $time);
        end
    endtask

    // =========================================================================
    // Pixel-index tracker (mirrors xram_wr_addr in system_top)
    // =========================================================================
    integer pixel_idx_cmp;

    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            pixel_idx_cmp <= 0;
        end else begin
            if (!dut.adc_capture_en) begin
                pixel_idx_cmp <= 0;
            end else if (dut.adc_valid_w) begin
                if (pixel_idx_cmp < ADC_PIXELS - 1) begin
                    pixel_idx_cmp <= pixel_idx_cmp + 1;
                end
            end
        end
    end

    // =========================================================================
    // Analog comparator model
    // =========================================================================
    logic ramp_reset_d;

    initial begin
        comp_reset_in  = 1'b0;
        comp_signal_in = 1'b0;
        ramp_reset_d   = 1'b1;
    end

    always_ff @(posedge clock) begin
        ramp_reset_d <= ramp_reset;
    end

    always @(posedge clock) begin
        if (ramp_reset_d && !ramp_reset) begin
            automatic integer cur_pix = pixel_idx_cmp;
            automatic integer sig_dly = pixel_voltages[cur_pix];
            fork
                begin
                    repeat(RESET_COMP_DLY) @(posedge clock);
                    comp_reset_in <= 1'b1;
                    @(posedge clock);
                    comp_reset_in <= 1'b0;
                end
            join_none
            fork
                begin
                    repeat(sig_dly) @(posedge clock);
                    comp_signal_in <= 1'b1;
                    @(posedge clock);
                    comp_signal_in <= 1'b0;
                end
            join_none
        end
    end

    // =========================================================================
    // Per-frame statistics
    // =========================================================================
    longint  adc_t, swr_t, srd_t, npu_t, rv_t;
    integer  pix_cnt;
    logic    capture_en;

    always @(negedge clock) begin
        if (dut.xram_wr_en) begin
            pix_cnt = pix_cnt + 1;
        end
    end

    task automatic reset_frame_stats();
        adc_t   = -1;
        swr_t   = -1;
        srd_t   = -1;
        npu_t   = -1;
        rv_t    = -1;
        pix_cnt = 0;
    endtask

    always @(posedge adc_stage_done)  begin if (capture_en && adc_t == -1) adc_t = $time; end
    always @(posedge sram_write_done) begin if (capture_en && swr_t == -1) swr_t = $time; end
    always @(posedge sram_read_done)  begin if (capture_en && srd_t == -1) srd_t = $time; end
    always @(posedge npu_stage_done)  begin if (capture_en && npu_t == -1) npu_t = $time; end
    always @(posedge result_valid)    begin if (capture_en && rv_t  == -1) rv_t  = $time; end

    // =========================================================================
    // Watchdog
    // =========================================================================
    integer watchdog_count;
    logic   watchdog_en;

    initial begin
        watchdog_en    = 1'b0;
        watchdog_count = 0;
    end

    always @(posedge clock) begin
        if (watchdog_en) begin
            watchdog_count = watchdog_count + 1;
            if (watchdog_count >= TIMEOUT_CYCLES) begin
                $display("LOG: %0t : ERROR : tb_system_top_noisy : watchdog : expected_value: done actual_value: TIMEOUT", $time);
                $display("ERROR");
                $fatal(1, "Watchdog timeout after %0d cycles", TIMEOUT_CYCLES);
            end
        end else begin
            watchdog_count = 0;
        end
    end

    // =========================================================================
    // Per-frame task
    // =========================================================================
    task automatic run_one_frame(input int img_num, input int expected_label, output int errors_out);
        integer loc_errors;
        loc_errors = 0;

        $display("");
        $display("=== Frame %0d / %0d : start @ %0t ns ===", img_num, NUM_IMAGES, $time);

        @(negedge clock); start = 1'b1;
        @(posedge clock); @(negedge clock); start = 1'b0;
        $display("LOG: %0t : INFO : tb_system_top_noisy : dut.start : expected_value: 1 actual_value: 1", $time);

        // Wait for ADC done
        @(posedge adc_stage_done);
        @(posedge clock);
        $display("LOG: %0t : INFO : tb_system_top_noisy : dut.adc_stage_done : expected_value: 1 actual_value: 1", $time);
        if (pix_cnt != ADC_PIXELS) begin
            $display("LOG: %0t : ERROR : tb_system_top_noisy : dut.xram_wr_en : expected_value: %0d actual_value: %0d", $time, ADC_PIXELS, pix_cnt);
            loc_errors = loc_errors + 1;
        end else begin
            $display("LOG: %0t : INFO : tb_system_top_noisy : dut.xram_wr_en : expected_value: %0d actual_value: %0d", $time, ADC_PIXELS, pix_cnt);
        end

        // Wait for SRAM done
        @(posedge sram_write_done);
        $display("LOG: %0t : INFO : tb_system_top_noisy : dut.sram_write_done : expected_value: 1 actual_value: 1", $time);
        @(posedge sram_read_done);
        $display("LOG: %0t : INFO : tb_system_top_noisy : dut.sram_read_done : expected_value: 1 actual_value: 1", $time);

        // Wait for NPU done
        @(posedge npu_stage_done);
        @(posedge clock);
        $display("LOG: %0t : INFO : tb_system_top_noisy : dut.npu_stage_done : expected_value: 1 actual_value: 1", $time);

        if (rv_t == -1) begin
            $display("LOG: %0t : ERROR : tb_system_top_noisy : dut.result_valid : expected_value: 1 actual_value: 0", $time);
            loc_errors = loc_errors + 1;
        end else begin
            $display("LOG: %0t : INFO : tb_system_top_noisy : dut.result_valid : expected_value: 1 actual_value: 1", $time);
        end

        if (result_data > 4'd9) begin
            $display("LOG: %0t : ERROR : tb_system_top_noisy : dut.result_data : expected_value: <=9 actual_value: %0d", $time, result_data);
            loc_errors = loc_errors + 1;
        end

        // Label comparison
        if (expected_label >= 0) begin
            if (result_data == expected_label[3:0]) begin
                $display("LOG: %0t : INFO : tb_system_top_noisy : dut.result_data : expected_value: %0d actual_value: %0d", $time, expected_label, result_data);
            end else begin
                $display("LOG: %0t : ERROR : tb_system_top_noisy : dut.result_data : expected_value: %0d actual_value: %0d", $time, expected_label, result_data);
                loc_errors = loc_errors + 1;
            end
        end else begin
            $display("LOG: %0t : WARNING : tb_system_top_noisy : label_compare : expected_value: N/A actual_value: %0d", $time, result_data);
        end

        // Pipeline ordering
        if (!(adc_t < swr_t)) begin
            $display("LOG: %0t : ERROR : tb_system_top_noisy : pipeline_order : expected_value: adc_t<swr_t actual_value: FAIL", $time);
            loc_errors = loc_errors + 1;
        end
        if (!(swr_t < srd_t)) begin
            $display("LOG: %0t : ERROR : tb_system_top_noisy : pipeline_order : expected_value: swr_t<srd_t actual_value: FAIL", $time);
            loc_errors = loc_errors + 1;
        end
        if (!(srd_t < npu_t)) begin
            $display("LOG: %0t : ERROR : tb_system_top_noisy : pipeline_order : expected_value: srd_t<npu_t actual_value: FAIL", $time);
            loc_errors = loc_errors + 1;
        end

        $display("--- Frame %0d Timing & Result ---", img_num);
        $display("  ADC  done      : %0d ns", adc_t);
        $display("  SRAM write done: %0d ns", swr_t);
        $display("  SRAM read  done: %0d ns", srd_t);
        $display("  NPU  done      : %0d ns", npu_t);
        if (expected_label >= 0) begin
            $display("  Expected label : %0d", expected_label);
        end
        $display("  Prediction     : %0d  %s", result_data,
            (expected_label < 0) ? "(no label)" :
            (result_data == expected_label[3:0]) ? "CORRECT" : "WRONG");
        $display("  Pixel writes   : %0d / %0d", pix_cnt, ADC_PIXELS);

        errors_out = loc_errors;
    endtask

    // =========================================================================
    // Main test
    // =========================================================================
    integer total_errors;
    integer frame_errors;
    integer correct_count;
    integer label_available;

    initial begin
        $display("TEST START");

        reset           = 1'b1;
        start           = 1'b0;
        soft_shift      = 5'd15;
        capture_en      = 1'b0;
        total_errors    = 0;
        correct_count   = 0;
        label_available = 0;

        load_image_file();
        load_label_file();

        repeat(RESET_CYCLES) @(posedge clock);
        @(negedge clock); reset = 1'b0;
        repeat(5) @(posedge clock);
        $display("LOG: %0t : INFO : tb_system_top_noisy : dut.reset : expected_value: 0 actual_value: %0b", $time, reset);

        @(posedge clock);
        if (adc_stage_done | sram_write_done | sram_read_done | npu_stage_done) begin
            $display("LOG: %0t : ERROR : tb_system_top_noisy : idle_check : expected_value: all_0 actual_value: stage_asserted", $time);
            total_errors = total_errors + 1;
        end else begin
            $display("LOG: %0t : INFO : tb_system_top_noisy : idle_check : expected_value: all_0 actual_value: all_0", $time);
        end

        // 5-image loop with 10 ms inter-frame gap
        for (int img = 1; img <= NUM_IMAGES; img++) begin
            reset_frame_stats();
            capture_en  = 1'b1;
            watchdog_en = 1'b1;

            run_one_frame(img, ground_truth[img-1], frame_errors);
            // Accuracy tracking
            if (ground_truth[img-1] >= 0) begin
                label_available = label_available + 1;
                if (result_data == ground_truth[img-1][3:0]) begin
                    correct_count = correct_count + 1;
                end
            end

            total_errors = total_errors + frame_errors;
            capture_en   = 1'b0;
            watchdog_en  = 1'b0;

            if (img < NUM_IMAGES) begin
                $display("LOG: %0t : INFO : tb_system_top_noisy : inter_frame_gap : expected_value: 10ms actual_value: waiting", $time);
                #(INTER_GAP_NS);
                $display("LOG: %0t : INFO : tb_system_top_noisy : inter_frame_gap : expected_value: 10ms actual_value: done", $time);
            end
        end

        $display("");
        $display("=====================================================");
        $display("  5-Image Inference Summary");
        $display("  Clock         : 100 MHz (10 ns period)");
        $display("  ADC pixels    : %0d (28x28, 8-bit CDS)", ADC_PIXELS);
        $display("  NPU arch      : FNN 784->8->10, 8-bit weights");
        $display("  Total frames  : %0d", NUM_IMAGES);
        $display("  Inter-frame   : 10 ms  (50 ms total window)");
        $display("  Est. latency  : ~1.31 ms / frame (ADC-dominated)");
        $display("  Est. throughp : ~769 fps  (limited by ADC stage)");
        if (label_available > 0) begin
            $display("  Accuracy      : %0d / %0d  (%0d%%)",
                correct_count, label_available,
                (correct_count * 100) / label_available);
        end else begin
            $display("  Accuracy      : N/A (label.text not found)");
        end
        $display("=====================================================");

        if (total_errors == 0) begin
            $display("TEST PASSED");
        end else begin
            $display("ERROR: %0d check(s) failed across all frames", total_errors);
            $display("TEST FAILED");
            $error("Integration checks failed");
        end

        $finish;
    end

endmodule
