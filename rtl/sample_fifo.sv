module sample_fifo #(parameter N = 16, parameter W = 16)
(
    input                clk,
    input                rst_n,
    input                shift_en,
    input  signed [W-1:0] din_re,
    input  signed [W-1:0] din_im,
    output signed [W-1:0] dout_re,
    output signed [W-1:0] dout_im
);

    reg signed [W-1:0] mem_re [0:N-1];
    reg signed [W-1:0] mem_im [0:N-1];
    reg [$clog2(N)-1:0] ptr;
    reg [$clog2(N):0]   fill_cnt;

    wire full = (fill_cnt == N);
    assign dout_re = full ? mem_re[ptr] : {W{1'b0}};
    assign dout_im = full ? mem_im[ptr] : {W{1'b0}};

    always @(posedge clk) begin
        if (!rst_n) begin
            ptr      <= 0;
            fill_cnt <= 0;
        end
        else if (shift_en) begin
            mem_re[ptr] <= din_re;
            mem_im[ptr] <= din_im;
            if (ptr == N - 1)
                ptr <= 0;
            else
                ptr <= ptr + 1;
            if (!full)
                fill_cnt <= fill_cnt + 1;
        end
    end

endmodule
