`timescale 1ns/1ps
module cordic_rotate_tb;

    parameter W = 22;
    parameter FRAC = 19;        // internal format Q3.19 (Q1.15 plus 4 guard bits)
    parameter TOL = 64;         // allowed error in LSBs (about 1.2e-4)

    reg clk = 0;
    reg rst_n = 0;
    reg start = 0;
    reg signed [W-1:0] x_in, y_in;
    reg signed [23:0]  theta;
    wire signed [W-1:0] x_out, y_out;
    wire done;

    integer errors, i, k, max_err;
    real pi;

    cordic_rotate #(.W(W)) dut (clk, rst_n, start, x_in, y_in, theta, x_out, y_out, done);

    always #5 clk = ~clk;

    // run one rotation and compare with real number math
    task run(input real xr, input real yr, input real th);
        real ex, ey, scale;
        integer dx, dy, e;
        begin
            scale = 2.0 ** FRAC;
            x_in  = $rtoi(xr * scale);
            y_in  = $rtoi(yr * scale);
            theta = $rtoi(th * 1048576.0);       // 2^20
            @(negedge clk);
            start = 1;
            @(negedge clk);
            start = 0;
            while (!done) @(negedge clk);

            ex = (x_in * $cos(th) - y_in * $sin(th));
            ey = (x_in * $sin(th) + y_in * $cos(th));
            dx = x_out - $rtoi(ex);
            dy = y_out - $rtoi(ey);
            if (dx < 0) dx = -dx;
            if (dy < 0) dy = -dy;
            e = (dx > dy) ? dx : dy;
            if (e > max_err) max_err = e;
            if (e > TOL) begin
                errors = errors + 1;
                $display("error: in=(%f,%f) theta=%f  got (%0d,%0d) expected (%0d,%0d)",
                         xr, yr, th, x_out, y_out, $rtoi(ex), $rtoi(ey));
            end
        end
    endtask

    real a, m, t;

    initial begin
        pi = 3.14159265358979;
        errors = 0;
        max_err = 0;
        #22 rst_n = 1;

        // Test all 16 DFT harmonic angles theta_k = 2*pi*k/16 for k = 0..15 (full 0..360 deg circle)
        for (k = 0; k < 16; k = k + 1) begin
            run(0.8, -0.4, 2.0 * pi * k / 16.0);
        end

        // zero angle and zero input
        run(0.7, 0.3, 0.0);
        run(0.0, 0.0, 0.5);

        // random vectors (|v| < 1.2) and random angles across the entire [-pi, pi] circle
        for (i = 0; i < 500; i = i + 1) begin
            m = ($urandom_range(1000) / 1000.0) * 1.2;
            a = ($urandom_range(6283) / 1000.0) - 3.1415;
            t = ($urandom_range(6283) / 1000.0) - 3.1415;
            run(m * $cos(a), m * $sin(a), t);
        end

        $display("max error across all 4 quadrants = %0d LSB", max_err);
        if (errors == 0) $display("cordic_rotate_tb PASSED");
        else             $display("cordic_rotate_tb FAILED, %0d errors", errors);
        $finish;
    end

endmodule