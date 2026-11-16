// Running DFT, Architecture-1 (iterative CORDIC) with refreshing mechanism
// based on Ray & Dhar (2019), Fig. 2 & Section 4.1.
//
//   s(n) -> FIFO -> complex subtractor -> delta_s
//        -> PE(U) / PE(L) (alternately refreshed) -> output mux -> vectoring CORDIC -> |F(r,k)|
//
// With quadrant pre-rotation in cordic_rotate, ALL frequency bins k = 0..N-1
// (theta_k = 2*pi*k/N in Q3.20 radians) are supported across the full [0, 2*pi) circle.
//
// This file provides:
//   1. `running_dft_top`          : Single-bin Architecture-1 (Fig. 2)
//   2. `running_dft_all_bins_top` : N-parallel multi-bin Architecture-1 (Fig. 1 / Table 2)
module running_dft_top #(
    parameter N                 = 16,
    parameter W                 = 22,
    parameter ITER              = 16,
    parameter ANG_W             = 24,
    parameter SWAP_PERIOD       = 512,
    parameter PAPER_FIG3_MODE   = 0,
    parameter SINGLE_CYCLE_COMP = 0,
    parameter PAPER_TRUNC_SCALE = 0
)
(
    input                      clk,
    input                      rst_n,
    input                      sample_en,
    input  signed [15:0]       s_re,
    input  signed [15:0]       s_im,
    input  signed [ANG_W-1:0]  theta,
    output signed [W-1:0]      f_re,
    output signed [W-1:0]      f_im,
    output signed [W-1:0]      mag,
    output                     mag_done,
    output reg                 mag_ok,
    output                     swap_sel
);

    wire signed [15:0]  old_re, old_im;
    wire signed [W-1:0] ds_re, ds_im;
    wire signed [W-1:0] u_re, u_im, l_re, l_im;
    wire u_done, l_done, u_valid, l_valid, o_valid;
    wire refresh_u, refresh_l;

    // s(r) in the internal format (sign extended, 4 guard bits), used while a PE warms up
    wire signed [W-1:0] s_g_re = {{(W-16){s_re[15]}}, s_re} <<< 4;
    wire signed [W-1:0] s_g_im = {{(W-16){s_im[15]}}, s_im} <<< 4;

    sample_fifo #(.N(N), .W(16)) fifo (
        .clk(clk), .rst_n(rst_n), .shift_en(sample_en),
        .din_re(s_re), .din_im(s_im), .dout_re(old_re), .dout_im(old_im));

    complex_subtractor #(.IN_W(16), .OUT_W(W), .GUARD_LSB(4)) sub (
        .a_re(s_re), .a_im(s_im), .b_re(old_re), .b_im(old_im),
        .d_re(ds_re), .d_im(ds_im));

    running_dft_pe #(
        .W(W), .ITER(ITER), .N(N), .ANG_W(ANG_W),
        .SINGLE_CYCLE_COMP(SINGLE_CYCLE_COMP),
        .PAPER_TRUNC_SCALE(PAPER_TRUNC_SCALE)
    ) pe_u (
        .clk(clk), .rst_n(rst_n), .clear(refresh_u), .sample_en(sample_en),
        .ds_re(ds_re), .ds_im(ds_im), .s_re(s_g_re), .s_im(s_g_im), .theta(theta),
        .f_re(u_re), .f_im(u_im), .done(u_done), .valid(u_valid));

    running_dft_pe #(
        .W(W), .ITER(ITER), .N(N), .ANG_W(ANG_W),
        .SINGLE_CYCLE_COMP(SINGLE_CYCLE_COMP),
        .PAPER_TRUNC_SCALE(PAPER_TRUNC_SCALE)
    ) pe_l (
        .clk(clk), .rst_n(rst_n), .clear(refresh_l), .sample_en(sample_en),
        .ds_re(ds_re), .ds_im(ds_im), .s_re(s_g_re), .s_im(s_g_im), .theta(theta),
        .f_re(l_re), .f_im(l_im), .done(l_done), .valid(l_valid));

    refresh_controller #(
        .SWAP_PERIOD(SWAP_PERIOD),
        .N(N),
        .PAPER_FIG3_MODE(PAPER_FIG3_MODE)
    ) ctrl (
        .clk(clk), .rst_n(rst_n), .sample_done(u_done),
        .valid_u(u_valid), .valid_l(l_valid),
        .refresh_u(refresh_u), .refresh_l(refresh_l), .swap_sel(swap_sel));

    output_mux #(.W(W)) mux (
        .sel(swap_sel),
        .u_re(u_re), .u_im(u_im), .u_valid(u_valid),
        .l_re(l_re), .l_im(l_im), .l_valid(l_valid),
        .o_re(f_re), .o_im(f_im), .o_valid(o_valid));

    // the magnitude is started in the clock where the PEs finish a sample
    cordic_vector #(.W(W), .ITER(ITER)) vec (
        .clk(clk), .rst_n(rst_n), .start(u_done),
        .x_in(f_re), .y_in(f_im), .mag(mag), .done(mag_done));

    // remember if the PE that was selected at the start was valid
    always @(posedge clk) begin
        if (!rst_n)
            mag_ok <= 1'b0;
        else if (u_done)
            mag_ok <= o_valid;
    end

endmodule


