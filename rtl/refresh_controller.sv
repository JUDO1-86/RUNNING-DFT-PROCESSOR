// Refresh controller (REFRCKT + DELAY) for the two PEs (PE(U) and PE(L)).
//
// Supports two timing modes via PAPER_FIG3_MODE:
//
// 1. PAPER_FIG3_MODE = 1 (Paper Fig. 2 & Fig. 3 exact REFRCKT + DELAY architecture):
//    - Loadable down-counter + NOR zero-detect generates interim pulse `refrper`
//      every SWAP_PERIOD samples.
//    - Toggle flip-flop generates `swapsig`, and two AND gates generate
//      `refresh_l` (`refrsigl = refrper & swapsig`) and
//      `refresh_u` (`refrsigu = refrper & ~swapsig`) alternately.
//    - Separate N-sample DELAY block delays `swapsig` by N samples (`latency` in Fig. 3)
//      to produce `swap_sel` (`opswapsig`), so a freshly cleared PE warms up for
//      exactly N samples and then immediately takes over the output with zero
//      accumulated recursive drift (reproducing Fig. 6b's reset back to 1.0).
//
// 2. PAPER_FIG3_MODE = 0 (Default testbench-compatible mode for dual_pe_tb):
//    - Every SWAP_PERIOD samples, once the standby PE is valid, flips `swap_sel`
//      and pulses `refresh_u` / `refresh_l` on the outgoing PE.
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

    // Signals for PAPER_FIG3_MODE (Fig. 2 REFRCKT + DELAY)
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
                // DELAY block: delays swapsig by N samples (latency) to form opswapsig (swap_sel)
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

                // Loadable Down Counter + NOR (refrper) + T-FF (swapsig) + AND gates
                if (refrper) begin
                    down_cnt     <= (SWAP_PERIOD > N) ? (SWAP_PERIOD - 1) : (N - 1);
                    swapsig      <= ~swapsig;
                    // AND gates: alternate refresh pulses between PEL and PEU
                    if (~swapsig) refresh_l <= 1'b1; // refrsigl = refrper & new_swapsig
                    else          refresh_u <= 1'b1; // refrsigu = refrper & ~new_swapsig
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
                        if (swap_sel) refresh_l <= 1'b1;   // L was the output, clear it
                        else          refresh_u <= 1'b1;   // U was the output, clear it
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