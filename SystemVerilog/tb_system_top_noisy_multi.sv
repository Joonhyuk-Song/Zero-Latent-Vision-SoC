// =============================================================================
// Testbench : tb_system_top_noisy_multi
// Purpose   : End-to-end 5-image inference test with 2 ms inter-frame gap.
//             Each frame loads a distinct noisy voltage file.
// Clock     : 100 MHz  |  Gap : 2 ms  |  Images : 0-4
// =============================================================================
module tb_system_top_noisy_multi;

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
    localparam longint INTER_GAP_NS   = 2_000_000;  // 2 ms
    localparam real    VOLT_MAX       = 3.3;
    localparam int     CYCLE_MAX      = 255;

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
        .clock           (clock         ),
        .reset           (reset         ),
        .start           (start         ),
        .comp_reset_in   (comp_reset_in ),
        .comp_signal_in  (comp_signal_in),
        .ramp_reset      (ramp_reset    ),
        .soft_shift      (soft_shift    ),
        .result_data     (result_data   ),
        .result_valid    (result_valid  ),
        .adc_stage_done  (adc_stage_done),
        .sram_write_done (sram_write_done),
        .sram_read_done  (sram_read_done),
        .npu_stage_done  (npu_stage_done)
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
    // Storage
    // =========================================================================
    integer pixel_voltages[0:ADC_PIXELS-1];
    integer ground_truth  [0:NUM_IMAGES-1];

    // =========================================================================
    // load_label_file  - parse "Image N (Label: X):" lines
    // =========================================================================
    task automatic load_label_file();
        integer fp, img_idx, lbl, ret;
        string  line;
        fp = $fopen("label.txt", "r");
        if (fp == 0) begin
            $display("LOG: %0t : INFO : tb_system_top_noisy_multi : label_open : label.txt not found, using image_data_pkg::LABELS fallback", $time);
            for (int i = 0; i < NUM_IMAGES; i++) begin
                ground_truth[i] = image_data_pkg::LABELS[i];
            end
            return;
        end
        img_idx = 0;
        for (int i = 0; i < NUM_IMAGES; i++) begin
            ground_truth[i] = -1;
        end
        while (!$feof(fp) && img_idx < NUM_IMAGES) begin
            ret = $fgets(line, fp);
            if (ret != 0) begin
                if ($sscanf(line, " Image %*d (Label: %d", lbl) == 1) begin
                    ground_truth[img_idx] = lbl;
                    img_idx = img_idx + 1;
                end
            end
        end
        $fclose(fp);
        $display("LOG: %0t : INFO : tb_system_top_noisy_multi : label_load : expected_value: %0d_labels actual_value: parsed_%0d",
                 $time, NUM_IMAGES, img_idx);
    endtask

    // =========================================================================
    // load_image_file  - float 0.0-3.3 V -> delay cycles 1-255
    //   Falls back to image_data_pkg constants when .mem file is unavailable.
    // =========================================================================
    task automatic load_image_file(input int img_num);
        integer fp, ret, raw;
        real    volt_f;
        string  fname;
        $sformat(fname, "image_%0d_voltage_noisy.mem", img_num);
        fp = $fopen(fname, "r");
        if (fp == 0) begin
            $display("LOG: %0t : INFO : tb_system_top_noisy_multi : file_open : file=%s not found, using image_data_pkg fallback",
                     $time, fname);
            // Package stores desired ADC output codes. CDS subtracts D_reset=RESET_COMP_DLY(16).
            // So set comp_signal delay = desired_code + RESET_COMP_DLY so pixel_out = desired_code.
            case (img_num)
                0: foreach (pixel_voltages[i]) pixel_voltages[i] = (image_data_pkg::IMAGE0[i] + RESET_COMP_DLY > CYCLE_MAX) ? CYCLE_MAX : image_data_pkg::IMAGE0[i] + RESET_COMP_DLY;
                1: foreach (pixel_voltages[i]) pixel_voltages[i] = (image_data_pkg::IMAGE1[i] + RESET_COMP_DLY > CYCLE_MAX) ? CYCLE_MAX : image_data_pkg::IMAGE1[i] + RESET_COMP_DLY;
                2: foreach (pixel_voltages[i]) pixel_voltages[i] = (image_data_pkg::IMAGE2[i] + RESET_COMP_DLY > CYCLE_MAX) ? CYCLE_MAX : image_data_pkg::IMAGE2[i] + RESET_COMP_DLY;
                3: foreach (pixel_voltages[i]) pixel_voltages[i] = (image_data_pkg::IMAGE3[i] + RESET_COMP_DLY > CYCLE_MAX) ? CYCLE_MAX : image_data_pkg::IMAGE3[i] + RESET_COMP_DLY;
                4: foreach (pixel_voltages[i]) pixel_voltages[i] = (image_data_pkg::IMAGE4[i] + RESET_COMP_DLY > CYCLE_MAX) ? CYCLE_MAX : image_data_pkg::IMAGE4[i] + RESET_COMP_DLY;
                default: foreach (pixel_voltages[i]) pixel_voltages[i] = RESET_COMP_DLY + 128;
            endcase
            return;
        end
        for (int i = 0; i < ADC_PIXELS; i++) begin
            ret = $fscanf(fp, "%f", volt_f);
            if (ret != 1) begin
                volt_f = 1.65;
            end
            raw = int'(volt_f / VOLT_MAX * real'(CYCLE_MAX)) + RESET_COMP_DLY;
            if (raw < RESET_COMP_DLY + 1) raw = RESET_COMP_DLY + 1;
            if (raw > CYCLE_MAX)          raw = CYCLE_MAX;
            pixel_voltages[i] = raw;
        end
        $fclose(fp);
        $display("LOG: %0t : INFO : tb_system_top_noisy_multi : file_load : expected_value: 784_pixels actual_value: loaded_%s",
                 $time, fname);
    endtask

    // =========================================================================
    // Pixel index tracker (mirrors xram_wr_addr)
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
    // Per-frame stats
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
                $display("LOG: %0t : ERROR : tb_system_top_noisy_multi : watchdog : expected_value: done actual_value: TIMEOUT", $time);
                $display("ERROR");
                $fatal(1, "Watchdog timeout after %0d cycles", TIMEOUT_CYCLES);
            end
        end else begin
            watchdog_count = 0;
        end
    end

    // =========================================================================
    // run_one_frame
    // =========================================================================
    task automatic run_one_frame(input int img_num, input int expected_label, output int errors_out);
        integer loc_errors;
        loc_errors = 0;

        $display("\n=== Image %0d / %0d (Label=%0d) @ %0t ns ===",
                 img_num, NUM_IMAGES, expected_label, $time);

        @(negedge clock); start = 1'b1;
        @(posedge clock); @(negedge clock); start = 1'b0;
        $display("LOG: %0t : INFO : tb_system_top_noisy_multi : dut.start : expected_value: 1 actual_value: 1", $time);

        @(posedge adc_stage_done); @(posedge clock);
        $display("LOG: %0t : INFO : tb_system_top_noisy_multi : dut.adc_stage_done : expected_value: 1 actual_value: 1", $time);

        if (pix_cnt != ADC_PIXELS) begin
            $display("LOG: %0t : ERROR : tb_system_top_noisy_multi : dut.xram_wr_en : expected_value: %0d actual_value: %0d",
                     $time, ADC_PIXELS, pix_cnt);
            loc_errors++;
        end else begin
            $display("LOG: %0t : INFO : tb_system_top_noisy_multi : dut.xram_wr_en : expected_value: %0d actual_value: %0d",
                     $time, ADC_PIXELS, pix_cnt);
        end

        @(posedge sram_write_done);
        $display("LOG: %0t : INFO : tb_system_top_noisy_multi : dut.sram_write_done : expected_value: 1 actual_value: 1", $time);
        @(posedge sram_read_done);
        $display("LOG: %0t : INFO : tb_system_top_noisy_multi : dut.sram_read_done : expected_value: 1 actual_value: 1", $time);

        @(posedge npu_stage_done); @(posedge clock);
        $display("LOG: %0t : INFO : tb_system_top_noisy_multi : dut.npu_stage_done : expected_value: 1 actual_value: 1", $time);

        if (rv_t == -1) begin
            $display("LOG: %0t : ERROR : tb_system_top_noisy_multi : dut.result_valid : expected_value: 1 actual_value: 0", $time);
            loc_errors++;
        end else begin
            $display("LOG: %0t : INFO : tb_system_top_noisy_multi : dut.result_valid : expected_value: 1 actual_value: 1", $time);
        end

        if (result_data > 4'd9) begin
            $display("LOG: %0t : ERROR : tb_system_top_noisy_multi : dut.result_data : expected_value: <=9 actual_value: %0d",
                     $time, result_data);
            loc_errors++;
        end

        if (expected_label >= 0) begin
            if (result_data == expected_label[3:0]) begin
                $display("LOG: %0t : INFO : tb_system_top_noisy_multi : dut.result_data : expected_value: %0d actual_value: %0d",
                         $time, expected_label, result_data);
            end else begin
                $display("LOG: %0t : ERROR : tb_system_top_noisy_multi : dut.result_data : expected_value: %0d actual_value: %0d",
                         $time, expected_label, result_data);
                loc_errors++;
            end
        end else begin
            $display("LOG: %0t : WARNING : tb_system_top_noisy_multi : label_compare : expected_value: N/A actual_value: %0d",
                     $time, result_data);
        end

        if (!(adc_t < swr_t)) begin
            $display("LOG: %0t : ERROR : tb_system_top_noisy_multi : pipeline_order : expected_value: adc_t<swr_t actual_value: FAIL", $time);
            loc_errors++;
        end
        if (!(swr_t < srd_t)) begin
            $display("LOG: %0t : ERROR : tb_system_top_noisy_multi : pipeline_order : expected_value: swr_t<srd_t actual_value: FAIL", $time);
            loc_errors++;
        end
        if (!(srd_t < npu_t)) begin
            $display("LOG: %0t : ERROR : tb_system_top_noisy_multi : pipeline_order : expected_value: srd_t<npu_t actual_value: FAIL", $time);
            loc_errors++;
        end

        $display("--- Image %0d Timing ---", img_num);
        $display("  ADC  done      : %0d ns", adc_t);
        $display("  SRAM write done: %0d ns", swr_t);
        $display("  SRAM read  done: %0d ns", srd_t);
        $display("  NPU  done      : %0d ns", npu_t);
        $display("  Prediction     : %0d  %s", result_data,
            (expected_label < 0) ? "(no label)" :
            (result_data == expected_label[3:0]) ? "CORRECT" : "WRONG");
        $display("  Pixel writes   : %0d / %0d", pix_cnt, ADC_PIXELS);

        errors_out = loc_errors;
    endtask

    // =========================================================================
    // Main
    // =========================================================================
    integer total_errors;
    integer frame_errors;
    integer correct_count;
    integer label_available;
    longint prev_end_t;
    longint gap_remaining;

    initial begin
        $display("TEST START");
        reset           = 1'b1;
        start           = 1'b0;
        soft_shift      = 5'd7;         // Calibrated: matches sv/tb_FNN.sv SOFT_SHIFT
        capture_en      = 1'b0;
        total_errors    = 0;
        correct_count   = 0;
        label_available = 0;

        load_label_file();

        repeat(RESET_CYCLES) @(posedge clock);
        @(negedge clock); reset = 1'b0;
        repeat(5) @(posedge clock);
        $display("LOG: %0t : INFO : tb_system_top_noisy_multi : dut.reset : expected_value: 0 actual_value: %0b", $time, reset);

        @(posedge clock);
        if (adc_stage_done | sram_write_done | sram_read_done | npu_stage_done) begin
            $display("LOG: %0t : ERROR : tb_system_top_noisy_multi : idle_check : expected_value: all_0 actual_value: stage_asserted", $time);
            total_errors++;
        end else begin
            $display("LOG: %0t : INFO : tb_system_top_noisy_multi : idle_check : expected_value: all_0 actual_value: all_0", $time);
        end

        prev_end_t = $time;

        for (int img = 0; img < NUM_IMAGES; img++) begin
            load_image_file(img);

            if (img > 0) begin
                gap_remaining = (prev_end_t + INTER_GAP_NS) - longint'($time);
                if (gap_remaining > 0) begin
                    $display("LOG: %0t : INFO : tb_system_top_noisy_multi : inter_frame_gap : expected_value: 2ms actual_value: waiting_%0d_ns",
                             $time, gap_remaining);
                    #(gap_remaining);
                end
                $display("LOG: %0t : INFO : tb_system_top_noisy_multi : inter_frame_gap : expected_value: 2ms actual_value: done", $time);
            end

            reset_frame_stats();
            capture_en  = 1'b1;
            watchdog_en = 1'b1;

            run_one_frame(img, ground_truth[img], frame_errors);

            prev_end_t = $time;

            if (ground_truth[img] >= 0) begin
                label_available++;
                if (result_data == ground_truth[img][3:0]) begin
                    correct_count++;
                end
            end

            total_errors += frame_errors;
            capture_en  = 1'b0;
            watchdog_en = 1'b0;
        end

        $display("\n=====================================================");
        $display("  5-Image Inference Summary");
        $display("  Clock       : 100 MHz");
        $display("  Inter-frame : 2 ms");
        $display("  Frames      : %0d", NUM_IMAGES);
        if (label_available > 0) begin
            $display("  Accuracy    : %0d / %0d  (%0d%%)",
                correct_count, label_available,
                (correct_count * 100) / label_available);
        end else begin
            $display("  Accuracy    : N/A");
        end
        $display("  Labels      : [5, 0, 4, 1, 9]");
        $display("=====================================================");

        if (total_errors == 0) begin
            $display("TEST PASSED");
        end else begin
            $display("ERROR: %0d check(s) failed", total_errors);
            $display("TEST FAILED");
            $error("Integration checks failed");
        end

        $finish;
    end

endmodule
