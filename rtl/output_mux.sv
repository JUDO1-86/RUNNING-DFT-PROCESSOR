// Picks the real and imaginary output of the PE that is currently active.
// sel = 0 : PE(U), sel = 1 : PE(L)
module output_mux #(parameter W = 22)
(
    input                 sel,
    input  signed [W-1:0] u_re, u_im,
    input                 u_valid,
    input  signed [W-1:0] l_re, l_im,
    input                 l_valid,
    output signed [W-1:0] o_re, o_im,
    output                o_valid
);

    assign o_re    = sel ? l_re : u_re;
    assign o_im    = sel ? l_im : u_im;
    assign o_valid = sel ? l_valid : u_valid;

endmodule
