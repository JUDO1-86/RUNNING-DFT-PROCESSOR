// delta_s = s(r) - s(r-N)
// output is sign extended and shifted left by GUARD_LSB bits
module complex_subtractor #(parameter IN_W = 16, parameter OUT_W = 22, parameter GUARD_LSB = 4)
(
    input  signed [IN_W-1:0]  a_re, a_im,   // s(r)
    input  signed [IN_W-1:0]  b_re, b_im,   // s(r-N)
    output signed [OUT_W-1:0] d_re, d_im
);

    wire signed [OUT_W-1:0] a_re_ext = {{(OUT_W-IN_W){a_re[IN_W-1]}}, a_re};
    wire signed [OUT_W-1:0] a_im_ext = {{(OUT_W-IN_W){a_im[IN_W-1]}}, a_im};
    wire signed [OUT_W-1:0] b_re_ext = {{(OUT_W-IN_W){b_re[IN_W-1]}}, b_re};
    wire signed [OUT_W-1:0] b_im_ext = {{(OUT_W-IN_W){b_im[IN_W-1]}}, b_im};

    assign d_re = (a_re_ext - b_re_ext) <<< GUARD_LSB;
    assign d_im = (a_im_ext - b_im_ext) <<< GUARD_LSB;

endmodule
