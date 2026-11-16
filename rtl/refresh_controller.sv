module refresh_controller #(
    parameter SWAP_PERIOD     = 512,
    parameter N               = 16,
    parameter PAPER_FIG3_MODE = 0
)
(
    input      clk,
    input      rst_n,
    input      sample_done,
    input      valid_u,
    input      valid_l,
    output reg refresh_u,
    output reg refresh_l,
    output reg swap_sel
);

    reg [31:0] cnt;
    reg [31:0] down_cnt;
    reg        swapsig;
    reg [15:0] delay_cnt;
    reg        delay_active;

    wire refrper = (down_cnt == 0);

    initial begin
        if (SWAP_PERIOD < N)
            $display("refresh_controller warning: SWAP_PERIOD (%0d) < N (%0d), swaps wait for the other PE to be valid so the real period is N",
                     SWAP_PERIOD, N);
    end

    wire other_valid = swap_sel ? valid_u : valid_l;

    always @(posedge clk) begin
        refresh_u <= 1'b0;
        refresh_l <= 1'b0;

        if (!rst_n) begin
            cnt          <= 0;
            swap_sel     <= 1'b0;
            down_cnt     <= (SWAP_PERIOD > N) ? (SWAP_PERIOD - N - 1) : (N - 1);
            swapsig      <= 1'b0;
            delay_cnt    <= 0;
            delay_active <= 1'b0;
        end
        else if (sample_done) begin
            if (PAPER_FIG3_MODE) begin
                if (delay_active) begin
                    if (delay_cnt == N - 1) begin
                        swap_sel     <= swapsig;
                        delay_active <= 1'b0;
                        delay_cnt    <= 0;
                    end
                    else begin
                        delay_cnt <= delay_cnt + 1;
                    end
                end
                if (refrper) begin
                    down_cnt     <= (SWAP_PERIOD > N) ? (SWAP_PERIOD - 1) : (N - 1);
                    swapsig      <= ~swapsig;
                    if (~swapsig) refresh_l <= 1'b1; 
                    else          refresh_u <= 1'b1; 
                    delay_active <= 1'b1;
                    delay_cnt    <= 0;
                end
                else begin
                    down_cnt <= down_cnt - 1;
                end
            end
            else begin
                if (cnt >= SWAP_PERIOD - 1) begin
                    if (other_valid) begin
                        swap_sel <= ~swap_sel;
                        if (swap_sel) refresh_l <= 1'b1;   
                        else          refresh_u <= 1'b1;   
                        cnt <= 0;
                    end
                end
                else begin
                    cnt <= cnt + 1;
                end
            end
        end
    end

endmodule
