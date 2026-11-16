// Iterative vectoring CORDIC (circular), gives the magnitude of (x_in, y_in).
// The output is NOT divided by the CORDIC gain, so
//     mag = K * sqrt(x_in^2 + y_in^2),   K = 1.6467602581 (same as the paper).
// Only the magnitude is computed, so if x_in is negative both inputs are
// negated first (this does not change the magnitude and keeps the CORDIC
// inside its convergence range).
//
// timing: pulse start for one clock, done is high ITER clocks after the clock that sampled start.
module cordic_vector #(
    parameter W    = 22,
    parameter ITER = 16
)
(
    input                      clk,
    input                      rst_n,
    input                      start,
    input  signed [W-1:0]      x_in,
    input  signed [W-1:0]      y_in,
    output reg signed [W-1:0]  mag,
    output reg                 done
);

    reg signed [W-1:0] x, y;
    reg [4:0] i;
    reg busy;

    wire signed [W-1:0] x_sh = x >>> i;
    wire signed [W-1:0] y_sh = y >>> i;

    always @(posedge clk) begin
        done <= 1'b0;

        if (!rst_n) begin
            busy <= 1'b0;
            i    <= 0;
            x    <= 0;
            y    <= 0;
            mag  <= 0;
        end
        else if (start && !busy) begin
            if (x_in < 0) begin
                x <= -x_in;
                y <= -y_in;
            end
            else begin
                x <= x_in;
                y <= y_in;
            end
            i    <= 0;
            busy <= 1'b1;
        end
        else if (busy) begin
            // drive y towards zero
            if (y >= 0) begin
                x <= x + y_sh;
                y <= y - x_sh;
            end
            else begin
                x <= x - y_sh;
                y <= y + x_sh;
            end
            i <= i + 1;

            if (i == ITER-1) begin
                busy <= 1'b0;
                done <= 1'b1;
            end
        end

        // after the last iteration x already holds the result
        if (busy && i == ITER-1) begin
            if (y >= 0) mag <= x + y_sh;
            else        mag <= x - y_sh;
        end
    end

endmodule
