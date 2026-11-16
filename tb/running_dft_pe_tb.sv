`timescale 1ns/1ps
// Single PE test: sample_fifo + complex_subtractor + running_dft_pe
// compared with an ideal floating point sliding DFT (bin k = 1, N = 16).
// No refresh in the first part, so the error drift shows up.
// At sample CLEAR_AT the PE is cleared once, to test the warm up mask.
//
// run this from the reference folder (the hex file is read from the current dir)
module running_dft_pe_tb;

    parameter N       = 16;
    parameter W       = 22;
    parameter NS      = 4096;     // samples to run
    parameter PERIOD  = 24;       // clocks per sample (> CORDIC latency of 17)
    parameter CLEAR_AT = 3000;
    parameter FRAC    = 19;       // internal Q3.19
    parameter ITER    = 16;
    parameter THETA   = 411775;   // 2*pi/16 * 2^20

    reg clk = 0;
    reg rst_n = 0;
    reg sample_en = 0;
    reg clear = 0;
    reg signed [15:0] s_in;
    wire signed [15:0] old_re, old_im;
    wire signed [W-1:0] ds_re, ds_im;
    wire signed [W-1:0] f_re, f_im;
    wire done, valid;
    wire signed [23:0] theta_w = THETA;

    // sign extend and shift left by 4 (guard bits)
    wire signed [W-1:0] s_g_re = {{(W-16){s_in[15]}}, s_in} <<< 4;
    wire signed [W-1:0] s_g_im = 0;

    sample_fifo #(.N(N), .W(16)) fifo (
        .clk(clk), .rst_n(rst_n), .shift_en(sample_en),
        .din_re(s_in), .din_im(16'sd0), .dout_re(old_re), .dout_im(old_im));

    complex_subtractor #(.IN_W(16), .OUT_W(W), .GUARD_LSB(4)) sub (
        .a_re(s_in), .a_im(16'sd0), .b_re(old_re), .b_im(old_im),
        .d_re(ds_re), .d_im(ds_im));

    running_dft_pe #(.W(W), .N(N), .ITER(ITER)) dut (
        .clk(clk), .rst_n(rst_n), .clear(clear), .sample_en(sample_en),
        .ds_re(ds_re), .ds_im(ds_im), .s_re(s_g_re), .s_im(s_g_im),
        .theta(theta_w), .f_re(f_re), .f_im(f_im), .done(done), .valid(valid));

    always #5 clk = ~clk;

    reg signed [15:0] mem [0:2047];
    integer r, c, fd, errors;
    real th, cth, sth;
    real sr, so, fr_re, fr_im, t_re, t_im;
    real pe_re, pe_im, err, mag;
    real max_early, err_before, max_after, max_all, scale;

    initial begin
        $readmemh("input_re.hex", mem);
        th  = 6.28318530717959 / N;       // ideal angle
        cth = $cos(th);
        sth = $sin(th);
        scale = 2.0 ** FRAC;
        fr_re = 0; fr_im = 0;
        errors = 0;
        max_early = 0; max_after = 0; max_all = 0; err_before = 0;
        fd = $fopen("pe_error.csv", "w");
        $fwrite(fd, "r,err,mag\n");

        #22 rst_n = 1;

        for (r = 0; r < NS; r = r + 1) begin
            // refresh the PE once, between two samples
            if (r == CLEAR_AT) begin
                @(negedge clk); clear = 1;
                @(negedge clk); clear = 0;
            end

            // one sample
            @(negedge clk);
            s_in = mem[r % 2048];          // signal period is 16, so wrapping is seamless
            sample_en = 1;
            @(negedge clk);
            sample_en = 0;
            for (c = 2; c < PERIOD; c = c + 1) @(negedge clk);

            // ideal sliding DFT
            sr = s_in / 32768.0;
            if (r >= N) so = mem[(r - N) % 2048] / 32768.0; else so = 0;
            t_re = fr_re + sr - so;
            t_im = fr_im;
            fr_re = t_re * cth - t_im * sth;
            fr_im = t_re * sth + t_im * cth;

            pe_re = f_re / scale;
            pe_im = f_im / scale;
            err = $sqrt((pe_re - fr_re)*(pe_re - fr_re) + (pe_im - fr_im)*(pe_im - fr_im));
            mag = $sqrt(pe_re*pe_re + pe_im*pe_im);
            $fwrite(fd, "%0d,%e,%f\n", r, err, mag);

            // (the warm up samples after the clear are skipped, F is not valid yet)
            if (err > max_all && !(r >= CLEAR_AT && r < CLEAR_AT + N - 1)) max_all = err;
            if (r < 64 && err > max_early) max_early = err;
            if (r == CLEAR_AT - 1) err_before = err;
            if (r >= CLEAR_AT + N - 1 && r < CLEAR_AT + N + 63 && err > max_after) max_after = err;

            // valid flag: low during warm up after the clear, high otherwise
            if (r >= N-1 && r < CLEAR_AT && !valid) begin
                errors = errors + 1; $display("error: valid low at r=%0d", r);
            end
            if (r >= CLEAR_AT && r < CLEAR_AT + N) begin
                if (valid != (r == CLEAR_AT + N - 1)) begin
                    errors = errors + 1; $display("error: valid wrong at r=%0d (%0d)", r, valid);
                end
            end
        end
        $fclose(fd);

        $display("max error, first 64 samples        = %e", max_early);
        $display("error just before refresh (r=%0d) = %e", CLEAR_AT-1, err_before);
        $display("max error, 64 samples after refresh = %e", max_after);
        $display("error at the last sample (r=%0d)  = %e", NS-1, err);
        $display("max error over the whole run       = %e", max_all);

        // the error must be small at the start and again after the refresh,
        // and the refresh must bring it well below the drifted value
        if (max_early > 5e-3) begin errors = errors + 1; $display("error: early error too large"); end
        if (max_after > 5e-3) begin errors = errors + 1; $display("error: error after refresh too large"); end
        if (max_after > err_before / 5) begin errors = errors + 1; $display("error: refresh did not reduce the error"); end

        if (errors == 0) $display("running_dft_pe_tb PASSED");
        else             $display("running_dft_pe_tb FAILED, %0d errors", errors);
        $finish;
    end

endmodule
