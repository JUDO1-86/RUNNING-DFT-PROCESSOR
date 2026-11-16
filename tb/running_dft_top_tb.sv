`timescale 1ns/1ps

module running_dft_top_tb;

    parameter N           = 16;
    parameter W           = 22;
    parameter NS          = 8192;
    parameter PERIOD      = 40;        // clocks per sample (must be > ITER+1; 40 lets the magnitude finish too)
    parameter SWAP_PERIOD = 512;
    parameter FRAC        = 19;
    parameter THETA_K1    = 411775;    // 2*pi*1/16 * 2^20 (22.5 deg)
    parameter THETA_K5    = 2058874;   // 2*pi*5/16 * 2^20 (112.5 deg, Quadrant II)
    parameter real K      = 1.6467602581;

    reg clk = 0;
    reg rst_n = 0;
    reg sample_en = 0;
    reg signed [15:0] s_in_re = 0;
    reg signed [15:0] s_in_im = 0;
    reg signed [23:0] theta_w = THETA_K1;
    wire signed [W-1:0] f_re, f_im, mag;
    wire mag_done, mag_ok, swap_sel;

    running_dft_top #(
        .N(N),
        .W(W),
        .SWAP_PERIOD(SWAP_PERIOD)
    ) dut (
        .clk(clk), .rst_n(rst_n), .sample_en(sample_en),
        .s_re(s_in_re), .s_im(s_in_im), .theta(theta_w),
        .f_re(f_re), .f_im(f_im), .mag(mag), .mag_done(mag_done),
        .mag_ok(mag_ok), .swap_sel(swap_sel));

    always #5 clk = ~clk;

    // clock counter and mag_done counter (for the latency and pulse count checks)
    integer cyc = 0, done_cnt = 0, t_strobe = 0, t_first_done = 0;
    always @(posedge clk) begin
        cyc <= cyc + 1;
        if (mag_done) begin
            if (done_cnt == 0) t_first_done <= cyc;
            done_cnt <= done_cnt + 1;
        end
    end

    reg signed [15:0] mem_re [0:2047];
    reg signed [15:0] mem_im [0:2047];
    integer r, c, h, fd, errors;
    real pi, th, cth, sth, scale, val_re, val_im;
    real sr_re, sr_im, so_re, so_im, fr_re, fr_im, t_re, t_im;
    real pe_re, pe_im, cerr, mag_n, ideal, merr, bound;
    real max_cerr, max_merr, max_cplx_cerr, max_cplx_merr;
    reg [255:0] fname;

    initial begin
        pi = 3.141592653589793;
        // Generate the paper's test signal x(n) = (2/N) * sum_{k=1..7} sin(n*theta_k) in Q1.15
        // (and overwrite from input_re.hex if present)
        for (r = 0; r < 2048; r = r + 1) begin
            val_re = 0.0;
            for (h = 1; h <= 7; h = h + 1)
                val_re = val_re + $sin(2.0 * pi * h * r / N);
            val_re = val_re * (2.0 / N);
            mem_re[r] = $rtoi(val_re * 32768.0);

            // Complex test signal for Phase 2: exp(j*2*pi*5*n/N)/N + 0.5*exp(-j*2*pi*2*n/N)/N
            val_re = ($cos(2.0 * pi * 5.0 * r / N) + 0.5 * $cos(2.0 * pi * 2.0 * r / N)) / N;
            val_im = ($sin(2.0 * pi * 5.0 * r / N) - 0.5 * $sin(2.0 * pi * 2.0 * r / N)) / N;
            mem_im[r] = $rtoi(val_im * 32768.0);
        end

        theta_w = THETA_K1;
        th = 2.0 * pi / N;
        cth = $cos(th);
        sth = $sin(th);
        scale = 2.0 ** FRAC;
        fr_re = 0; fr_im = 0;
        errors = 0; max_cerr = 0; max_merr = 0;
        bound = 3.2e-5 * (2.0 * SWAP_PERIOD) + 1e-3;
        $sformat(fname, "top_mag_P%0d.csv", SWAP_PERIOD);
        fd = $fopen(fname, "w");
        $fwrite(fd, "r,mag_norm,mag_ideal,cerr,sel\n");

        #22 rst_n = 1;

        for (r = 0; r < NS; r = r + 1) begin
            @(negedge clk);
            s_in_re = mem_re[r % 2048];
            s_in_im = 16'sd0;
            sample_en = 1;
            if (r == 0) t_strobe = cyc;
            @(negedge clk);
            sample_en = 0;
            for (c = 2; c < PERIOD; c = c + 1) @(negedge clk);

            // ideal sliding DFT (real input)
            sr_re = s_in_re / 32768.0;
            if (r >= N) so_re = mem_re[(r - N) % 2048] / 32768.0; else so_re = 0;
            t_re = fr_re + sr_re - so_re;
            t_im = fr_im;
            fr_re = t_re * cth - t_im * sth;
            fr_im = t_re * sth + t_im * cth;
            ideal = $sqrt(fr_re*fr_re + fr_im*fr_im);

            pe_re = f_re / scale;
            pe_im = f_im / scale;
            cerr  = $sqrt((pe_re - fr_re)*(pe_re - fr_re) + (pe_im - fr_im)*(pe_im - fr_im));
            mag_n = mag / scale / K;                 // remove the CORDIC gain
            merr  = (mag_n > ideal) ? mag_n - ideal : ideal - mag_n;
            $fwrite(fd, "%0d,%f,%f,%e,%0d\n", r, mag_n, ideal, cerr, swap_sel);

            if (r >= N - 1) begin
                if (!mag_ok) begin errors = errors + 1; $display("error: mag_ok low at r=%0d", r); end
                if (cerr > max_cerr) max_cerr = cerr;
                if (merr > max_merr) max_merr = merr;
            end
        end
        $fclose(fd);

        $display("=== Phase 1: Real Input (Paper Signal, Bin k=1) ===");
        $display("SWAP_PERIOD = %0d", SWAP_PERIOD);
        $display("latency sample_en -> first mag_done = about %0d clocks", t_first_done - t_strobe);
        $display("mag_done pulses                     = %0d (samples: %0d)", done_cnt, NS);
        $display("max |mag/K - ideal|                 = %e", max_merr);
        $display("max complex error                   = %e", max_cerr);
        $display("complex error at the last sample    = %e", cerr);

        if (done_cnt != NS) begin errors = errors + 1; $display("error: wrong number of mag_done pulses"); end
        if (max_merr > 1e-3) begin errors = errors + 1; $display("error: magnitude error too large"); end
        if (SWAP_PERIOD < NS && max_cerr > bound) begin
            errors = errors + 1; $display("error: complex error above bound %e", bound);
        end


        @(negedge clk);
        rst_n = 0;
        #20;
        @(negedge clk);
        theta_w = THETA_K5;
        rst_n = 1;

        th = 2.0 * pi * 5.0 / N;
        cth = $cos(th);
        sth = $sin(th);
        fr_re = 0; fr_im = 0;
        max_cplx_cerr = 0; max_cplx_merr = 0;

        for (r = 0; r < 1024; r = r + 1) begin
            @(negedge clk);
            s_in_re = mem_re[r % 2048];
            s_in_im = mem_im[r % 2048];
            sample_en = 1;
            @(negedge clk);
            sample_en = 0;
            for (c = 2; c < PERIOD; c = c + 1) @(negedge clk);

            // ideal sliding DFT for full complex input s_re + j*s_im
            sr_re = s_in_re / 32768.0;
            sr_im = s_in_im / 32768.0;
            if (r >= N) begin
                so_re = mem_re[(r - N) % 2048] / 32768.0;
                so_im = mem_im[(r - N) % 2048] / 32768.0;
            end
            else begin
                so_re = 0;
                so_im = 0;
            end
            t_re = fr_re + sr_re - so_re;
            t_im = fr_im + sr_im - so_im;
            fr_re = t_re * cth - t_im * sth;
            fr_im = t_re * sth + t_im * cth;
            ideal = $sqrt(fr_re*fr_re + fr_im*fr_im);

            pe_re = f_re / scale;
            pe_im = f_im / scale;
            cerr  = $sqrt((pe_re - fr_re)*(pe_re - fr_re) + (pe_im - fr_im)*(pe_im - fr_im));
            mag_n = mag / scale / K;
            merr  = (mag_n > ideal) ? mag_n - ideal : ideal - mag_n;

            if (r >= N - 1) begin
                if (cerr > max_cplx_cerr) max_cplx_cerr = cerr;
                if (merr > max_cplx_merr) max_cplx_merr = merr;
            end
        end

        $display("=== Phase 2: Complex Input s_re + j*s_im (Quadrant-II Bin k=5) ===");
        $display("max complex-input |mag/K - ideal|   = %e", max_cplx_merr);
        $display("max complex-input vector error      = %e", max_cplx_cerr);
        if (max_cplx_merr > 2e-3 || max_cplx_cerr > bound) begin
            errors = errors + 1;
            $display("error: Phase 2 complex input / Quadrant-II bin check failed");
        end

        if (errors == 0) $display("running_dft_top_tb PASSED (Both Real & Complex Input Phases)");
        else             $display("running_dft_top_tb FAILED, %0d errors", errors);
        $finish;
    end

endmodule
