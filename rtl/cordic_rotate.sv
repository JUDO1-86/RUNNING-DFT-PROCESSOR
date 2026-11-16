// Iterative rotational CORDIC (circular), one iteration per clock.
// Rotates (x_in, y_in) by theta and divides the result by the CORDIC gain K,
// so x_out + j*y_out = (x_in + j*y_in) * exp(j*theta).
//
// Features:
// 1. Full-circle angle convergence ([-2*pi, 2*pi] / all DFT bins k = 0..N-1)
//    via zero-cycle quadrant pre-rotation at start.
// 2. Multiplierless Canonical Signed-Digit (CSD) shift-and-add scale-factor
//    compensation (0 hardware multipliers, matching Table 2 of Ray & Dhar 2019).
// 3. Optional SINGLE_CYCLE_COMP (16 clocks total) or registered compensation
//    stage (17 clocks total, default for testbench compatibility), plus
//    optional PAPER_TRUNC_SCALE to reproduce the 16-bit unrounded truncation
//    decay curve in Fig. 6b.
module cordic_rotate #(
    parameter W                 = 22,     // data width (Q3.19 internal)
    parameter ITER              = 16,     // number of CORDIC iterations (m = 16)
    parameter ANG_W             = 24,     // angle width (Q3.20 radians)
    parameter ANG_F             = 20,     // angle fractional bits
    parameter SINGLE_CYCLE_COMP = 0,      // 1 = 16-cycle latency (Table 1), 0 = 17-cycle latency
    parameter PAPER_TRUNC_SCALE = 0       // 1 = 16-bit unrounded shift-add (Fig. 6b decay), 0 = 24-bit CSD
)
(
    input                      clk,
    input                      rst_n,
    input                      start,
    input  signed [W-1:0]      x_in,
    input  signed [W-1:0]      y_in,
    input  signed [ANG_W-1:0]  theta,
    output reg signed [W-1:0]  x_out,
    output reg signed [W-1:0]  y_out,
    output reg                 done
);

    // Angle constants in Q3.20 radians (scaled by 2^20)
    localparam signed [ANG_W-1:0] PI      = 24'sd3294199; // pi * 2^20
    localparam signed [ANG_W-1:0] TWO_PI  = 24'sd6588397; // 2*pi * 2^20
    localparam signed [ANG_W-1:0] HALF_PI = 24'sd1647100; // (pi/2) * 2^20

    // Scale factor 1/K = 0.6072529350088813 (K = 1.6467602581 for 16 iterations)
    // Exact 24-bit CSD shift-add decomposition of 10188014 = round((1/K) * 2^24):
    // 10188014 = 2^23 + 2^21 - 2^18 - 2^15 - 2^12 + 2^10 + 2^8 - 2^4 - 2^1
    localparam INVK_F = 24;

    reg signed [W-1:0]     x, y;
    reg signed [ANG_W-1:0] z;
    reg [4:0] i;
    reg busy;
    reg comp;          // compensation stage flag when SINGLE_CYCLE_COMP == 0

    // atan(2^-i) in radians, scaled by 2^20
    function signed [ANG_W-1:0] atan_tab(input [4:0] idx);
        case (idx)
            0:  atan_tab = 24'sd823550;
            1:  atan_tab = 24'sd486170;
            2:  atan_tab = 24'sd256879;
            3:  atan_tab = 24'sd130396;
            4:  atan_tab = 24'sd65451;
            5:  atan_tab = 24'sd32757;
            6:  atan_tab = 24'sd16383;
            7:  atan_tab = 24'sd8192;
            8:  atan_tab = 24'sd4096;
            9:  atan_tab = 24'sd2048;
            10: atan_tab = 24'sd1024;
            11: atan_tab = 24'sd512;
            12: atan_tab = 24'sd256;
            13: atan_tab = 24'sd128;
            14: atan_tab = 24'sd64;
            15: atan_tab = 24'sd32;
            16: atan_tab = 24'sd16;
            17: atan_tab = 24'sd8;
            18: atan_tab = 24'sd4;
            19: atan_tab = 24'sd2;
            default: atan_tab = 24'sd1;
        endcase
    endfunction

    // Step 1: Wrap angle theta from [-2*pi, 2*pi] into [-pi, pi]
    wire signed [ANG_W-1:0] theta_wrap =
        (theta >  PI) ? (theta - TWO_PI) :
        (theta < -PI) ? (theta + TWO_PI) : theta;

    // Step 2: Quadrant pre-rotation into [-pi/2, pi/2] (converges for all k = 0..N-1)
    wire gt_half_pi = (theta_wrap >  HALF_PI);
    wire lt_half_pi = (theta_wrap < -HALF_PI);

    wire signed [W-1:0]     x_pre = gt_half_pi ? -y_in : (lt_half_pi ?  y_in : x_in);
    wire signed [W-1:0]     y_pre = gt_half_pi ?  x_in : (lt_half_pi ? -x_in : y_in);
    wire signed [ANG_W-1:0] z_pre = gt_half_pi ? (theta_wrap - HALF_PI) :
                                    (lt_half_pi ? (theta_wrap + HALF_PI) : theta_wrap);

    // Barrel shifter for micro-rotations
    wire signed [W-1:0] x_sh = x >>> i;
    wire signed [W-1:0] y_sh = y >>> i;

    wire signed [W-1:0] x_next = (z >= 0) ? (x - y_sh) : (x + y_sh);
    wire signed [W-1:0] y_next = (z >= 0) ? (y + x_sh) : (y - x_sh);
    wire signed [ANG_W-1:0] z_next = (z >= 0) ? (z - atan_tab(i)) : (z + atan_tab(i));

    // Select source vector for scale-factor compensation
    wire signed [W-1:0] comp_in_x = SINGLE_CYCLE_COMP ? x_next : x;
    wire signed [W-1:0] comp_in_y = SINGLE_CYCLE_COMP ? y_next : y;

    // Multiplierless CSD shift-and-add scale-factor compensation (0 hardware multipliers)
    wire signed [W+25:0] ext_x = {{26{comp_in_x[W-1]}}, comp_in_x};
    wire signed [W+25:0] ext_y = {{26{comp_in_y[W-1]}}, comp_in_y};

    wire signed [W+25:0] prod_x = (ext_x <<< 23) + (ext_x <<< 21) - (ext_x <<< 18)
                                - (ext_x <<< 15) - (ext_x <<< 12) + (ext_x <<< 10)
                                + (ext_x <<< 8)  - (ext_x <<< 4)  - (ext_x <<< 1);

    wire signed [W+25:0] prod_y = (ext_y <<< 23) + (ext_y <<< 21) - (ext_y <<< 18)
                                - (ext_y <<< 15) - (ext_y <<< 12) + (ext_y <<< 10)
                                + (ext_y <<< 8)  - (ext_y <<< 4)  - (ext_y <<< 1);

    wire signed [W+25:0] half = 1 <<< (INVK_F - 1);

    wire signed [W-1:0] scaled_x_csd = (prod_x + half) >>> INVK_F;
    wire signed [W-1:0] scaled_y_csd = (prod_y + half) >>> INVK_F;

    // 16-bit unrounded shift-add scale compensation (matches Fig. 6b finite-precision decay: 39795/65536)
    wire signed [W-1:0] scaled_x_trunc = ((comp_in_x <<< 15) + (comp_in_x <<< 13) - (comp_in_x <<< 10)
                                        - (comp_in_x <<< 7)  - (comp_in_x <<< 4)  + (comp_in_x <<< 2)
                                        - comp_in_x) >>> 16;
    wire signed [W-1:0] scaled_y_trunc = ((comp_in_y <<< 15) + (comp_in_y <<< 13) - (comp_in_y <<< 10)
                                        - (comp_in_y <<< 7)  - (comp_in_y <<< 4)  + (comp_in_y <<< 2)
                                        - comp_in_y) >>> 16;

    wire signed [W-1:0] x_scaled = PAPER_TRUNC_SCALE ? scaled_x_trunc : scaled_x_csd;
    wire signed [W-1:0] y_scaled = PAPER_TRUNC_SCALE ? scaled_y_trunc : scaled_y_csd;

    always @(posedge clk) begin
        done <= 1'b0;

        if (!rst_n) begin
            busy  <= 1'b0;
            comp  <= 1'b0;
            i     <= 0;
            x     <= 0;
            y     <= 0;
            z     <= 0;
            x_out <= 0;
            y_out <= 0;
        end
        else if (start && !busy) begin
            x    <= x_pre;
            y    <= y_pre;
            z    <= z_pre;
            i    <= 0;
            busy <= 1'b1;
            comp <= 1'b0;
        end
        else if (busy && !comp) begin
            x <= x_next;
            y <= y_next;
            z <= z_next;
            i <= i + 1;

            if (i == ITER - 1) begin
                if (SINGLE_CYCLE_COMP) begin
                    x_out <= x_scaled;
                    y_out <= y_scaled;
                    done  <= 1'b1;
                    busy  <= 1'b0;
                end
                else begin
                    comp <= 1'b1;
                end
            end
        end
        else if (busy && comp) begin
            x_out <= x_scaled;
            y_out <= y_scaled;
            done  <= 1'b1;
            busy  <= 1'b0;
            comp  <= 1'b0;
        end
    end

endmodule