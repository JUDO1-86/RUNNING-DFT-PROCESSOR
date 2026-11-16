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

        if (busy && i == ITER-1) begin
            if (y >= 0) mag <= x + y_sh;
            else        mag <= x - y_sh;
        end
    end

endmodule