// Multi-Bin Parallel Architecture-1 (Section 4.1 & Table 2: M = N = 16 parallel bins)
// Shares 1 sample_fifo (size N), 1 complex_subtractor (2 adders), and 1 refresh_controller,
// while replicating PE(U), PE(L), output_mux, and cordic_vector across all N bins
// (Total: 5N CORDICs, 4N + 2 adders, 0 multipliers, N DPRAM).
module running_dft_all_bins_top #(
    parameter N                 = 16,
    parameter W                 = 22,
    parameter ITER              = 16,
    parameter ANG_W             = 24,
    parameter SWAP_PERIOD       = 512,
    parameter PAPER_FIG3_MODE   = 0,
    parameter SINGLE_CYCLE_COMP = 0,
    parameter PAPER_TRUNC_SCALE = 0
)
(
    input                      clk,
    input                      rst_n,
    input                      sample_en,
    input  signed [15:0]       s_re,
    input  signed [15:0]       s_im,
    output signed [W-1:0]      f_re     [0:N-1],
    output signed [W-1:0]      f_im     [0:N-1],
    output signed [W-1:0]      mag      [0:N-1],
    output                     mag_done,
    output reg                 mag_ok,
    output                     swap_sel
);

    // Precomputed theta_k = round(2*pi*k/16 * 2^20) for k = 0..15
    function signed [ANG_W-1:0] theta_lut(input integer k_idx);
        case (k_idx)
            0:  theta_lut = 24'sd0;
            1:  theta_lut = 24'sd411775;
            2:  theta_lut = 24'sd823550;
            3:  theta_lut = 24'sd1235324;
            4:  theta_lut = 24'sd1647099;
            5:  theta_lut = 24'sd2058874;
            6:  theta_lut = 24'sd2470649;
            7:  theta_lut = 24'sd2882424;
            8:  theta_lut = 24'sd3294199;
            9:  theta_lut = 24'sd3705973;
            10: theta_lut = 24'sd4117748;
            11: theta_lut = 24'sd4529523;
            12: theta_lut = 24'sd4941298;
            13: theta_lut = 24'sd5353073;
            14: theta_lut = 24'sd5764848;
            15: theta_lut = 24'sd6176622;
            default: theta_lut = 24'sd0;
        endcase
    endfunction

    wire signed [15:0]  old_re, old_im;
    wire signed [W-1:0] ds_re, ds_im;
    wire signed [W-1:0] s_g_re = {{(W-16){s_re[15]}}, s_re} <<< 4;
    wire signed [W-1:0] s_g_im = {{(W-16){s_im[15]}}, s_im} <<< 4;

    wire [N-1:0] u_done, l_done, u_valid, l_valid, o_valid, vec_done;
    wire refresh_u, refresh_l;

    sample_fifo #(.N(N), .W(16)) fifo (
        .clk(clk), .rst_n(rst_n), .shift_en(sample_en),
        .din_re(s_re), .din_im(s_im), .dout_re(old_re), .dout_im(old_im));

    complex_subtractor #(.IN_W(16), .OUT_W(W), .GUARD_LSB(4)) sub (
        .a_re(s_re), .a_im(s_im), .b_re(old_re), .b_im(old_im),
        .d_re(ds_re), .d_im(ds_im));

    refresh_controller #(
        .SWAP_PERIOD(SWAP_PERIOD),
        .N(N),
        .PAPER_FIG3_MODE(PAPER_FIG3_MODE)
    ) ctrl (
        .clk(clk), .rst_n(rst_n), .sample_done(u_done[0]),
        .valid_u(u_valid[0]), .valid_l(l_valid[0]),
        .refresh_u(refresh_u), .refresh_l(refresh_l), .swap_sel(swap_sel));

    genvar k;
    generate
        for (k = 0; k < N; k = k + 1) begin : gen_bins
            wire signed [W-1:0] u_re_k, u_im_k, l_re_k, l_im_k;

            running_dft_pe #(
                .W(W), .ITER(ITER), .N(N), .ANG_W(ANG_W),
                .SINGLE_CYCLE_COMP(SINGLE_CYCLE_COMP),
                .PAPER_TRUNC_SCALE(PAPER_TRUNC_SCALE)
            ) pe_u_k (
                .clk(clk), .rst_n(rst_n), .clear(refresh_u), .sample_en(sample_en),
                .ds_re(ds_re), .ds_im(ds_im), .s_re(s_g_re), .s_im(s_g_im),
                .theta(theta_lut(k)),
                .f_re(u_re_k), .f_im(u_im_k), .done(u_done[k]), .valid(u_valid[k]));

            running_dft_pe #(
                .W(W), .ITER(ITER), .N(N), .ANG_W(ANG_W),
                .SINGLE_CYCLE_COMP(SINGLE_CYCLE_COMP),
                .PAPER_TRUNC_SCALE(PAPER_TRUNC_SCALE)
            ) pe_l_k (
                .clk(clk), .rst_n(rst_n), .clear(refresh_l), .sample_en(sample_en),
                .ds_re(ds_re), .ds_im(ds_im), .s_re(s_g_re), .s_im(s_g_im),
                .theta(theta_lut(k)),
                .f_re(l_re_k), .f_im(l_im_k), .done(l_done[k]), .valid(l_valid[k]));

            output_mux #(.W(W)) mux_k (
                .sel(swap_sel),
                .u_re(u_re_k), .u_im(u_im_k), .u_valid(u_valid[k]),
                .l_re(l_re_k), .l_im(l_im_k), .l_valid(l_valid[k]),
                .o_re(f_re[k]), .o_im(f_im[k]), .o_valid(o_valid[k]));

            cordic_vector #(.W(W), .ITER(ITER)) vec_k (
                .clk(clk), .rst_n(rst_n), .start(u_done[k]),
                .x_in(f_re[k]), .y_in(f_im[k]), .mag(mag[k]), .done(vec_done[k]));
        end
    endgenerate

    assign mag_done = vec_done[0];

    always @(posedge clk) begin
        if (!rst_n)
            mag_ok <= 1'b0;
        else if (u_done[0])
            mag_ok <= o_valid[0];
    end

endmodule