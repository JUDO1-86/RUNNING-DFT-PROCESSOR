`timescale 1ns/1ps
module sample_fifo_tb;

    parameter N = 16;
    parameter W = 16;

    reg clk = 0;
    reg rst_n = 0;
    reg shift_en = 0;
    reg signed [W-1:0] din_re, din_im;
    wire signed [W-1:0] dout_re, dout_im;

    reg signed [W-1:0] ref_re [0:199];
    reg signed [W-1:0] ref_im [0:199];
    integer r, errors;
    reg signed [W-1:0] held;

    sample_fifo #(N, W) dut (clk, rst_n, shift_en, din_re, din_im, dout_re, dout_im);

    always #5 clk = ~clk;

    initial begin
        errors = 0;
        for (r = 0; r < 200; r = r + 1) begin
            ref_re[r] = r*37 - 3000;
            ref_im[r] = -r*11 + 500;
        end

        #25 rst_n = 1;

        for (r = 0; r < 200; r = r + 1) begin
            @(negedge clk);
            din_re = ref_re[r];
            din_im = ref_im[r];
            shift_en = 1;
            #1;
            if (r < N) begin
                if (dout_re !== 0 || dout_im !== 0) begin
                    errors = errors + 1;
                    $display("error at r=%0d, expected 0", r);
                end
            end
            else if (dout_re !== ref_re[r-N] || dout_im !== ref_im[r-N]) begin
                errors = errors + 1;
                $display("error at r=%0d: got %0d,%0d expected %0d,%0d",
                         r, dout_re, dout_im, ref_re[r-N], ref_im[r-N]);
            end
        end

        // output must not change when shift_en is low
        @(negedge clk);
        shift_en = 0;
        #1 held = dout_re;
        repeat (5) @(negedge clk);
        if (dout_re !== held) begin
            errors = errors + 1;
            $display("error: fifo moved without shift_en");
        end

        if (errors == 0) $display("sample_fifo_tb PASSED");
        else             $display("sample_fifo_tb FAILED, %0d errors", errors);
        $finish;
    end

endmodule
