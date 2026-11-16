`timescale 1ns/1ps
module cordic_vector_tb;

    parameter W = 22;
    parameter FRAC = 19;
    parameter TOL = 64;
    parameter real K = 1.6467602581;

    reg clk = 0;
    reg rst_n = 0;
    reg start = 0;
    reg signed [W-1:0] x_in, y_in;
    wire signed [W-1:0] mag;
    wire done;

    integer errors, i, max_err;

    cordic_vector #(.W(W)) dut (clk, rst_n, start, x_in, y_in, mag, done);

    always #5 clk = ~clk;

    task run(input real xr, input real yr);
        real scale, expected;
        integer e;
        begin
            scale = 2.0 ** FRAC;
            x_in = $rtoi(xr * scale);
            y_in = $rtoi(yr * scale);
            @(negedge clk);
            start = 1;
            @(negedge clk);
            start = 0;
            while (!done) @(negedge clk);

            // output is scaled by K (not compensated)
            expected = K * $sqrt(1.0*x_in*x_in + 1.0*y_in*y_in);
            e = mag - $rtoi(expected);
            if (e < 0) e = -e;
            if (e > max_err) max_err = e;
            if (e > TOL) begin
                errors = errors + 1;
                $display("error: in=(%f,%f) got %0d expected %0d", xr, yr, mag, $rtoi(expected));
            end
        end
    endtask

    real a, m;

    initial begin
        errors = 0;
        max_err = 0;
        #22 rst_n = 1;

        run(1.0, 0.0);
        run(0.0, 1.0);
        run(0.0, -1.0);
        run(-1.0, 0.0);       // negative x, handled by negating the input
        run(-0.6, -0.8);
        run(0.0, 0.0);
        run(0.6, 0.8);

        // random vectors, all quadrants
        for (i = 0; i < 500; i = i + 1) begin
            m = ($urandom_range(1000) / 1000.0) * 1.2;
            a = ($urandom_range(6283) / 1000.0) - 3.1415;
            run(m * $cos(a), m * $sin(a));
        end

        $display("max error = %0d LSB", max_err);
        if (errors == 0) $display("cordic_vector_tb PASSED");
        else             $display("cordic_vector_tb FAILED, %0d errors", errors);
        $finish;
    end

endmodule
