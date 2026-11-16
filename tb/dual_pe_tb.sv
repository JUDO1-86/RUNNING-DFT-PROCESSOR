`timescale 1ns/1ps
// Dual PE test (Level 3): fifo + subtractor + PE(U) + PE(L) + refresh_controller + output_mux.
// The muxed output is compared with an ideal floating point sliding DFT (k = 1, N = 16).
// SWAP_PERIOD can be changed from the command line, a very large value = no refresh.
//
// run this from the reference folder (hex file is read from the current dir)
module dual_pe_tb;

    parameter N           = 16;
    parameter W           = 22;
    parameter NS          = 8192;
    parameter PERIOD      = 24;        // clocks per sample (> CORDIC latency of 17)
    parameter SWAP_PERIOD = 1048576;
    parameter FRAC        = 19;
    parameter THETA       = 411775;    // 2*pi/16 * 2^20

    reg clk = 0;
    reg rst_n = 0;
    reg sample_en = 0;
    reg signed [15:0] s_in;
    wire signed [15:0] old_re, old_im;
    wire signed [W-1:0] ds_re, ds_im;
    wire signed [23:0] theta_w = THETA;

    wire signed [W-1:0] u_re, u_im, l_re, l_im, o_re, o_im;
    wire u_done, l_done, u_valid, l_valid, o_valid;
    wire refresh_u, refresh_l, swap_sel;

    wire signed [W-1:0] s_g_re = {{(W-16){s_in[15]}}, s_in} <<< 4;
    wire signed [W-1:0] s_g_im = 0;

    sample_fifo #(.N(N), .W(16)) fifo (
        .clk(clk), .rst_n(rst_n), .shift_en(sample_en),
        .din_re(s_in), .din_im(16'sd0), .dout_re(old_re), .dout_im(old_im));

    complex_subtractor #(.IN_W(16), .OUT_W(W), .GUARD_LSB(4)) sub (
        .a_re(s_in), .a_im(16'sd0), .b_re(old_re), .b_im(old_im),
        .d_re(ds_re), .d_im(ds_im));

    running_dft_pe #(.W(W), .N(N)) pe_u (
        .clk(clk), .rst_n(rst_n), .clear(refresh_u), .sample_en(sample_en),
        .ds_re(ds_re), .ds_im(ds_im), .s_re(s_g_re), .s_im(s_g_im),
        .theta(theta_w), .f_re(u_re), .f_im(u_im), .done(u_done), .valid(u_valid));

    running_dft_pe #(.W(W), .N(N)) pe_l (
        .clk(clk), .rst_n(rst_n), .clear(refresh_l), .sample_en(sample_en),
        .ds_re(ds_re), .ds_im(ds_im), .s_re(s_g_re), .s_im(s_g_im),
        .theta(theta_w), .f_re(l_re), .f_im(l_im), .done(l_done), .valid(l_valid));

    refresh_controller #(.SWAP_PERIOD(SWAP_PERIOD), .N(N)) ctrl (
        .clk(clk), .rst_n(rst_n), .sample_done(u_done),
        .valid_u(u_valid), .valid_l(l_valid),
        .refresh_u(refresh_u), .refresh_l(refresh_l), .swap_sel(swap_sel));

    output_mux #(.W(W)) mux (
        .sel(swap_sel),
        .u_re(u_re), .u_im(u_im), .u_valid(u_valid),
        .l_re(l_re), .l_im(l_im), .l_valid(l_valid),
        .o_re(o_re), .o_im(o_im), .o_valid(o_valid));

    always #5 clk = ~clk;

    reg signed [15:0] mem [0:2047];
    integer r, c, fd, errors, k, exp_sel, swaps;
    real th, cth, sth, scale;
    real sr, so, fr_re, fr_im, t_re, t_im;
    real pe_re, pe_im, err, mag, bound, max_err, max_magdev;
    reg cleared_valid;
    reg [255:0] fname;

    initial begin
        $readmemh("input_re.hex", mem);
        th = 6.28318530717959 / N;
        cth = $cos(th);
        sth = $sin(th);
        scale = 2.0 ** FRAC;
        fr_re = 0; fr_im = 0;
        errors = 0; swaps = 0;
        max_err = 0; max_magdev = 0;
        // each PE drifts about 2.6e-5 per sample (ITER = 16) and its age is at most 2*SWAP_PERIOD
        bound = 3.2e-5 * (2.0 * SWAP_PERIOD) + 1e-3;
        $sformat(fname, "dual_error_P%0d.csv", SWAP_PERIOD);
        fd = $fopen(fname, "w");
        $fwrite(fd, "r,err,mag,sel\n");

        #22 rst_n = 1;

        for (r = 0; r < NS; r = r + 1) begin
            @(negedge clk);
            s_in = mem[r % 2048];
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

            pe_re = o_re / scale;
            pe_im = o_im / scale;
            err = $sqrt((pe_re - fr_re)*(pe_re - fr_re) + (pe_im - fr_im)*(pe_im - fr_im));
            mag = $sqrt(pe_re*pe_re + pe_im*pe_im);
            $fwrite(fd, "%0d,%e,%f,%0d\n", r, err, mag, swap_sel);

            if (r >= N - 1) begin
                // output must always be valid and its magnitude must stay near 1.0 (no dropout)
                if (!o_valid) begin errors = errors + 1; $display("error: output not valid at r=%0d", r); end
                if (err > max_err) max_err = err;
                if ((mag - 1.0 > max_magdev) || (1.0 - mag > max_magdev))
                    max_magdev = (mag > 1.0) ? mag - 1.0 : 1.0 - mag;
            end

            // swap_sel must flip after samples P-1, 2P-1, ...  (only if P >= N)
            if (SWAP_PERIOD >= N) begin
                k = (r + 1) / SWAP_PERIOD;
                exp_sel = k % 2;
                if (swap_sel !== exp_sel) begin
                    errors = errors + 1;
                    $display("error: swap_sel=%0d expected %0d at r=%0d", swap_sel, exp_sel, r);
                end
                // the PE cleared at the last tick must be warming up, then become valid on the Nth sample
                k = r / SWAP_PERIOD;
                // (the last sample of an epoch is skipped: if P = N a new tick clears this PE again right after it)
                if (k >= 1 && (r % SWAP_PERIOD) <= N - 1 && (r % SWAP_PERIOD) != SWAP_PERIOD - 1) begin
                    cleared_valid = swap_sel ? u_valid : l_valid;   // the PE that is not the output
                    if (cleared_valid != ((r % SWAP_PERIOD) == N - 1)) begin
                        errors = errors + 1;
                        $display("error: cleared PE valid=%0d at r=%0d", cleared_valid, r);
                    end
                end
            end
        end
        $fclose(fd);

        $display("SWAP_PERIOD = %0d", SWAP_PERIOD);
        $display("max error over the run             = %e", max_err);
        $display("max |magnitude - 1| over the run   = %e", max_magdev);
        $display("error at the last sample           = %e", err);
        if (SWAP_PERIOD < NS) begin
            $display("error bound (2*P*3.2e-5 + 1e-3)    = %e", bound);
            if (max_err > bound) begin errors = errors + 1; $display("error: error above bound"); end
        end
        if (max_magdev > 2e-3) begin errors = errors + 1; $display("error: magnitude not continuous"); end

        if (errors == 0) $display("dual_pe_tb PASSED");
        else             $display("dual_pe_tb FAILED, %0d errors", errors);
        $finish;
    end

endmodule
