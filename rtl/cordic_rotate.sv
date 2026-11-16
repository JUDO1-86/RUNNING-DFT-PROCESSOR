module cordic_rotate #(
    parameter W                 = 22,    
    parameter ITER              = 16,    
    parameter ANG_W             = 24,     
    parameter ANG_F             = 20,   
    parameter SINGLE_CYCLE_COMP = 0,     
    parameter PAPER_TRUNC_SCALE = 0     
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


    localparam signed [ANG_W-1:0] PI      = 24'sd3294199; 
    localparam signed [ANG_W-1:0] TWO_PI  = 24'sd6588397; 
    localparam signed [ANG_W-1:0] HALF_PI = 24'sd1647100; 


    localparam INVK_F = 24;

    reg signed [W-1:0]     x, y;
    reg signed [ANG_W-1:0] z;
    reg [4:0] i;
    reg busy;
    reg comp;          
    
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

    wire signed [ANG_W-1:0] theta_wrap =
        (theta >  PI) ? (theta - TWO_PI) :
        (theta < -PI) ? (theta + TWO_PI) : theta;

    wire gt_half_pi = (theta_wrap >  HALF_PI);
    wire lt_half_pi = (theta_wrap < -HALF_PI);

    wire signed [W-1:0]     x_pre = gt_half_pi ? -y_in : (lt_half_pi ?  y_in : x_in);
    wire signed [W-1:0]     y_pre = gt_half_pi ?  x_in : (lt_half_pi ? -x_in : y_in);
    wire signed [ANG_W-1:0] z_pre = gt_half_pi ? (theta_wrap - HALF_PI) :
                                    (lt_half_pi ? (theta_wrap + HALF_PI) : theta_wrap);

    wire signed [W-1:0] x_sh = x >>> i;
    wire signed [W-1:0] y_sh = y >>> i;

    wire signed [W-1:0] x_next = (z >= 0) ? (x - y_sh) : (x + y_sh);
    wire signed [W-1:0] y_next = (z >= 0) ? (y + x_sh) : (y - x_sh);
    wire signed [ANG_W-1:0] z_next = (z >= 0) ? (z - atan_tab(i)) : (z + atan_tab(i));

    wire signed [W-1:0] comp_in_x = SINGLE_CYCLE_COMP ? x_next : x;
    wire signed [W-1:0] comp_in_y = SINGLE_CYCLE_COMP ? y_next : y;

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
