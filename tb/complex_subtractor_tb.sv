`timescale 1ns/1ps
module complex_subtractor_tb;

    reg  signed [15:0] a_re, a_im, b_re, b_im;
    wire signed [21:0] d_re, d_im;
    integer errors, i;

    complex_subtractor #(16, 22, 4) dut (a_re, a_im, b_re, b_im, d_re, d_im);

    // apply inputs and compare with plain integer math
    task check(input integer ar, input integer ai, input integer br, input integer bi);
        integer exp_re, exp_im;
        begin
            a_re = ar; a_im = ai; b_re = br; b_im = bi;
            #1;
            exp_re = (ar - br) * 16;
            exp_im = (ai - bi) * 16;
            if (d_re !== exp_re || d_im !== exp_im) begin
                errors = errors + 1;
                $display("error: (%0d,%0d)-(%0d,%0d) got %0d,%0d expected %0d,%0d",
                         ar, ai, br, bi, d_re, d_im, exp_re, exp_im);
            end
        end
    endtask

    initial begin
        errors = 0;
        check(0, 0, 0, 0);
        check(100, -200, 30, 50);
        check(-1, 1, 1, -1);
        // extreme values
        check(-32768, 32767, 32767, -32768);
        check(32767, 32767, -32768, -32768);

        for (i = 0; i < 2000; i = i + 1)
            check($urandom_range(65535) - 32768, $urandom_range(65535) - 32768,
                  $urandom_range(65535) - 32768, $urandom_range(65535) - 32768);

        if (errors == 0) $display("complex_subtractor_tb PASSED");
        else             $display("complex_subtractor_tb FAILED, %0d errors", errors);
        $finish;
    end

endmodule
